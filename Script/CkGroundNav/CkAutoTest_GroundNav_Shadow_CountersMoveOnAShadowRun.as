// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: THE COUNTERS MOVE, AND ONLY WHEN ASKED TO
//============================================================================
//
// A diagnostic that never moves and a diagnostic that always moves are equally
// useless, and both look identical from a single reading. So this asserts the
// difference: the same population of queries is issued twice against the same
// world, once with GroundNav shadowing Recast and once with nothing shadowing
// anything, and the fixture's comparison count must rise for the first and
// stand perfectly still for the second.
//
// The second half is the half worth having. It is a NEGATIVE - "the count did
// not move" is already true of a world where nothing was dispatched at all - so
// it is paired with a positive: every query in the unshadowed batch must reach
// a terminal status before the count is read. A batch that was never dispatched
// fails on that instead of passing quietly.
//
// Between the batches sits a settle rather than a condition, deliberately. What
// is being waited for is that NOTHING further arrives, and there is no predicate
// for that which is not already true the moment it is first polled.
//
// Fixture, the origin floor: shadowing only happens on the Recast dispatch path,
// so the world must be planning on Recast, and only the level's own
// NavMeshBoundsVolume_1 / StaticMeshActor_1 pair has a navmesh. The GroundNav
// field the shadow half searches is baked over that same floor, so a comparison
// is between two providers that both had ground to answer over.
//============================================================================

