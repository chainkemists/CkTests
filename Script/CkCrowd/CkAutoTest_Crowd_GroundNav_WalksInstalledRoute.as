// Language=angelscript

//============================================================================
// CK CROWD - AUTOMATION TEST: A CROWD AGENT WALKS A ROUTE GROUNDNAV PLANNED
//============================================================================
//
// The GroundNav dispatch branch and the crowd walk had only ever been
// exercised apart. The branch tests prove a request is enqueued; the facade
// test proves a projection comes back with the right numbers. Nothing walked
// the whole seam: a world selecting GroundNav, an agent whose MoveTo takes the
// GroundNav branch instead of the Recast fallthrough, a plan installed through
// the SHARED nav slot, and steering that follows it to the arrival radius.
//
// The signal is the real seam and the reason this is an end-to-end test rather
// than a dispatch assertion: InstallExternalPath broadcasts the SAME
// UUtils_Signal_Nav_OnPathReady with the SAME FCk_Nav_PathResult payload that a
// Recast query does. A caller cannot tell the two apart, which is the whole
// point of the fork being extended rather than replaced - so this asserts in
// the OnPathReady handler, never on a polled Get_PathStatus.
//
// Fixture, the facade test's verbatim in shape: one Static JoltBody box whose
// TOP sits at Z 0, overhanging the GroundNav volume on every horizontal side so
// no cliff edge exists INSIDE the field, auto-build disabled so the bake waited
// on is the one asked for. A box shape is convex and therefore closed - an open
// mesh would trip the bake's OPEN COLLISION warning, and the harness escalates
// a Warning into a test failure.
//
// The volume is 1800 x 800 uu of footprint with the walk running 1200 uu down
// its middle, leaving 300 uu of margin at each end - comfortably more than the
// 42 uu agent radius the clearance predicate demands, so the corridor is real
// and not an artifact of the field's own boundary.
//
// The provider is per world and every other crowd test in this map reads it, so
// the previous selection is captured before the swap and handed back both at
// the moment this test concludes AND in DoEndPlay - the walk spans seconds and
// every exit path, including the engine TimeLimit one, must put the world back.
//
// Isolated Y band: 122000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_Crowd_GroundNav_WalksInstalledRoute : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 45.0f;

    //------------------------------------------------------------------------
    // Fixture geometry
    //------------------------------------------------------------------------

    private const float BandY = 122000.0;

    // Top face at Z 0. Overhangs the volume by 200uu on X and Y so the volume's
    // interior never contains a slab edge.
    private const float SlabHalfX = 1100.0;
    private const float SlabHalfY = 600.0;
    private const float SlabHalfZ = 50.0;

    private const float VolumeHalfX = 900.0;
    private const float VolumeHalfY = 400.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float SurfaceZ = 0.0;

    // 1200uu of walk, 300uu of margin to the field boundary at each end.
    private const float SpawnX = -600.0;
    private const float GoalX = 600.0;
    private const float AgentCentreOffsetZ = 100.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;

    //------------------------------------------------------------------------
    // Budgets
    //------------------------------------------------------------------------

    private const float SampleIntervalSec = 0.1;

    // 1200uu at the crowd's ~240uu/s cruise is ~5s, plus the acceleration ramp,
    // plus the arrival settle. 20s from dispatch is a wide margin that still
    // fails loudly rather than riding the engine TimeLimit.
    private const float WalkDeadlineSec = 20.0;
    private const float HardDeadlineSec = 40.0;

    //------------------------------------------------------------------------
    // State
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _VolumeEntity;
    private FCk_Handle _AgentEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_CrowdAgent _Agent;

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private ECk_NavSurface_Provider _ProviderWhilePlanning = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    private bool _BuildRequested = false;
    private bool _Dispatched = false;
    private float _DispatchedAtSec = -1.0;

    private int32 _PathReadyCount = 0;
    private int32 _PathReadyWaypoints = 0;
    private ECk_Nav_PathStatus _PathReadyStatus = ECk_Nav_PathStatus::None;

    private float _ElapsedSec = 0.0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        utils_transform::Add(_SelfHandle,
            FTransform(FRotator::ZeroRotator, FVector(0.0, BandY, 0.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        Build_Fixture();

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(_SelfHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private void Build_Fixture()
    {
        _FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _FloorEntity.Request_OverrideToSelf();

        utils_transform::Add(_FloorEntity,
            FTransform(FRotator::ZeroRotator, FVector(0.0, BandY, SurfaceZ - SlabHalfZ)),
            ECk_Replication::DoesNotReplicate);

        auto SlabShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        SlabShape.Set_HalfExtents(FVector(SlabHalfX, SlabHalfY, SlabHalfZ));

        auto SlabParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        SlabParams.Set_ShapeDimensions(SlabShape);
        SlabParams.Set_MotionType(ECk_MotionType::Static);

        _FloorBody = utils_jolt_body::Add(_FloorEntity, SlabParams);

        Assert_True(ck::IsValid(_FloorBody), "the slab's Jolt body must be valid");

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(25.0f, 10.0f);
        Config.Set_TileSizeUu(500.0f);

        // The standing volume is the crowd agent's own: radius is deliberately absent from the
        // profile (clearance is answered per query as clearance >= R), so only the height matters
        // here, and the branch feeds the agent's 42uu radius to the query itself.
        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(FCk_ShapeCapsule_Dimensions(96.0f, 42.0f)));
        // The slab's own edges lie OUTSIDE the volume, but the field is clipped to the volume, so
        // the ledge filter would otherwise demote the whole perimeter and pinch the corridor.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(-VolumeHalfX, BandY - VolumeHalfY, VolumeFloorZ),
            FVector( VolumeHalfX, BandY + VolumeHalfY, VolumeCeilingZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid volume handle");
    }

    private void Spawn_Agent()
    {
        const auto Spawn = FVector(SpawnX, BandY, SurfaceZ + AgentCentreOffsetZ);
        const auto Goal  = FVector(GoalX,  BandY, SurfaceZ + AgentCentreOffsetZ);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"GroundNav_WalksInstalledRoute_Walker");

        const auto Rot = (Goal - Spawn).Rotation();
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(Rot, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        _Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);

        // The nav signals live on the agent's own entity - the shared slot the GroundNav install
        // writes through is that entity's FFragment_Nav_PathResult.
        utils_nav::BindTo_OnPathReady(_AgentEntity,
            FCk_Delegate_Nav_OnPathReady(this, n"OnPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::BindTo_OnPathFailed(_AgentEntity,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalReached(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    //------------------------------------------------------------------------
    // Poll
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ElapsedSec += SampleIntervalSec;

        if (_ElapsedSec >= HardDeadlineSec)
        {
            Fail(f"HARD DEADLINE at {_ElapsedSec}s (builds={_BuildCompletions}, providerSwapped={_ProviderSwapped}, dispatched={_Dispatched}, pathReady={_PathReadyCount})");
            return;
        }

        if (_BuildRequested == false)
        {
            if (utils_jolt_body::Get_IsBodyAdded(_FloorBody) == false) { return; }

            _BuildRequested = true;
            utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(),
                FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
            return;
        }

        if (_Dispatched == false)
        {
            if (_BuildCompletions < 1) { return; }
            if (utils_ground_nav_volume::Get_IsBuilt(_Volume) == false) { return; }

            Assert_True(_LastBuildResult == ECk_Request_OperationResult::Succeeded,
                f"a bake that finished must complete with Succeeded (got {_LastBuildResult})");

            utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
            _ProviderSwapped = true;
            _ProviderWhilePlanning = utils_nav_surface::Get_Provider();

            // First, because every assertion below is meaningless if the world quietly stayed on
            // its default provider - the walk would then be Recast agreeing with GroundNav about
            // nothing at all.
            Assert_True(_ProviderWhilePlanning == ECk_NavSurface_Provider::GroundNav,
                f"the world must report the provider it was told to plan on (got {_ProviderWhilePlanning})");

            Spawn_Agent();
            _Dispatched = true;
            _DispatchedAtSec = _ElapsedSec;
            return;
        }

        if (ck::Is_NOT_Valid(_Agent))
        {
            Fail("the walker went invalid mid-run");
            return;
        }

        if (_ElapsedSec >= _DispatchedAtSec + WalkDeadlineSec)
        {
            const auto Pos = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Agent)));
            const auto State = utils_crowd_agent::Get_MovementState(_Agent);
            const auto Status = utils_nav::Get_PathStatus(_Agent);
            Fail(f"the walker never arrived within {WalkDeadlineSec}s of dispatch (position={Pos}, state={State}, navStatus={Status}, pathReadySignals={_PathReadyCount}). A GroundNav route installed through the shared slot must be walkable by the same steering that walks a Recast one.");
        }
    }

    //------------------------------------------------------------------------
    // Signals
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _BuildCompletions += 1;
        _LastBuildResult = InResult;
    }

    UFUNCTION()
    private void OnPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _PathReadyCount += 1;
        _PathReadyStatus = InResult.Get_Status();
        _PathReadyWaypoints = InResult.Get_Waypoints().Num();
    }

    UFUNCTION()
    private void OnPathFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        const auto Reason = utils_nav::Get_PathResult(InHandle).Get_Diagnostics().Get_LastFailReason();
        Fail(f"the plan for a straight 1200uu run across a fully baked GroundNav field FAILED with reason {Reason}. Either the field does not cover the corridor or the install verdict mapped a good plan onto a failure.");
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_PathReadyCount, 1,
            f"the walk was fed by exactly one installed route (got {_PathReadyCount} OnPathReady signals) - arriving without a plan, or on a second plan, is not the seam under test");
        Assert_True(_PathReadyStatus == ECk_Nav_PathStatus::Ready,
            f"the installed GroundNav route reported Ready through the shared slot (got {_PathReadyStatus})");
        Assert_True(_PathReadyWaypoints >= 1,
            f"an installed route carries at least one waypoint (got {_PathReadyWaypoints}) - InstallExternalPath refuses an empty list, so zero here means nothing installed at all");

        Teardown();
        FinishSuccess();
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

        Fail("the walker reported OnGoalFailed for a straight, unobstructed 1200uu run on a fully baked GroundNav field");
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    private void Fail(const FString& InMessage)
    {
        Teardown();
        FinishFailure(InMessage);
    }

    // Idempotent, and called from BOTH the conclusion and DoEndPlay: the provider is a WORLD
    // selection that every later crowd test in this map reads, so leaving it on GroundNav would
    // silently re-provider the rest of the lane.
    private void Teardown()
    {
        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_AgentEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_AgentEntity);
            _AgentEntity = FCk_Handle();
        }
        if (ck::IsValid(_VolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
            _VolumeEntity = FCk_Handle();
        }
        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}
