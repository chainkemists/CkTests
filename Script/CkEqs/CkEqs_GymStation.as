// Language=angelscript

//============================================================================
// CK EQS GYM - STATION ENTITY SCRIPT
//============================================================================
//
// One station class drives every EQS scenario via a Scenario enum. Each
// scenario builds a different FCk_Eqs_QueryParams (generator + test set + run
// mode) and re-issues the query on a 5-second cadence. Some scenarios spawn
// extra entities in DoConstruct (target rings, probe markers, LOS blockers).
//
// Display panel shows: scenario name, candidate count, best location, status,
// run #, and the time-to-next-restart.
//============================================================================

// AS-internal enum - UENUM() macro is not available in AngelScript; plain `enum`
// is the right form (no `class` keyword, values accessed as Name::Value per
// CkGoapEmpire_Station's ECk_GoapEmpire_Phase precedent).
enum ECkEqsGym_Scenario
{
    SimpleGrid_Distance,    // 5x5 SimpleGrid, Distance test, SingleBest
    Donut_Dot,              // 3-ring Donut, Dot test, SingleBest
    Cone_Generator,         // Cone generator, no tests, AllMatchingSorted
    Immediate_Sync,         // Same as SimpleGrid_Distance but via Request_RunQuery_Immediate
    RandomBest5Pct,         // SimpleGrid + Distance, RunMode RandomBest5Pct

    // v1.1 generators / tests.
    NavProjection,          // SimpleGrid + _ProjectOntoNav=true, snaps to floor's navmesh
    OnCircle,               // 8 points evenly spaced on a 300uu ring, Distance scoring
    VolumeCheck,            // SimpleGrid filtered by AABB centred on station
    Random,                 // SimpleGrid + Distance + Random tiebreaker, AllMatchingSorted

    // Existing test types that didn't have a v1.0 station.
    Trace,                  // SimpleGrid + LineTrace LOS test against a spawned wall
    EntitiesWithTag,        // Generator returns 5 spawned target entities, Distance scoring
    Overlap                 // SimpleGrid + Overlap test against 3 spawned probe markers
}

USTRUCT()
struct FCkEqsGym_StationSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    FString StationTitle;

    UPROPERTY()
    FString StationDescription;

    UPROPERTY()
    ECkEqsGym_Scenario Scenario = ECkEqsGym_Scenario::SimpleGrid_Distance;

    UPROPERTY()
    float RestartIntervalSeconds = 5.0f;
}

// ====================================================================================================================

