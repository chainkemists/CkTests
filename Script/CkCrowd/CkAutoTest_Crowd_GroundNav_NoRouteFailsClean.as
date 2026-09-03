// Language=angelscript

//============================================================================
// CK CROWD - AUTOMATION TEST: NO ROUTE AT ALL FAILS CLEANLY, ON GROUNDNAV
//============================================================================
//
// The GroundNav twin of Crowd_NarrowGap_NoRouteFailsClean. The original is NOT
// touched and NOT parameterised - an AS autotest class is one fixture, and the
// delta-zero requirement forbids editing it. This asserts the SAME terminal
// signal sequence on the GroundNav provider that the original asserts on
// Recast, which is the whole claim being made about the fork: it was extended,
// not replaced, so a caller sees the same shape of failure either way.
//
// Sequence mirrored (Crowd_NarrowGap_NoRouteFailsClean.as:168-188):
//   - OnGoalReached is an immediate FinishFailure - a physically unreachable
//     goal that reports arrival has lied to its caller;
//   - OnGoalFailed within the budget is the pass, with the direction-reversal
//     ceiling asserted so a bounded failure does not look like a fidget fit;
//   - the budget expiring with the agent still pressing is the UNBOUNDED
//     defect the instrument exists to expose.
//
// DELIBERATE DIVERGENCE from the original, stated rather than hidden: the
// original blocks with a crowd agent parked in the only gap and therefore
// asserts InInfo.Get_NoCrowdFreeRouteExisted(). There is no crowd plug here -
// the blockage is geometry - so that flag is not the contract this fixture can
// speak to and is not asserted. What replaces it is a nav-level assertion the
// original cannot make: OnPathFailed must have fired at least once before
// OnGoalFailed, i.e. the goal-level failure was carried by a real provider
// verdict (GroundNav Unreachable -> FindPathNoPath) and not invented by the
// crowd's own ladder.
//
// BLOCKAGE SHAPE - and why not Request_ImpassableBox. The original paints
// NavSurface area markup (:156-166). GroundNav honours no area markup yet, so
// the twin blocks with GEOMETRY instead: two Static JoltBody slabs baked into
// one GroundNav volume with an 800uu void between them. The gap is empty space,
// so nothing is walkable across it at any clearance - stronger than a markup
// carve, which only raises cost. Both slabs are boxes, hence convex, hence
// closed: an open mesh would trip the bake's OPEN COLLISION warning and the
// harness escalates a Warning into a test failure.
//
// Isolated Y band: 126000 - clear of every other autotest's bodies, and its own
// band rather than the walk test's so the shared PIE world never mixes the two
// fixtures.
//============================================================================