class UCk_AutoTest_GroundNav_Shadow_CountersMoveOnAShadowRun : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 180.0f;

    //------------------------------------------------------------------------
    // Fixture shape
    //------------------------------------------------------------------------

    private const int32 QueryCount = 3;

    private const float EndpointInset = 0.55;
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
    private const int32 AnswerFrameBudget = 3600;
    private const int32 ProjectFrameBudget = 900;

    // Long enough for a GroundNav search the first batch left mid-slice to finish and be folded in,
    // so the number the second batch is measured against is the settled one.
    private const int32 QuietFrames = 120;

    private const FName FixtureName = n"Shadow_Smoke";

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
    // Batches
    //------------------------------------------------------------------------

    private TArray<FCk_Handle> _AgentEntities;
    private TArray<FCk_Handle_CrowdAgent> _Agents;

    private int32 _CountAfterShadowedBatch = 0;
    private int32 _CountBeforeUnshadowedBatch = 0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _ProviderBefore = utils_nav_surface::Get_Provider();
        _ShadowModeBefore = utils_nav_surface::Get_ShadowMode();

        Add_Step(          "find the level floor and the box both providers will cover", n"Step_FindFloor");
        Add_Step(          "ask the surface and the navmesh to build",                   n"Step_KickRebuild");
        Add_Step_WaitUntil("every query endpoint projects onto the navmesh",             n"Check_EndpointsProject", ProjectFrameBudget);
        Add_Step(          "put the floor in the Jolt static world if nothing else has", n"Step_EnsureFloorIsStaticWorldGeometry");
        Add_Step(          "bake a GroundNav field over the same floor",                 n"Step_RequestFieldBake");
        Add_Step_WaitUntil("the field reports itself built",                             n"Check_FieldBuilt", BuildFrameBudget);
        Add_Step(          "open a fixture and turn GroundNav shadowing on",             n"Step_ArmShadowedBatch");
        Add_Step(          "dispatch the shadowed batch",                                n"Step_DispatchBatch");
        Add_Step_WaitUntil("the fixture records a comparison for every query",           n"Check_EveryQueryCompared", AnswerFrameBudget);
        Add_Step(          "turn shadowing off and retire the shadowed batch",           n"Step_DisarmShadowing");
        Add_Step_WaitFrames("let any shadow search the first batch left in flight land", QuietFrames);
        Add_Step(          "read the settled count and dispatch the unshadowed batch",   n"Step_DispatchUnshadowedBatch");
        Add_Step_WaitUntil("every unshadowed query reaches a terminal status",           n"Check_EveryQueryTerminal", AnswerFrameBudget);
        Add_Step(          "assert the count stood perfectly still",                     n"Step_AssertCountStood");
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
            FinishFailure("staging failed: the level floor StaticMeshActor_1 could not be reached - the fixture, not the counters, is broken");
            return;
        }

        auto FloorOrigin = FVector::ZeroVector;
        auto FloorExtent = FVector::ZeroVector;
        _FloorActor.GetActorBounds(false, FloorOrigin, FloorExtent);

        auto Volume = assets::NavMeshBoundsVolume_1().Get();

        if (!System::IsValid(Volume))
        {
            FinishFailure("staging failed: the level nav bounds volume NavMeshBoundsVolume_1 could not be reached - the fixture, not the counters, is broken");
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

        Add_QueryPair(-Reach, -Reach,  Reach,  Reach);
        Add_QueryPair( Reach, -Reach, -Reach,  Reach);
        Add_QueryPair(-Reach,   0.0f,  Reach,   0.0f);

        ck::nav::Display(f"[SHADOW-COUNTERS] fixture: centre={_FieldCentre} halfXY={_FieldHalfXY} queries={QueryCount}");
    }

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

    // GroundNav reads the Jolt static world, not UE collision, and whether the level sweep has
    // already put the floor there is the host project's business rather than this test's.
    UFUNCTION()
    private void Step_EnsureFloorIsStaticWorldGeometry(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto ProbeStart = FVector(_FieldCentre.X, _FieldCentre.Y, _FloorTopZ + 200.0);
        const auto ProbeEnd = FVector(_FieldCentre.X, _FieldCentre.Y, _FloorTopZ - 200.0);

        if (utils_jolt_static_world::Get_RayCastStaticWorld(ProbeStart, ProbeEnd).Get_HasHit())
        {
            ck::nav::Display("[SHADOW-COUNTERS] the level floor is already in the Jolt static world");
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
    // The shadowed batch
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_ArmShadowedBatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastBuildResult == ECk_Request_OperationResult::Succeeded,
            f"a bake that finished must complete with Succeeded (got {_LastBuildResult})");

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::Recast);
        _WorldStateSwapped = true;

        utils_ground_nav_shadow::Request_ResetShadowDiagnostics();
        utils_ground_nav_shadow::Request_BeginShadowFixture(FixtureName);
        _FixtureOpened = true;

        Assert_Equals_Int(utils_ground_nav_shadow::Get_ShadowComparisonCount(FixtureName), 0,
            "a fixture opened after a reset starts at zero - a rise measured from an unknown floor measures nothing");

        utils_nav_surface::Request_SetShadowMode(ECk_NavSurface_ShadowMode::GroundNavShadowsRecast);

        const auto ShadowNow = utils_nav_surface::Get_ShadowMode();
        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ShadowNow == ECk_NavSurface_ShadowMode::GroundNavShadowsRecast,
            f"the world must report the shadow mode it was told to run (got {ShadowNow})");
        Assert_True(ProviderNow == ECk_NavSurface_Provider::Recast,
            f"shadowing happens on the Recast dispatch path, so the world must be planning on Recast (got {ProviderNow})");
    }

    UFUNCTION()
    private void Step_DispatchBatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Spawn_Batch();
    }

    UFUNCTION()
    private void Check_EveryQueryCompared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_ground_nav_shadow::Get_ShadowComparisonCount(FixtureName) >= QueryCount);
    }

    //------------------------------------------------------------------------
    // The unshadowed batch
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_DisarmShadowing(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CountAfterShadowedBatch = utils_ground_nav_shadow::Get_ShadowComparisonCount(FixtureName);

        Assert_True(_CountAfterShadowedBatch >= QueryCount,
            f"the shadowed batch recorded {_CountAfterShadowedBatch} comparisons for {QueryCount} queries");

        utils_nav_surface::Request_SetShadowMode(ECk_NavSurface_ShadowMode::Off);

        const auto ShadowNow = utils_nav_surface::Get_ShadowMode();

        Assert_True(ShadowNow == ECk_NavSurface_ShadowMode::Off,
            f"the world must report shadowing off once it is turned off (got {ShadowNow})");

        Destroy_Batch();
    }

    UFUNCTION()
    private void Step_DispatchUnshadowedBatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CountBeforeUnshadowedBatch = utils_ground_nav_shadow::Get_ShadowComparisonCount(FixtureName);

        Spawn_Batch();
    }

    UFUNCTION()
    private void Check_EveryQueryTerminal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        for (int32 Index = 0; Index < _Agents.Num(); Index++)
        {
            const auto Status = utils_nav::Get_PathStatus(_Agents[Index]);

            if (Status == ECk_Nav_PathStatus::None || Status == ECk_Nav_PathStatus::Pending)
            {
                Res.Set(false);
                return;
            }
        }

        Res.Set(_Agents.Num() == QueryCount);
    }

    UFUNCTION()
    private void Step_AssertCountStood(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto CountNow = utils_ground_nav_shadow::Get_ShadowComparisonCount(FixtureName);

        ck::nav::Display(f"[SHADOW-COUNTERS] comparisons: after shadowed batch={_CountAfterShadowedBatch}, before unshadowed batch={_CountBeforeUnshadowedBatch}, after it={CountNow}");

        Assert_Equals_Int(CountNow, _CountBeforeUnshadowedBatch,
            f"{QueryCount} queries were dispatched and answered with shadowing OFF and the fixture recorded {CountNow - _CountBeforeUnshadowedBatch} further comparisons. A diagnostic that moves when nothing is shadowing cannot say what a shadow run cost.");
    }

    //------------------------------------------------------------------------
    // Batch handling
    //------------------------------------------------------------------------

    private void Spawn_Batch()
    {
        for (int32 Index = 0; Index < QueryCount; Index++)
        {
            const auto Spawn = _Starts[Index];
            const auto Goal = _Goals[Index];

            auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
            AgentEntity.Set_DebugName(n"Shadow_Counters_Planner");

            const auto Rot = (Goal - Spawn).Rotation();
            auto AgentTransform = utils_transform::Add(AgentEntity,
                FTransform(Rot, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

            auto Params = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));
            auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

            // The euler integrator is deliberately never started: this test asks what a dispatch
            // costs the counters, and a walker that reached its goal would re-plan on the way and
            // dispatch more queries than were counted.
            utils_velocity::Add(AgentEntity,
                FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
                ECk_Replication::DoesNotReplicate);
            utils_acceleration::Add(AgentEntity,
                FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
                ECk_Replication::DoesNotReplicate);

            _AgentEntities.Add(AgentEntity);
            _Agents.Add(Agent);

            utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(Goal));
        }
    }

    private void Destroy_Batch()
    {
        for (int32 Index = 0; Index < _AgentEntities.Num(); Index++)
        {
            auto AgentEntity = _AgentEntities[Index];

            if (ck::Is_NOT_Valid(AgentEntity)) { continue; }

            utils_crowd_agent::Request_Stop(_Agents[Index]);
            utils_entity_lifetime::Request_DestroyEntity(AgentEntity);
        }

        _AgentEntities.Reset();
        _Agents.Reset();
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

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

        Destroy_Batch();

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