class UCk_EntityScript_EqsGym_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;
    UPROPERTY(ExposeOnSpawn) FString    StationTitle;
    UPROPERTY(ExposeOnSpawn) FString    StationDescription;
    UPROPERTY(ExposeOnSpawn) ECkEqsGym_Scenario Scenario = ECkEqsGym_Scenario::SimpleGrid_Distance;
    UPROPERTY(ExposeOnSpawn) float      RestartIntervalSeconds = 5.0f;

    // Latest result snapshot (updated on each OnComplete fire / on Immediate return).
    private bool             _HasResult = false;
    private FVector          _BestLocation = FVector::ZeroVector;
    private int32            _CandidateCount = 0;
    private bool             _Failed = false;
    private int32            _RunCount = 0;
    private float            _TimeSinceLast = 0.0f;
    private bool             _IsImmediate = false;

    // Most-recent query handle (deferred path: filled in OnQueryComplete; immediate path: filled
    // in Capture_Result). Set_AutoDestroy(false) on the deferred request keeps the query entity
    // alive past Cleanup so the user can inspect it in the debugger; we manually destroy it on the
    // next cycle to keep the in-world list at one query per station instead of accumulating.
    private FCk_Handle_EqsQuery _LastQueryHandle;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        InHandle.Set_DebugName(n"EqsStation");
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        // Per-scenario one-shot world setup. Targets / probes live as child entities
        // owned by this station so they're cleaned up when the station entity goes away.
        if (Scenario == ECkEqsGym_Scenario::EntitiesWithTag)
        {
            Spawn_TargetEntities(InHandle);
        }
        else if (Scenario == ECkEqsGym_Scenario::Overlap)
        {
            Spawn_OverlapMarkers(InHandle);
        }
        else if (Scenario == ECkEqsGym_Scenario::Trace)
        {
            Spawn_TraceBlocker(InHandle);
        }

        Request_StartScenario();
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // Spawn 5 tagged child entities arranged on a 250uu ring around the station so the
    // EntitiesWithTag generator has something to find. The Distance test then orders them
    // by closeness to the querier (the station entity itself).
    private void Spawn_TargetEntities(FCk_Handle& InStation)
    {
        const auto Radius = 250.0f;
        const auto NumTargets = 5;
        const auto BaseLocation = InitialTransform.GetLocation();
        const auto TargetTag = utils_gameplay_tag::ResolveGameplayTag(n"Gym.Eqs.Target");

        for (int32 i = 0; i < NumTargets; i++)
        {
            const auto Yaw = (360.0f / float(NumTargets)) * float(i);
            const auto Direction = FRotator(0.0f, Yaw, 0.0f).Vector();
            const auto TargetLocation = BaseLocation + Direction * Radius;
            const auto TargetTransform = FTransform(FRotator::ZeroRotator, TargetLocation);

            auto Target = utils_entity_lifetime::Request_CreateEntity(InStation);
            auto TargetName = FName(f"Target_{i}");
            Target.Set_DebugName(TargetName);
            Target.Request_OverrideToSelf();
            utils_transform::Add(Target, TargetTransform, ECk_Replication::DoesNotReplicate);
            utils_entity_tag::Add_UsingGameplayTag(Target, TargetTag);
        }
    }

    // Spawn 1 box probe co-located with the visible wall the player controller spawned.
    // The probe is what the CkSpatialQuery line-trace actually intersects (actor collision
    // alone isn't visible to the probe-trace system), so this is what makes the Trace
    // test's filter eliminate candidates whose LOS is blocked.
    //
    // Wall offset/scale must match SpawnTraceWall in CkEqs_GymPlayerController.as.
    private void Spawn_TraceBlocker(FCk_Handle& InStation)
    {
        const auto BlockerProbeName = utils_gameplay_tag::ResolveGameplayTag(n"Gym.Eqs.TraceBlocker");
        const auto BaseLocation = InitialTransform.GetLocation();
        const auto BlockerOffset = FVector(150.0f, 0.0f, 100.0f);   // matches SpawnTraceWall
        const auto BlockerHalfExtent = FVector(25.0f, 250.0f, 150.0f); // 50 x 500 x 300 cm

        const auto BlockerTransform = FTransform(FRotator::ZeroRotator, BaseLocation + BlockerOffset);

        auto Blocker = utils_entity_lifetime::Request_CreateEntity(InStation);
        Blocker.Set_DebugName(n"TraceBlocker");
        Blocker.Request_OverrideToSelf();
        auto BlockerXform = utils_transform::Add(Blocker, BlockerTransform, ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(BlockerProbeName);
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
        auto DebugInfo = FCk_Probe_DebugInfo();
        utils_probe::Add_Box(BlockerXform, BlockerHalfExtent, ProbeParams, DebugInfo);
    }

    // Spawn 3 sphere probes carrying the Gym.Eqs.OverlapMarker probe-name. The Overlap test's
    // _OverlapFilter matches that name so candidates near a marker score higher.
    private void Spawn_OverlapMarkers(FCk_Handle& InStation)
    {
        const auto MarkerProbeName = utils_gameplay_tag::ResolveGameplayTag(n"Gym.Eqs.OverlapMarker");
        const auto Radius = 60.0f;
        const auto BaseLocation = InitialTransform.GetLocation();
        // Three offsets near the SimpleGrid footprint (which is 5x5 @ 100uu spacing).
        auto Offsets = TArray<FVector>();
        Offsets.Add(FVector(-100.0f,  100.0f, 0.0f));
        Offsets.Add(FVector(   0.0f,    0.0f, 0.0f));
        Offsets.Add(FVector( 100.0f, -100.0f, 0.0f));

        for (int32 i = 0; i < Offsets.Num(); i++)
        {
            const auto MarkerTransform = FTransform(FRotator::ZeroRotator, BaseLocation + Offsets[i]);

            auto Marker = utils_entity_lifetime::Request_CreateEntity(InStation);
            auto MarkerName = FName(f"OverlapMarker_{i}");
            Marker.Set_DebugName(MarkerName);
            Marker.Request_OverrideToSelf();
            auto MarkerXform = utils_transform::Add(Marker, MarkerTransform, ECk_Replication::DoesNotReplicate);

            auto ProbeParams = FCk_Fragment_Probe_ParamsData(MarkerProbeName);
            ProbeParams.Set_MotionType(ECk_MotionType::Static);
            ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
            auto DebugInfo = FCk_Probe_DebugInfo();
            utils_probe::Add_Sphere(MarkerXform, Radius, ProbeParams, DebugInfo);
        }
    }

    private void Request_StartScenario()
    {
        auto SelfEntity = ck::ToEntity(this);
        _RunCount++;
        _TimeSinceLast = 0.0f;
        _IsImmediate = (Scenario == ECkEqsGym_Scenario::Immediate_Sync);

        // Destroy the previous query before issuing a new one. Without this, deferred queries
        // (with Set_AutoDestroy(false)) and Immediate queries would pile up on the station entity
        // every 5 seconds. Doing it here also fixes the original "queries flicker" UX problem in
        // the debugger - the debugger now sees one stable query per station instead of a brief
        // 1-2 frame flash followed by 5 seconds of nothing.
        if (ck::IsValid(_LastQueryHandle))
        {
            auto OldQuery = FCk_Handle(_LastQueryHandle);
            utils_entity_lifetime::Request_DestroyEntity(OldQuery);
            _LastQueryHandle = utils_eqs::Get_InvalidHandle();
        }

        auto QueryParams = Build_QueryParams(SelfEntity);

        if (_IsImmediate)
        {
            // Synchronous path: returns a typed query handle with results already written.
            // Does NOT broadcast OnComplete (P3-E5) - read accessors directly.
            auto QueryHandle = utils_eqs::Request_RunQuery_Immediate(SelfEntity, QueryParams);
            _LastQueryHandle = QueryHandle;
            Capture_Result(QueryHandle);
        }
        else
        {
            // Deferred path: bind OnComplete on the request, fire and forget. AutoDestroy=false
            // keeps the query entity alive past Cleanup so the user can inspect it in the
            // debugger - we own the destroy on the next cycle (above).
            auto Request = FCk_Request_Eqs_RunQuery(QueryParams);
            Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnQueryComplete"));
            Request.Set_AutoDestroy(false);
            utils_eqs::Request_RunQuery(SelfEntity, Request);
        }
    }

    private FCk_Eqs_QueryParams Build_QueryParams(const FCk_Handle& InQuerier)
    {
        auto Tests = TArray<FCk_Eqs_TestParams>();

        if (Scenario == ECkEqsGym_Scenario::SimpleGrid_Distance ||
            Scenario == ECkEqsGym_Scenario::Immediate_Sync ||
            Scenario == ECkEqsGym_Scenario::RandomBest5Pct)
        {
            auto Generator = FCk_Eqs_GeneratorParams();
            Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
            Generator.Set_SpaceBetween(100.0f);
            Generator.Set_GridHalfSize(200.0f);  // 5x5 = 25 candidates

            // Distance test - closer to querier scores higher (InverseLinear).
            auto Distance = FCk_Eqs_TestParams();
            Distance.Set_TestType(ECk_Eqs_TestType::Distance);
            Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);
            Distance.Set_DistanceMode(ECk_Eqs_DistanceMode::Distance3D);
            auto Scoring = FCk_Eqs_ScoringConfig();
            Scoring.Set_ScoringEquation(ECk_Eqs_ScoringEquation::InverseLinear);
            Distance.Set_ScoringConfig(Scoring);
            Tests.Add(Distance);

            auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
            Params.Set_RunMode(Scenario == ECkEqsGym_Scenario::RandomBest5Pct
                ? ECk_Eqs_RunMode::RandomBest5Pct
                : ECk_Eqs_RunMode::SingleBest);
            return Params;
        }

        if (Scenario == ECkEqsGym_Scenario::Donut_Dot)
        {
            auto Generator = FCk_Eqs_GeneratorParams();
            Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::Donut);
            Generator.Set_InnerRadius(200.0f);
            Generator.Set_OuterRadius(500.0f);
            Generator.Set_NumRings(3);
            Generator.Set_PointsPerRing(8);
            Generator.Set_ArcAngle(360.0f);

            // Dot test - forward of the querier scores highest.
            auto Dot = FCk_Eqs_TestParams();
            Dot.Set_TestType(ECk_Eqs_TestType::Dot);
            Dot.Set_Purpose(ECk_Eqs_TestPurpose::Score);
            Dot.Set_DotMode(ECk_Eqs_DotMode::NormalizedDot);
            auto Scoring = FCk_Eqs_ScoringConfig();
            Scoring.Set_ScoringEquation(ECk_Eqs_ScoringEquation::Linear);
            Dot.Set_ScoringConfig(Scoring);
            Tests.Add(Dot);

            auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
            Params.Set_RunMode(ECk_Eqs_RunMode::SingleBest);
            return Params;
        }

        if (Scenario == ECkEqsGym_Scenario::Cone_Generator)
        {
            // Cone_Generator: no tests, AllMatchingSorted to surface every candidate.
            auto Generator = FCk_Eqs_GeneratorParams();
            Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::Cone);
            Generator.Set_ConeDegrees(90.0f);
            Generator.Set_ConeRange(500.0f);
            Generator.Set_ConeAngleStep(15.0f);
            Generator.Set_ConePointSpacing(100.0f);

            // A neutral Score-only Distance test satisfies the non-empty-Tests requirement
            // without changing which candidates survive.
            auto Distance = FCk_Eqs_TestParams();
            Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);
            Tests.Add(Distance);

            auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
            Params.Set_RunMode(ECk_Eqs_RunMode::AllMatchingSorted);
            return Params;
        }

        if (Scenario == ECkEqsGym_Scenario::NavProjection)
        {
            // SimpleGrid + project candidates onto the floor's navmesh. Without the
            // floor's bake, every candidate would be dropped; with it, all candidates
            // snap down to navmesh height and survive.
            auto Generator = FCk_Eqs_GeneratorParams();
            Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
            Generator.Set_SpaceBetween(100.0f);
            Generator.Set_GridHalfSize(200.0f);
            Generator.Set_ProjectOntoNav(true);
            Generator.Set_NavProjectionSearchHalfExtentUu(200.0f);

            auto Distance = FCk_Eqs_TestParams();
            Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);
            Tests.Add(Distance);

            auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
            Params.Set_RunMode(ECk_Eqs_RunMode::AllMatching);
            return Params;
        }

        if (Scenario == ECkEqsGym_Scenario::OnCircle)
        {
            // 8 evenly-spaced points on a 300uu ring. Distance from the querier scores
            // the picks (all at radius 300, so scoring is degenerate but visualises the
            // generator nicely).
            auto Generator = FCk_Eqs_GeneratorParams();
            Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::OnCircle);
            Generator.Set_CircleRadius(300.0f);
            Generator.Set_NumPointsOnCircle(8);
            Generator.Set_CircleArcAngle(360.0f);

            auto Distance = FCk_Eqs_TestParams();
            Distance.Set_TestType(ECk_Eqs_TestType::Distance);
            Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);
            Tests.Add(Distance);

            auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
            Params.Set_RunMode(ECk_Eqs_RunMode::AllMatchingSorted);
            return Params;
        }

        if (Scenario == ECkEqsGym_Scenario::VolumeCheck)
        {
            // SimpleGrid (25 candidates) filtered by an AABB at the station origin.
            // HalfExtent = (150, 150, 50) keeps the inner 3x3 = 9 candidates.
            auto Generator = FCk_Eqs_GeneratorParams();
            Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
            Generator.Set_SpaceBetween(100.0f);
            Generator.Set_GridHalfSize(200.0f);

            auto Volume = FCk_Eqs_TestParams();
            Volume.Set_TestType(ECk_Eqs_TestType::VolumeCheck);
            Volume.Set_Purpose(ECk_Eqs_TestPurpose::Filter);
            Volume.Set_VolumeCheck_WorldCenter(InitialTransform.GetLocation());
            Volume.Set_VolumeCheck_HalfExtent(FVector(150.0f, 150.0f, 50.0f));
            Volume.Set_VolumeCheck_Inverted(false);
            // Raise FilterMin so raw=0 (outside box) candidates fail the Minimum filter.
            auto FilterCfg = FCk_Eqs_FilterConfig();
            FilterCfg.Set_FilterMin(0.5f);
            Volume.Set_FilterConfig(FilterCfg);
            Tests.Add(Volume);

            auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
            Params.Set_RunMode(ECk_Eqs_RunMode::AllMatching);
            return Params;
        }

        if (Scenario == ECkEqsGym_Scenario::Random)
        {
            // SimpleGrid + Distance score + Random tiebreaker. Distance dominates; Random
            // multiplies a small per-candidate factor in so equal-distance candidates aren't
            // ordered deterministically.
            auto Generator = FCk_Eqs_GeneratorParams();
            Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
            Generator.Set_SpaceBetween(100.0f);
            Generator.Set_GridHalfSize(200.0f);

            auto Distance = FCk_Eqs_TestParams();
            Distance.Set_TestType(ECk_Eqs_TestType::Distance);
            Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);
            auto DistanceScoring = FCk_Eqs_ScoringConfig();
            DistanceScoring.Set_ScoringEquation(ECk_Eqs_ScoringEquation::InverseLinear);
            Distance.Set_ScoringConfig(DistanceScoring);
            Tests.Add(Distance);

            auto Random = FCk_Eqs_TestParams();
            Random.Set_TestType(ECk_Eqs_TestType::Random);
            Random.Set_Purpose(ECk_Eqs_TestPurpose::Score);
            Random.Set_Weight(0.1f);  // small enough to be a tiebreaker, not a primary
            Tests.Add(Random);

            auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
            Params.Set_RunMode(ECk_Eqs_RunMode::AllMatchingSorted);
            return Params;
        }

        if (Scenario == ECkEqsGym_Scenario::Trace)
        {
            // SimpleGrid + LineTrace LOS test. The player controller spawns an obstacle wall
            // alongside this station; candidates whose line-of-sight from the querier is blocked
            // by the wall fail the trace and are dropped.
            auto Generator = FCk_Eqs_GeneratorParams();
            Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
            Generator.Set_SpaceBetween(100.0f);
            Generator.Set_GridHalfSize(200.0f);

            auto Trace = FCk_Eqs_TestParams();
            Trace.Set_TestType(ECk_Eqs_TestType::Trace);
            Trace.Set_Purpose(ECk_Eqs_TestPurpose::Filter);
            Trace.Set_TraceMode(ECk_Eqs_TraceMode::LineTrace);
            // The trace must hit only the blocker probe (TraceFilter matches its probe-name).
            auto TraceFilter = FGameplayTagContainer();
            TraceFilter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Gym.Eqs.TraceBlocker"));
            Trace.Set_TraceFilter(TraceFilter);
            // FilterMin=0.5 so raw=0 (LOS blocked) candidates fail the Minimum filter.
            auto FilterCfg = FCk_Eqs_FilterConfig();
            FilterCfg.Set_FilterMin(0.5f);
            Trace.Set_FilterConfig(FilterCfg);
            Tests.Add(Trace);

            auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
            Params.Set_RunMode(ECk_Eqs_RunMode::AllMatching);
            return Params;
        }

        if (Scenario == ECkEqsGym_Scenario::EntitiesWithTag)
        {
            // Generator returns the 5 target entities the station spawned in DoConstruct.
            // Distance test orders them by proximity to the querier.
            auto Generator = FCk_Eqs_GeneratorParams();
            Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::EntitiesWithTag);
            Generator.Set_RequiredEntityTag(utils_gameplay_tag::ResolveGameplayTag(n"Gym.Eqs.Target"));

            auto Distance = FCk_Eqs_TestParams();
            Distance.Set_TestType(ECk_Eqs_TestType::Distance);
            Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);
            auto DistanceScoring = FCk_Eqs_ScoringConfig();
            DistanceScoring.Set_ScoringEquation(ECk_Eqs_ScoringEquation::InverseLinear);
            Distance.Set_ScoringConfig(DistanceScoring);
            Tests.Add(Distance);

            auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
            Params.Set_RunMode(ECk_Eqs_RunMode::SingleBest);
            return Params;
        }

        // Overlap: SimpleGrid + Overlap test against the 3 markers DoConstruct spawned.
        // Score-only purpose: candidates near markers get a higher overlap count and rank
        // higher in AllMatchingSorted.
        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(100.0f);
        Generator.Set_GridHalfSize(200.0f);

        auto Overlap = FCk_Eqs_TestParams();
        Overlap.Set_TestType(ECk_Eqs_TestType::Overlap);
        Overlap.Set_Purpose(ECk_Eqs_TestPurpose::Score);
        Overlap.Set_OverlapRadius(80.0f);
        auto OverlapFilter = FGameplayTagContainer();
        OverlapFilter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Gym.Eqs.OverlapMarker"));
        Overlap.Set_OverlapFilter(OverlapFilter);
        Tests.Add(Overlap);

        auto Params = FCk_Eqs_QueryParams(InQuerier, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::AllMatchingSorted);
        return Params;
    }

    UFUNCTION()
    private void OnQueryComplete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        _HasResult = InResults.Get_HasResults();
        _CandidateCount = InResults.Get_Candidates().Num();
        _BestLocation = InResults.Get_BestLocation();

        // Cast typed handle to generic to inspect tags safely.
        auto AsGeneric = FCk_Handle(InQueryHandle);
        _Failed = utils_eqs::Get_IsFailed(InQueryHandle);

        // Stash the handle so we can destroy this query at the start of the next cycle (see
        // Request_StartScenario). With AutoDestroy=false on the request, the query entity
        // survives past Cleanup; we own its destruction.
        _LastQueryHandle = InQueryHandle;
    }

    private void Capture_Result(FCk_Handle_EqsQuery InQueryHandle)
    {
        // Immediate path: results are already written; read via accessors.
        _HasResult = utils_eqs::Get_HasResults(InQueryHandle);
        auto Candidates = utils_eqs::Get_AllCandidates(InQueryHandle);
        _CandidateCount = Candidates.Num();
        _BestLocation = utils_eqs::Get_BestLocation(InQueryHandle);
        _Failed = utils_eqs::Get_IsFailed(InQueryHandle);
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto DeltaSeconds = float(InDeltaT.Get_Seconds());
        _TimeSinceLast += DeltaSeconds;

        if (_TimeSinceLast >= RestartIntervalSeconds)
        {
            Request_StartScenario();
        }

        Update_Display();
    }

    private void Update_Display()
    {
        auto SelfEntity = ck::ToEntity(this);

        auto Mode = _IsImmediate ? "IMMEDIATE" : "DEFERRED";
        auto Status = _Failed ? "FAILED" : (_HasResult ? "READY" : "PENDING");
        auto SecondsLeft = int(RestartIntervalSeconds - _TimeSinceLast) + 1;

        auto Display = f"Scenario: {Get_ScenarioName()}\n";
        Display = f"{Display}Mode: {Mode}    Run #{_RunCount}\n";
        Display = f"{Display}Status: {Status}\n";
        Display = f"{Display}Candidates: {_CandidateCount}\n";

        if (_HasResult)
        {
            Display = f"{Display}Best: ({int(_BestLocation.X)}, {int(_BestLocation.Y)}, {int(_BestLocation.Z)})\n";
        }

        Display = f"{Display}\nRestarting in {SecondsLeft}s...";

        CkGym_Common::Update_StationDisplay(SelfEntity, StationTitle, Display, StationDescription);
    }

    private FString Get_ScenarioName()
    {
        if (Scenario == ECkEqsGym_Scenario::SimpleGrid_Distance) { return "SimpleGrid + Distance"; }
        if (Scenario == ECkEqsGym_Scenario::Donut_Dot)           { return "Donut + Dot"; }
        if (Scenario == ECkEqsGym_Scenario::Cone_Generator)      { return "Cone (no tests)"; }
        if (Scenario == ECkEqsGym_Scenario::Immediate_Sync)      { return "Immediate Sync"; }
        if (Scenario == ECkEqsGym_Scenario::RandomBest5Pct)      { return "RandomBest5Pct"; }
        if (Scenario == ECkEqsGym_Scenario::NavProjection)       { return "NavProjection"; }
        if (Scenario == ECkEqsGym_Scenario::OnCircle)            { return "OnCircle"; }
        if (Scenario == ECkEqsGym_Scenario::VolumeCheck)         { return "VolumeCheck"; }
        if (Scenario == ECkEqsGym_Scenario::Random)              { return "Random Tiebreaker"; }
        if (Scenario == ECkEqsGym_Scenario::Trace)               { return "Trace (LOS)"; }
        if (Scenario == ECkEqsGym_Scenario::EntitiesWithTag)     { return "EntitiesWithTag"; }
        if (Scenario == ECkEqsGym_Scenario::Overlap)             { return "Overlap"; }
        return "UNKNOWN";
    }
}