class UCk_AutoTest_Crowd_GroundNav_NoRouteFailsClean : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 45.0f;

    //------------------------------------------------------------------------
    // Fixture geometry
    //------------------------------------------------------------------------

    private const float BandY = 126000.0;

    // Mainland: X -1000 .. -100. Island: X 700 .. 1300. An 800uu void between.
    private const float MainlandCentreX = -550.0;
    private const float MainlandHalfX = 450.0;
    private const float IslandCentreX = 1000.0;
    private const float IslandHalfX = 300.0;

    private const float SlabHalfY = 700.0;
    private const float SlabHalfZ = 50.0;

    // The volume overhangs neither slab in Y (slabs reach 700, the field 500), so
    // the field's own boundary never coincides with a slab edge in Y.
    private const float VolumeMinX = -950.0;
    private const float VolumeMaxX = 1250.0;
    private const float VolumeHalfY = 500.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float SurfaceZ = 0.0;
    private const float AgentCentreOffsetZ = 100.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;

    //------------------------------------------------------------------------
    // Budgets
    //------------------------------------------------------------------------

    private const float SampleIntervalSec = 0.5;

    // The route does not exist at PLAN time, so this is the strict plan, the one
    // permissive retry, and the terminal report - not the full no-progress
    // ladder. 20s from dispatch is several times that and still fails loudly
    // ahead of the engine TimeLimit.
    private const float FailDeadlineSec = 20.0;
    private const float HardDeadlineSec = 38.0;

    // The original's ceiling, kept verbatim (Crowd_NarrowGap_NoRouteFailsClean.as:31).
    private const int32 MaxReversalsWhilePressing = 4;

    //------------------------------------------------------------------------
    // State
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _MainlandEntity;
    private FCk_Handle _IslandEntity;
    private FCk_Handle _VolumeEntity;
    private FCk_Handle _AgentEntity;

    private FCk_Handle_JoltBody _MainlandBody;
    private FCk_Handle_JoltBody _IslandBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_CrowdAgent _Walker;

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private ECk_NavSurface_Provider _ProviderWhilePlanning = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    private bool _BuildRequested = false;
    private bool _WalkerDispatched = false;
    private float _DispatchedAtSec = -1.0;

    private int32 _PathFailedCount = 0;
    private int32 _PathReadyCount = 0;

    private float _ElapsedSec = 0.0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _SelfHandle = InHandle;
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

    // Tests share one PIE world and run seconds apart. These slabs, the field baked over them and
    // the provider selection all come down on every exit path, including the engine TimeLimit one.
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
        _MainlandEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _MainlandEntity.Request_OverrideToSelf();
        _MainlandBody = Add_Slab(_MainlandEntity, MainlandCentreX, MainlandHalfX);

        _IslandEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _IslandEntity.Request_OverrideToSelf();
        _IslandBody = Add_Slab(_IslandEntity, IslandCentreX, IslandHalfX);

        Assert_True(ck::IsValid(_MainlandBody) && ck::IsValid(_IslandBody),
            "both slabs must produce valid Jolt bodies");

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(25.0f, 10.0f);
        Config.Set_TileSizeUu(500.0f);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(FCk_ShapeCapsule_Dimensions(96.0f, 42.0f)));
        // Zero, so the two slabs' shared field boundary is not what disconnects them - the 800uu of
        // empty air between them is. A demoted perimeter would blur the reason this test fails.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(VolumeMinX, BandY - VolumeHalfY, VolumeFloorZ),
            FVector(VolumeMaxX, BandY + VolumeHalfY, VolumeCeilingZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid volume handle");
    }

    private FCk_Handle_JoltBody Add_Slab(FCk_Handle& InEntity, float InCentreX, float InHalfX)
    {
        utils_transform::Add(InEntity,
            FTransform(FRotator::ZeroRotator, FVector(InCentreX, BandY, SurfaceZ - SlabHalfZ)),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(InHalfX, SlabHalfY, SlabHalfZ));

        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);

        return utils_jolt_body::Add(InEntity, Params);
    }

    private void Spawn_Walker()
    {
        const auto Spawn = FVector(MainlandCentreX, BandY, SurfaceZ + AgentCentreOffsetZ);
        const auto Goal  = FVector(IslandCentreX,   BandY, SurfaceZ + AgentCentreOffsetZ);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"GroundNav_NoRoute_Walker");

        const auto Rot = (Goal - Spawn).Rotation();
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(Rot, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        _Walker = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);

        utils_nav::BindTo_OnPathReady(_AgentEntity,
            FCk_Delegate_Nav_OnPathReady(this, n"OnPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::BindTo_OnPathFailed(_AgentEntity,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalFailed(_Walker,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalReached(_Walker,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent_diag::Track(_Walker, Spawn, Goal);
        utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(Goal));
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
            Fail(f"HARD DEADLINE at {_ElapsedSec}s (builds={_BuildCompletions}, dispatched={_WalkerDispatched}, pathFailed={_PathFailedCount}, pathReady={_PathReadyCount})");
            return;
        }

        if (_BuildRequested == false)
        {
            if (utils_jolt_body::Get_IsBodyAdded(_MainlandBody) == false) { return; }
            if (utils_jolt_body::Get_IsBodyAdded(_IslandBody) == false) { return; }

            _BuildRequested = true;
            utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(),
                FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
            return;
        }

        if (_WalkerDispatched == false)
        {
            if (_BuildCompletions < 1) { return; }
            if (utils_ground_nav_volume::Get_IsBuilt(_Volume) == false) { return; }

            Assert_True(_LastBuildResult == ECk_Request_OperationResult::Succeeded,
                f"a bake that finished must complete with Succeeded (got {_LastBuildResult})");

            utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
            _ProviderSwapped = true;
            _ProviderWhilePlanning = utils_nav_surface::Get_Provider();

            Assert_True(_ProviderWhilePlanning == ECk_NavSurface_Provider::GroundNav,
                f"the world must report the provider it was told to plan on (got {_ProviderWhilePlanning})");

            Spawn_Walker();
            _WalkerDispatched = true;
            _DispatchedAtSec = _ElapsedSec;
            return;
        }

        if (ck::Is_NOT_Valid(_Walker))
        {
            Fail("the walker went invalid mid-run");
            return;
        }

        if (_ElapsedSec >= _DispatchedAtSec + FailDeadlineSec)
        {
            const auto BlockedHold = utils_crowd_agent::Get_IsGoalBlocked(_Walker);
            const auto State = utils_crowd_agent::Get_MovementState(_Walker);
            Fail(f"UNBOUNDED: {FailDeadlineSec}s elapsed with no OnGoalFailed (goalBlockedHold={BlockedHold}, state={State}, pathFailed={_PathFailedCount}). The goal stands on an island across 800uu of empty air - there is no route at any clearance - so a move that neither succeeds nor fails is unobservable to every caller.");
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
    }

    UFUNCTION()
    private void OnPathFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }
        _PathFailedCount += 1;
    }

    UFUNCTION()
    private void OnWalkerReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        Fail("the walker REACHED a goal standing on an island across 800uu of empty air - either it walked on nothing, or an arrival was reported for a partial route's reachable end");
    }

    UFUNCTION()
    private void OnWalkerFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

        // The nav-level assertion the original cannot make: the goal-level failure was carried by a
        // real provider verdict on the shared slot, not invented by the crowd's own ladder.
        Assert_True(_PathFailedCount >= 1,
            f"OnGoalFailed arrived without a single OnPathFailed on the shared nav slot (pathFailed={_PathFailedCount}, pathReady={_PathReadyCount}) - the GroundNav Unreachable verdict must reach the caller as a nav failure, exactly as a Recast no-path does");

        const auto Recorder = utils_crowd_agent_diag::Get_RecorderData(_Walker);
        Assert_True(Recorder.Get_DirReversalCount() <= MaxReversalsWhilePressing,
            f"CHURN: the walker reversed direction {Recorder.Get_DirReversalCount()} times before failing (ceiling {MaxReversalsWhilePressing}). A bounded failure must not look like a fidget fit.");

        const auto State = utils_crowd_agent::Get_MovementState(_Walker);
        Assert_True(State != ECk_CrowdAgent_MovementState::Walking,
            f"the walker STOPPED when its move failed (movement state={State}). A terminal OnGoalFailed while the agent is still Walking means the failure was reported but the press never ended.");

        Teardown();
        FinishSuccess();
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    private void Fail(const FString& InMessage)
    {
        Teardown();
        FinishFailure(InMessage);
    }

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
        if (ck::IsValid(_IslandEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_IslandEntity);
            _IslandEntity = FCk_Handle();
        }
        if (ck::IsValid(_MainlandEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_MainlandEntity);
            _MainlandEntity = FCk_Handle();
        }
    }
}

class ACk_AutoTest_Crowd_GroundNav_NoRouteFailsClean_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_GroundNav_NoRouteFailsClean;
    default _TimeoutSeconds = 45.0f;

    // The original (CkAutoTest_Crowd_NarrowGap_NoRouteFailsClean.as:191-195) carries NO expected
    // errors: its blockage is a crowd plug, so the strict plan fails inside the crowd's own ladder
    // and the SHARED nav slot never goes Failed. This twin's blockage is geometry - GroundNav
    // answers Unreachable, the resolve processor calls FailPath, and the crowd's Failed branch
    // reports it at Warning verbosity. The harness escalates any Warning to a test failure, so the
    // twin's own deliberate output would fail it. Registered as a plain substring
    // (AddExpectedErrorPlain, Contains, suppress-all) - no regex.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        // FProcessor_CrowdAgent_OnPathResolved, Failed branch
        // (CkCrowdAgent_OnPathResolved_Processor.cpp:336):
        //   "CrowdAgent [..] PathPending -> Idle (path failed: ..)"
        Out.Add("(path failed:");
        return Out;
    }
}
