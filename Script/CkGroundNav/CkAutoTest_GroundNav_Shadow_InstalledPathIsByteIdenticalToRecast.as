// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: SHADOWING CHANGES NOTHING THE CALLER SEES
//============================================================================
//
// The whole promise of shadow mode is that turning it on is invisible. A second
// provider answers the same query, its answer is measured and thrown away, and
// the route that installs is the one that would have installed anyway. If that
// is not exactly true then every number a shadow run collects was collected
// about a world that no longer behaves like the one being measured.
//
// So this runs the SAME population of queries twice against the SAME world:
// leg A with shadowing off, leg B with GroundNav shadowing Recast, and holds
// the two to byte equality - waypoint counts, every waypoint component, the
// status and the fail reason.
//
// THE ONE HAZARD WORTH NAMING. Two legs disagree for exactly two reasons: the
// shadow seam leaked, or the two legs did not plan the same query. Only the
// first is interesting, so the second is measured separately and first: every
// query records the start Recast actually planned from (the result's own
// _LastAgentLocation) and the target it planned to, and those are asserted
// equal BEFORE any route is compared. A walker that drifted between legs then
// fails on a message that says so, rather than on a waypoint mismatch that
// reads like a shadow-mode defect.
//
// The agent is also built so it cannot drift: it is spawned on a point already
// projected onto the navmesh, it carries velocity and acceleration but the
// euler integrator is never started, so nothing turns steering into position.
// One agent is alive at a time in both legs, so neither leg's queries plan
// around the other's standing bodies.
//
// Fixture, the origin floor, because Recast is the provider under test and only
// the level's own NavMeshBoundsVolume_1 / StaticMeshActor_1 pair has a navmesh.
// A fresh Y band would have GroundNav ground and no Recast navmesh at all,
// which is the one thing this test cannot substitute for. The GroundNav field
// the shadow searches is therefore baked over that SAME floor: a volume placed
// at the rim centre, over the floor's own collision, added to the Jolt static
// world first if the level sweep has not already put it there.
//
// The count assertion at the end is what makes leg B a shadow run rather than
// merely a second Recast run: the fixture must have recorded at least one
// comparison per query. A leg B that quietly shadowed nothing would satisfy
// every equality above it.
//============================================================================

class UCk_AutoTest_GroundNav_Shadow_InstalledPathIsByteIdenticalToRecast : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 180.0f;

    //------------------------------------------------------------------------
    // Fixture shape
    //------------------------------------------------------------------------

    private const int32 QueryCount = 3;

    // Endpoints stay this far inside the baked box, so no query start or goal
    // sits on the eroded edge of either provider's own boundary.
    private const float EndpointInset = 0.55;

    // The GroundNav volume is clamped to this half extent so the bake stays a
    // few tiles rather than however large the level floor happens to be.
    private const float MaxFieldHalfXY = 900.0;

    private const float FieldFloorDropUu = 200.0;
    private const float FieldCeilingRiseUu = 500.0;

    private const float ProjectionExtentUu = 300.0;
    private const float ProjectionVerticalExtentUu = 500.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;

    private const float CellSizeUu = 25.0;
    private const float StepHeightUu = 10.0;
    private const float TileSizeUu = 500.0;

    private const float ProfileHalfHeightUu = 96.0;

    private const int32 BuildFrameBudget = 3600;
    private const int32 LegFrameBudget = 3600;
    private const int32 ProjectFrameBudget = 900;

    private const FName FixtureName = n"Shadow_ByteIdentical";

    //------------------------------------------------------------------------
    // Resolved fixture
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;

    private AStaticMeshActor _FloorActor;
    private bool _FloorBakedByThisTest = false;

    private FVector _FieldCentre = FVector::ZeroVector;
    private float _FieldHalfXY = 0.0;
    private float _FloorTopZ = 0.0;

    private TArray<FVector> _Starts;
    private TArray<FVector> _Goals;

    private FCk_Handle _VolumeEntity;
    private FCk_Handle_GroundNavVolume _Volume;
    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private ECk_NavSurface_ShadowMode _ShadowModeBefore = ECk_NavSurface_ShadowMode::Off;
    private bool _WorldStateSwapped = false;
    private bool _FixtureOpened = false;

    //------------------------------------------------------------------------
    // Leg state
    //------------------------------------------------------------------------

    // 0 while leg A (shadow off) runs, 1 while leg B (shadow on) runs.
    private int32 _Leg = 0;
    private int32 _QueryIndex = 0;

    private FCk_Handle _AgentEntity;
    private FCk_Handle_CrowdAgent _Agent;
    private bool _AgentAlive = false;
    private bool _ResultCaptured = false;

    private TArray<int32> _WaypointCountA;
    private TArray<int32> _WaypointCountB;
    private TArray<FVector> _WaypointsA;
    private TArray<FVector> _WaypointsB;
    private TArray<ECk_Nav_PathStatus> _StatusA;
    private TArray<ECk_Nav_PathStatus> _StatusB;
    private TArray<ECk_Nav_PathFailReason> _ReasonA;
    private TArray<ECk_Nav_PathFailReason> _ReasonB;
    private TArray<FVector> _PlannedFromA;
    private TArray<FVector> _PlannedFromB;
    private TArray<FVector> _PlannedToA;
    private TArray<FVector> _PlannedToB;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured before anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();
        _ShadowModeBefore = utils_nav_surface::Get_ShadowMode();

        Add_Step(          "find the level floor and the box both providers will cover", n"Step_FindFloor");
        Add_Step(          "ask the surface and the navmesh to build",                   n"Step_KickRebuild");
        Add_Step_WaitUntil("every query endpoint projects onto the navmesh",             n"Check_EndpointsProject", ProjectFrameBudget);
        Add_Step(          "put the floor in the Jolt static world if nothing else has", n"Step_EnsureFloorIsStaticWorldGeometry");
        Add_Step(          "bake a GroundNav field over the same floor",                 n"Step_RequestFieldBake");
        Add_Step_WaitUntil("the field reports itself built",                             n"Check_FieldBuilt", BuildFrameBudget);
        Add_Step(          "plan on Recast alone",                                       n"Step_BeginLegA");
        Add_Step_WaitUntil("leg A answers every query",                                  n"Check_LegComplete", LegFrameBudget);
        Add_Step(          "turn GroundNav shadowing on and plan again",                 n"Step_BeginLegB");
        Add_Step_WaitUntil("leg B answers every query and every shadow is compared",     n"Check_LegComplete", LegFrameBudget);
        Add_Step(          "hold the two legs to byte equality",                         n"Step_CompareLegs");
        Add_Step(          "hand the world back",                                        n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Staging
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_FindFloor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FloorActor = assets::StaticMeshActor_1().Get();

        if (!System::IsValid(_FloorActor))
        {
            FinishFailure("staging failed: the level floor StaticMeshActor_1 could not be reached - the fixture, not shadow mode, is broken");
            return;
        }

        auto FloorOrigin = FVector::ZeroVector;
        auto FloorExtent = FVector::ZeroVector;
        _FloorActor.GetActorBounds(false, FloorOrigin, FloorExtent);

        auto Volume = assets::NavMeshBoundsVolume_1().Get();

        if (!System::IsValid(Volume))
        {
            FinishFailure("staging failed: the level nav bounds volume NavMeshBoundsVolume_1 could not be reached - the fixture, not shadow mode, is broken");
            return;
        }

        auto VolumeOrigin = FVector::ZeroVector;
        auto VolumeExtent = FVector::ZeroVector;
        Volume.GetActorBounds(false, VolumeOrigin, VolumeExtent);

        const auto FloorMin = FloorOrigin - FloorExtent;
        const auto FloorMax = FloorOrigin + FloorExtent;
        const auto VolumeMin = VolumeOrigin - VolumeExtent;
        const auto VolumeMax = VolumeOrigin + VolumeExtent;

        const auto RimMin = FVector(Math::Max(FloorMin.X, VolumeMin.X), Math::Max(FloorMin.Y, VolumeMin.Y), FloorMin.Z);
        const auto RimMax = FVector(Math::Min(FloorMax.X, VolumeMax.X), Math::Min(FloorMax.Y, VolumeMax.Y), FloorMax.Z);

        const auto RimCentre = (RimMin + RimMax) * 0.5;
        const auto RimHalf = (RimMax - RimMin) * 0.5;

        if (RimHalf.X <= 0.0 || RimHalf.Y <= 0.0)
        {
            FinishFailure(f"staging failed: the floor and the nav bounds do not overlap (rim half extent {RimHalf})");
            return;
        }

        // Narrowed explicitly rather than left to an implicit conversion: FVector components are
        // float64 and every tunable above is float32, and a Math::Min straddling the two is an
        // overload resolution nobody should have to guess at.
        _FloorTopZ = float(FloorOrigin.Z + FloorExtent.Z);
        _FieldCentre = FVector(RimCentre.X, RimCentre.Y, _FloorTopZ);

        const auto RimHalfXY = float(Math::Min(RimHalf.X, RimHalf.Y));
        _FieldHalfXY = Math::Min(RimHalfXY, MaxFieldHalfXY);

        const auto Reach = _FieldHalfXY * EndpointInset;

        // Three fixed, well separated pairs. No generator and no seed: two runs of this test must
        // ask the same three questions, and a run against a captured report must ask them too.
        Add_QueryPair(-Reach, -Reach,  Reach,  Reach);
        Add_QueryPair( Reach, -Reach, -Reach,  Reach);
        Add_QueryPair(-Reach,   0.0f,  Reach,   0.0f);

        ck::nav::Display(f"[SHADOW-AB] fixture: centre={_FieldCentre} halfXY={_FieldHalfXY} floorTopZ={_FloorTopZ} queries={QueryCount}");
    }

    // Offsets are relative to the field centre in X and Y; Z is the floor's own top face, which is
    // then replaced by whatever the navmesh projects the point onto.
    private void Add_QueryPair(float InStartX, float InStartY, float InGoalX, float InGoalY)
    {
        _Starts.Add(FVector(_FieldCentre.X + InStartX, _FieldCentre.Y + InStartY, _FloorTopZ));
        _Goals.Add(FVector(_FieldCentre.X + InGoalX, _FieldCentre.Y + InGoalY, _FloorTopZ));
    }

    UFUNCTION()
    private void Step_KickRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);
    }

    // Projection through utils_nav is the projection FindPath itself performs, so it is the
    // readiness that actually gates the measurement. Every endpoint is snapped IN PLACE here: an
    // agent spawned on an already-projected point gives grounding nothing to correct, which is one
    // fewer way the two legs could start from different places.
    UFUNCTION()
    private void Check_EndpointsProject(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Snapped = FVector::ZeroVector;

        for (int32 Index = 0; Index < _Starts.Num(); Index++)
        {
            if (utils_nav::Try_ProjectOntoNavmesh(InHandle, _Starts[Index], float32(ProjectionExtentUu), Snapped, float32(ProjectionVerticalExtentUu)) == false)
            {
                Res.Set(false);
                return;
            }
            _Starts[Index] = Snapped;

            if (utils_nav::Try_ProjectOntoNavmesh(InHandle, _Goals[Index], float32(ProjectionExtentUu), Snapped, float32(ProjectionVerticalExtentUu)) == false)
            {
                Res.Set(false);
                return;
            }
            _Goals[Index] = Snapped;
        }

        Res.Set(true);
    }

    // The GroundNav bake reads the Jolt static world, not UE collision. Whether the level sweep has
    // already put the floor there is a property of the host project's settings rather than of this
    // test, so it is probed rather than assumed - and only what this test added is removed again.
    UFUNCTION()
    private void Step_EnsureFloorIsStaticWorldGeometry(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto ProbeStart = FVector(_FieldCentre.X, _FieldCentre.Y, _FloorTopZ + 200.0);
        const auto ProbeEnd = FVector(_FieldCentre.X, _FieldCentre.Y, _FloorTopZ - 200.0);

        if (utils_jolt_static_world::Get_RayCastStaticWorld(ProbeStart, ProbeEnd).Get_HasHit())
        {
            ck::nav::Display("[SHADOW-AB] the level floor is already in the Jolt static world");
            return;
        }

        const auto BodiesAdded = utils_jolt_static_world::Request_BakeActor(_FloorActor);

        Assert_True(BodiesAdded >= 1,
            f"the level floor had to be baked into the Jolt static world for GroundNav to see any ground at all, and the bake produced {BodiesAdded} bodies");

        _FloorBakedByThisTest = BodiesAdded >= 1;
    }

    UFUNCTION()
    private void Step_RequestFieldBake(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(float32(CellSizeUu), float32(StepHeightUu));
        Config.Set_TileSizeUu(float32(TileSizeUu));

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(FCk_ShapeCapsule_Dimensions(float32(ProfileHalfHeightUu), float32(AgentRadius))));

        // The floor's own edges lie outside the volume, so the ledge filter would otherwise demote
        // the whole perimeter and pinch the field in from every side.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(_FieldCentre.X - _FieldHalfXY, _FieldCentre.Y - _FieldHalfXY, _FloorTopZ - FieldFloorDropUu),
            FVector(_FieldCentre.X + _FieldHalfXY, _FieldCentre.Y + _FieldHalfXY, _FloorTopZ + FieldCeilingRiseUu));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid GroundNav volume handle");

        utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
    }

    UFUNCTION()
    private void Check_FieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BuildCompletions >= 1 && utils_ground_nav_volume::Get_IsBuilt(_Volume));
    }

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _BuildCompletions += 1;
        _LastBuildResult = InResult;
    }

    //------------------------------------------------------------------------
    // The two legs
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_BeginLegA(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastBuildResult == ECk_Request_OperationResult::Succeeded,
            f"a bake that finished must complete with Succeeded (got {_LastBuildResult})");

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::Recast);
        utils_nav_surface::Request_SetShadowMode(ECk_NavSurface_ShadowMode::Off);
        _WorldStateSwapped = true;

        // The count is only meaningful against a fixture nothing else has written to, and the row
        // must belong to this test rather than to whatever the map name happens to be.
        utils_ground_nav_shadow::Request_ResetShadowDiagnostics();
        utils_ground_nav_shadow::Request_BeginShadowFixture(FixtureName);
        _FixtureOpened = true;

        const auto ProviderNow = utils_nav_surface::Get_Provider();
        const auto ShadowNow = utils_nav_surface::Get_ShadowMode();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::Recast,
            f"leg A plans on Recast - the world reports {ProviderNow}");
        Assert_True(ShadowNow == ECk_NavSurface_ShadowMode::Off,
            f"leg A plans with nothing shadowing it - the world reports {ShadowNow}");

        _Leg = 0;
        _QueryIndex = 0;
    }

    UFUNCTION()
    private void Step_BeginLegB(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_WaypointCountA.Num(), QueryCount,
            "leg A answered every query it was given - a short leg would compare fewer routes than it claims to");

        utils_nav_surface::Request_SetShadowMode(ECk_NavSurface_ShadowMode::GroundNavShadowsRecast);

        const auto ShadowNow = utils_nav_surface::Get_ShadowMode();
        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ShadowNow == ECk_NavSurface_ShadowMode::GroundNavShadowsRecast,
            f"leg B runs with GroundNav shadowing Recast - the world reports {ShadowNow}");
        Assert_True(ProviderNow == ECk_NavSurface_Provider::Recast,
            f"shadowing must not move the provider that installs - the world reports {ProviderNow}");

        _Leg = 1;
        _QueryIndex = 0;
    }

    // Drives one query at a time: spawn, wait for the answer, destroy, advance. One agent alive at
    // a time is deliberate - two standing bodies plan around each other, and a leg whose population
    // differed from the other's would be comparing two different questions.
    UFUNCTION()
    private void Check_LegComplete(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (_QueryIndex >= QueryCount)
        {
            Res.Set(true);
            return;
        }

        if (_AgentAlive == false)
        {
            Spawn_QueryAgent(_QueryIndex);
            Res.Set(false);
            return;
        }

        if (_ResultCaptured == false)
        {
            Res.Set(false);
            return;
        }

        // Leg B is not done with a query until the shadow half of it has been folded into the
        // fixture: destroying the agent first would take the shadow episode down with it, and the
        // count at the end would then be honestly zero for a run that really did shadow.
        if (_Leg == 1 && utils_ground_nav_shadow::Get_ShadowComparisonCount(FixtureName) < _QueryIndex + 1)
        {
            Res.Set(false);
            return;
        }

        Destroy_QueryAgent();
        _QueryIndex += 1;

        Res.Set(_QueryIndex >= QueryCount);
    }

    private void Spawn_QueryAgent(int32 InIndex)
    {
        const auto Spawn = _Starts[InIndex];
        const auto Goal = _Goals[InIndex];

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"Shadow_ByteIdentical_Planner");

        const auto Rot = (Goal - Spawn).Rotation();
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(Rot, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));
        _Agent = utils_crowd_agent::Add(AgentTransform, Params);

        // Velocity and acceleration are composed because a crowd agent is composed with them, but
        // the euler integrator is deliberately NEVER started: nothing may turn steering into
        // position, or the second leg would plan from wherever the first leg's walk ended up.
        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::BindTo_OnPathReady(_AgentEntity,
            FCk_Delegate_Nav_OnPathReady(this, n"OnPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::BindTo_OnPathFailed(_AgentEntity,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        _AgentAlive = true;
        _ResultCaptured = false;

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    private void Destroy_QueryAgent()
    {
        if (ck::IsValid(_AgentEntity))
        {
            utils_crowd_agent::Request_Stop(_Agent);
            utils_entity_lifetime::Request_DestroyEntity(_AgentEntity);
            _AgentEntity = FCk_Handle();
        }

        _AgentAlive = false;
    }

    //------------------------------------------------------------------------
    // Recording
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        Record_Result(InResult);
    }

    UFUNCTION()
    private void OnPathFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        Record_Result(utils_nav::Get_PathResult(InHandle));
    }

    // Terminal-frame capture: the first signal this query produces is its answer, and a later one
    // would belong to a re-plan rather than to the question that was asked.
    private void Record_Result(const FCk_Nav_PathResult& InResult)
    {
        if (_AgentAlive == false) { return; }
        if (_ResultCaptured) { return; }

        _ResultCaptured = true;

        const auto Waypoints = InResult.Get_Waypoints();
        const auto Diagnostics = InResult.Get_Diagnostics();

        if (_Leg == 0)
        {
            _StatusA.Add(InResult.Get_Status());
            _ReasonA.Add(Diagnostics.Get_LastFailReason());
            _PlannedFromA.Add(Diagnostics.Get_LastAgentLocation());
            _PlannedToA.Add(Diagnostics.Get_LastTargetLocation());
            _WaypointCountA.Add(Waypoints.Num());

            for (int32 Index = 0; Index < Waypoints.Num(); Index++)
            { _WaypointsA.Add(Waypoints[Index]); }
        }
        else
        {
            _StatusB.Add(InResult.Get_Status());
            _ReasonB.Add(Diagnostics.Get_LastFailReason());
            _PlannedFromB.Add(Diagnostics.Get_LastAgentLocation());
            _PlannedToB.Add(Diagnostics.Get_LastTargetLocation());
            _WaypointCountB.Add(Waypoints.Num());

            for (int32 Index = 0; Index < Waypoints.Num(); Index++)
            { _WaypointsB.Add(Waypoints[Index]); }
        }
    }

    //------------------------------------------------------------------------
    // The comparison
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_CompareLegs(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_WaypointCountB.Num(), QueryCount,
            "leg B answered every query it was given");

        if (_WaypointCountA.Num() != QueryCount || _WaypointCountB.Num() != QueryCount)
        { return; }

        // FIRST, and separately: did the two legs ask the same question? Everything below is
        // meaningless if they did not, and a failure here is a fixture defect rather than a leak
        // across the shadow seam.
        for (int32 Index = 0; Index < QueryCount; Index++)
        {
            Assert_True(Get_IsExactlyEqual(_PlannedFromA[Index], _PlannedFromB[Index]),
                f"query {Index} planned from {_PlannedFromA[Index]} without shadowing and from {_PlannedFromB[Index]} with it. The two legs did not ask the same question, so nothing below this compares shadow mode - the walker moved between legs.");

            Assert_True(Get_IsExactlyEqual(_PlannedToA[Index], _PlannedToB[Index]),
                f"query {Index} planned to {_PlannedToA[Index]} without shadowing and to {_PlannedToB[Index]} with it - the two legs did not ask the same question");
        }

        for (int32 Index = 0; Index < QueryCount; Index++)
        {
            Assert_True(_StatusA[Index] == _StatusB[Index],
                f"query {Index} reported {_StatusA[Index]} without shadowing and {_StatusB[Index]} with it. Shadowing must not change the verdict the caller sees.");

            Assert_True(_ReasonA[Index] == _ReasonB[Index],
                f"query {Index} reported fail reason {_ReasonA[Index]} without shadowing and {_ReasonB[Index]} with it");

            Assert_Equals_Int(_WaypointCountB[Index], _WaypointCountA[Index],
                f"query {Index} installed a route of a different length once shadowing was on");
        }

        if (_WaypointsA.Num() != _WaypointsB.Num())
        {
            Assert_Equals_Int(_WaypointsB.Num(), _WaypointsA.Num(),
                "the two legs installed a different total number of waypoints");
            return;
        }

        auto FirstMismatch = -1;

        for (int32 Index = 0; Index < _WaypointsA.Num(); Index++)
        {
            if (Get_IsExactlyEqual(_WaypointsA[Index], _WaypointsB[Index])) { continue; }

            FirstMismatch = Index;
            break;
        }

        if (FirstMismatch >= 0)
        {
            Assert_True(false,
                f"waypoint {FirstMismatch} of the installed routes differs: {_WaypointsA[FirstMismatch]} without shadowing, {_WaypointsB[FirstMismatch]} with it. A shadowing provider answers alongside the installing one and is discarded - the route that installs must be the one that would have installed anyway.");
        }

        // Without this, a leg B that shadowed nothing at all would satisfy every equality above.
        const auto Comparisons = utils_ground_nav_shadow::Get_ShadowComparisonCount(FixtureName);

        Assert_True(Comparisons >= QueryCount,
            f"leg B recorded {Comparisons} shadow comparisons for {QueryCount} queries. Fewer than one per query means the shadow half never ran, and the equality above compared Recast with Recast.");
    }

    private bool Get_IsExactlyEqual(const FVector& InLhs, const FVector& InRhs) const
    {
        return InLhs.X == InRhs.X && InLhs.Y == InRhs.Y && InLhs.Z == InRhs.Z;
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

    // Idempotent, and called from both the conclusion and DoEndPlay: the provider, the shadow mode
    // and the Jolt static world are all WORLD state every later test in this map reads.
    private void Teardown()
    {
        if (_FixtureOpened)
        {
            _FixtureOpened = false;
            utils_ground_nav_shadow::Request_EndShadowFixture();
        }

        if (_WorldStateSwapped)
        {
            _WorldStateSwapped = false;
            utils_nav_surface::Request_SetShadowMode(_ShadowModeBefore);
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        Destroy_QueryAgent();

        if (ck::IsValid(_VolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
            _VolumeEntity = FCk_Handle();
        }

        if (_FloorBakedByThisTest && System::IsValid(_FloorActor))
        {
            _FloorBakedByThisTest = false;
            utils_jolt_static_world::Request_RemoveActor(_FloorActor);
        }
    }
}
