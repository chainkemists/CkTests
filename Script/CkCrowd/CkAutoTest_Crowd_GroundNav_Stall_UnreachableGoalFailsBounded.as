// Language=angelscript

//============================================================================
// CK CROWD - AUTOMATION TEST: A SEALED GOAL FAILS BOUNDED, ON GROUNDNAV
//============================================================================
//
// The GroundNav twin of Crowd_Stall_UnreachableGoalFailsBounded. The original
// is NOT touched and NOT parameterised - an AS autotest class is one fixture,
// and the delta-zero requirement forbids editing it. This asserts the SAME
// bounded-failure sequence on the GroundNav provider that the original asserts
// on Recast: a move whose goal cannot be reached must terminate, once, within a
// budget, and leave the agent stopped and in the stable failed-goal hold.
//
// THE MID-WALK SEAL VARIANT IS DEFERRED. The original seals the corridor while
// the agent is already following an installed polyline; that is not reproducible
// on this provider yet, because GroundNav has no change detection on geometry
// change (fenced to the phase that adds it) and the crowd's PathRefresh is
// Recast-adapter based, so a rebuild under a walking agent is simply not
// observed - the agent keeps its installed route and arrives. This twin
// therefore seals the goal BEFORE the first Request_MoveTo and asserts the
// terminal contract that IS provider-independent today; the mid-walk seal comes
// back with change detection.
//
// Sequence mirrored (Crowd_Stall_UnreachableGoalFailsBounded.as:222-269):
//   - OnGoalReached at any point is a FALSE ARRIVAL and fails immediately;
//   - OnGoalFailed exactly ONCE - a terminal signal that repeats is not
//     terminal, and a caller that re-dispatches on it would loop;
//   - the agent is NOT Walking afterwards - a failure reported while the press
//     continues means the press never ended;
//   - the GoalBlocked hold is released and the failed-goal hold is set;
//   - OnGoalBlocked, if it fires at all, fires once and names NoProgress - a
//     GoalOccupied verdict would put the agent in the one retry policy that
//     never fails;
//   - all of it inside a budget, with the elapsed time named in the failure.
// The original's same-goal-spam, PushApart-anchor and correlated-recovery
// batteries are NOT mirrored: those pin down the failed-goal hold, which is
// crowd behaviour downstream of the terminal signal and identical on every
// provider. This twin's subject is the provider.
//
// SEAL SHAPE - and why not Request_ImpassableBox. The original paints NavSurface
// area markup (:468-477). GroundNav honours no area markup yet, so the twin
// seals with GEOMETRY: a Static JoltBody wall box stands in the Jolt world
// before the single bake, so the field the agent plans against has never
// contained a route. The wall spans |y| <= 900 against a field that reaches
// |y| = 400, so no detour exists - and it is kept ENTIRELY inside the volume's
// Z range, because the bake rasterizes faces and a wall clipped by the ceiling
// contributes no span at all (see the WallHalfZ comment). Slab and wall are
// boxes, hence convex, hence closed: an open mesh would trip the bake's OPEN
// COLLISION warning and the harness escalates a Warning into a failure.
//
// Two staging guards ask the FACADE, before the first MoveTo, whether the seal
// is actually in the baked field - a broken fixture must name itself rather
// than surface as a FALSE ARRIVAL defect in the crowd.
//
// Isolated Y band: 128000 - clear of every other autotest's bodies, and its own
// band rather than the other GroundNav twins' so the shared PIE world never
// mixes the fixtures.
//============================================================================

class UCk_AutoTest_Crowd_GroundNav_Stall_UnreachableGoalFailsBounded : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 48.0f;

    //------------------------------------------------------------------------
    // Fixture geometry
    //------------------------------------------------------------------------

    private const float BandY = 128000.0;

    private const float SlabHalfX = 1100.0;
    private const float SlabHalfY = 600.0;
    private const float SlabHalfZ = 50.0;

    private const float VolumeHalfX = 900.0;
    private const float VolumeHalfY = 400.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float SurfaceZ = 0.0;
    private const float AgentCentreOffsetZ = 100.0;

    private const float SpawnX = -700.0;
    private const float GoalX = 700.0;

    // |y| <= 900 against a field that reaches |y| = 400: the wall runs off both ends
    // of the field, so no detour exists.
    //
    // Z is 0..400, and the underside sitting EXACTLY on the slab's top face is the
    // whole reason the wall exists to the bake at all. The rasterizer emits one
    // zero-thickness span per FACE and knows no interiors
    // (CkGroundNav_Rasterize.cpp:325-338; :321 drops anything with no projected XY
    // area, so vertical sides contribute nothing). Per the closed-collision
    // contract (Source/CkGroundNav/CLAUDE.md), a box resting on a floor is known to
    // cover that floor only through its underside lying FLUSH on the floor's top
    // face and winning the exact-height tie - non-walkable beats walkable. Sink the
    // underside even slightly below the slab's top and the tie never happens: the
    // column keeps the slab's walkable face at Z 0 with clear headroom above it,
    // and the seal bakes as open ground with no warning to say so.
    //
    // The top at 400 is under the volume's 500 ceiling, and the 100uu that leaves
    // is far under the agent's 192uu standing height, so no standable wall-top
    // plate is produced either.
    private const float WallHalfX = 80.0;
    private const float WallHalfY = 900.0;
    private const float WallHalfZ = 200.0;
    private const float WallCentreZ = 200.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;

    //------------------------------------------------------------------------
    // Budgets
    //------------------------------------------------------------------------

    private const float SampleIntervalSec = 0.1;

    // One poll of separation between the terminal broadcast and the state read, so
    // the assertions run against a settled frame rather than the signal's own.
    private const float SettleAfterFailSec = 0.2;

    // The goal is sealed at PLAN time, so the terminal report is the strict plan,
    // the one permissive retry and the failure - not the full no-progress ladder
    // the original pays for its mid-walk seal. 20s from dispatch is several times
    // that and still fails loudly ahead of the engine TimeLimit.
    private const float FailDeadlineSec = 20.0;
    private const float HardDeadlineSec = 40.0;

    //------------------------------------------------------------------------
    // State
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _WallEntity;
    private FCk_Handle _VolumeEntity;
    private FCk_Handle _AgentEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_JoltBody _WallBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_CrowdAgent _Agent;

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private ECk_NavSurface_Provider _ProviderWhilePlanning = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    private bool _BuildRequested = false;
    private bool _WalkerDispatched = false;
    private float _DispatchedAtSec = -1.0;

    private bool _Failed = false;
    private int32 _FailedCount = 0;
    private float _FailedAtSec = -1.0;
    private bool _Reached = false;

    private int32 _BlockedCount = 0;
    private bool _BlockedReasonWasNoProgress = false;

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

    // The wall, the slab, the field baked over them and the provider selection all come down on
    // every exit path, including the engine TimeLimit one.
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
        _FloorBody = Add_StaticBox(_FloorEntity,
            FVector(0.0, BandY, SurfaceZ - SlabHalfZ),
            FVector(SlabHalfX, SlabHalfY, SlabHalfZ));

        // Standing in the Jolt world BEFORE the single bake, so the field the agent plans against
        // has never contained a route to the goal. A wall added after the bake would need change
        // detection to be observed at all, which this phase does not have.
        _WallEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _WallEntity.Request_OverrideToSelf();
        _WallBody = Add_StaticBox(_WallEntity,
            FVector(0.0, BandY, WallCentreZ),
            FVector(WallHalfX, WallHalfY, WallHalfZ));

        Assert_True(ck::IsValid(_FloorBody) && ck::IsValid(_WallBody),
            "the slab and the wall must both produce valid Jolt bodies");

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(25.0f, 10.0f);
        Config.Set_TileSizeUu(500.0f);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(FCk_ShapeCapsule_Dimensions(96.0f, 42.0f)));
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(-VolumeHalfX, BandY - VolumeHalfY, VolumeFloorZ),
            FVector( VolumeHalfX, BandY + VolumeHalfY, VolumeCeilingZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid volume handle");
    }

    private FCk_Handle_JoltBody Add_StaticBox(FCk_Handle& InEntity, FVector InCentre, FVector InHalfExtents)
    {
        utils_transform::Add(InEntity,
            FTransform(FRotator::ZeroRotator, InCentre),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);

        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);

        return utils_jolt_body::Add(InEntity, Params);
    }

    private void Spawn_Walker()
    {
        const auto Spawn = FVector(SpawnX, BandY, SurfaceZ + AgentCentreOffsetZ);
        const auto Goal  = FVector(GoalX,  BandY, SurfaceZ + AgentCentreOffsetZ);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));
        // HoldAndRetry is the DEFAULT and is the policy under test: it is the one that used to hold
        // forever on a NoProgress cause. FailMove would short-circuit the bounded ladder.
        Params.Set_BlockedPolicy(ECk_CrowdAgent_BlockedPolicy::HoldAndRetry);

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"GroundNav_UnreachableGoal_Walker");

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

        utils_crowd_agent::BindTo_OnGoalReached(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalBlocked(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalBlocked(this, n"OnGoalBlocked"),
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

        // Last-resort guard, ahead of the engine TimeLimit: a wedge in ANY phase must report as a
        // named failure with the wall and the field torn down, never as an anonymous TimesUp that
        // leaves a sealed GroundNav volume standing in the shared PIE world.
        if (_ElapsedSec >= HardDeadlineSec)
        {
            Fail(f"HARD DEADLINE at {_ElapsedSec}s (builds={_BuildCompletions}, dispatched={_WalkerDispatched}, failed={_Failed}, blocks={_BlockedCount})");
            return;
        }

        if (_BuildRequested == false)
        {
            if (utils_jolt_body::Get_IsBodyAdded(_FloorBody) == false) { return; }
            if (utils_jolt_body::Get_IsBodyAdded(_WallBody) == false) { return; }

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

            if (DoCheck_SealIsInTheField() == false) { return; }

            Spawn_Walker();
            _WalkerDispatched = true;
            _DispatchedAtSec = _ElapsedSec;
            return;
        }

        if (ck::Is_NOT_Valid(_Agent))
        {
            Fail("the walker went invalid mid-run");
            return;
        }

        if (_Reached)
        {
            Fail(f"FALSE ARRIVAL: the walker reported OnGoalReached for a goal sealed behind a full-width wall that was in the field before it ever planned (t={_ElapsedSec}s). Widening the arrival radius, or treating a partial path's reachable end as an arrival, lies to a caller who asked to stand within its arrival radius of a specific point.");
            return;
        }

        if (_Failed)
        {
            if (_FailedAtSec >= 0.0 && _ElapsedSec < _FailedAtSec + SettleAfterFailSec)
            { return; }

            DoAssert_TerminalFailure();
            return;
        }

        if (_ElapsedSec >= _DispatchedAtSec + FailDeadlineSec)
        {
            const auto Pos = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Agent)));
            const auto State = utils_crowd_agent::Get_MovementState(_Agent);
            const auto Blocked = utils_crowd_agent::Get_IsGoalBlocked(_Agent);
            const auto Status = utils_nav::Get_PathStatus(_Agent);
            const auto SinceDispatch = _ElapsedSec - _DispatchedAtSec;
            Fail(f"SILENT HANG: {SinceDispatch}s after dispatch the walker has still not reported OnGoalFailed (position={Pos}, state={State}, navStatus={Status}, goalBlocked={Blocked}, blockedSignals={_BlockedCount}). Its goal stands behind a wall the field contained before the first plan - it can never arrive - so a move that neither succeeds nor fails is unobservable to every caller.");
        }
    }

    //------------------------------------------------------------------------
    // Staging guard
    //------------------------------------------------------------------------

    // Asked through the FACADE, with GroundNav already selected, BEFORE the first MoveTo. The whole
    // test is vacuous if the wall is not in the baked field - the agent then plans a straight route,
    // walks it, and arrives, which reads as a FALSE ARRIVAL defect when the truth is a broken
    // fixture. Both halves name themselves so the next log says which one, and the test stops here
    // rather than dispatching a walk whose result cannot mean anything.
    private bool DoCheck_SealIsInTheField()
    {
        // GUARD A - the seal exists. A probe just above the slab's top face, inside the wall's own
        // 160uu footprint on every axis, must find NOTHING walkable. If the wall's spans are missing
        // the slab's surface survives underneath it and this projects cleanly onto Z 0.
        auto SealQuery = FCk_NavSurface_ProjectionQuery(FVector(0.0, BandY, SurfaceZ + 20.0));
        SealQuery.Set_SearchHalfExtents(FVector(60.0, 60.0, 120.0));
        SealQuery.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

        const auto SealResult = utils_nav_surface::Try_ProjectPoint(SealQuery);

        if (SealResult.Get_Status() == ECk_NavSurface_QueryStatus::Success)
        {
            Fail(f"GUARD A (seal exists) FAILED: the facade projected a point inside the wall's own footprint onto walkable ground at {SealResult.Get_Location()}. The wall is NOT in the baked field, so the walk that follows could only ever arrive - fix the fixture, not the crowd.");
            return false;
        }

        // GUARD B - the seal separates. Even a wall that rasterized could leave the goal reachable if
        // it failed to span the field, so ask the reachability question the walk is about to ask.
        const auto Spawn = FVector(SpawnX, BandY, SurfaceZ + AgentCentreOffsetZ);
        const auto Goal  = FVector(GoalX,  BandY, SurfaceZ + AgentCentreOffsetZ);

        const auto Reachability = utils_nav_surface::Get_IsReachable(
            FCk_NavSurface_ReachabilityQuery(Spawn, Goal));

        if (Reachability != ECk_NavSurface_Reachability::Unreachable)
        {
            Fail(f"GUARD B (seal separates) FAILED: the facade answered {Reachability} for start -> goal across the wall, so the two ends are still in one connected component (or the provider was not ready to answer). Unreachable is the only answer that makes the bounded-failure assertions below meaningful.");
            return false;
        }

        return true;
    }

    //------------------------------------------------------------------------
    // Assertions
    //------------------------------------------------------------------------

    private void DoAssert_TerminalFailure()
    {
        Assert_Equals_Int(_FailedCount, 1,
            "the blocked move reported OnGoalFailed exactly once - a terminal signal that repeats is not terminal, and a caller that re-dispatches on it would loop");

        const auto State = utils_crowd_agent::Get_MovementState(_Agent);
        Assert_True(State != ECk_CrowdAgent_MovementState::Walking,
            f"the agent STOPPED when its move failed (movement state={State}). A terminal OnGoalFailed while the agent is still Walking means the failure was reported but the press never ended.");

        Assert_False(utils_crowd_agent::Get_IsGoalBlocked(_Agent),
            "the GoalBlocked hold was released when the move failed - a failed move is terminal, so leaving the agent flagged as blocked would have BlockedRecheck keep re-planning an episode nobody owns any more.");
        Assert_True(utils_crowd_agent::Get_IsGoalFailedHold(_Agent),
            "the unreachable goal remains in the stable failed-goal hold");

        // The geometric detector names an AGENT blocker; nothing here is an agent.
        // A GoalOccupied verdict would mean the wrong detector answered.
        if (_BlockedCount > 0)
        {
            Assert_True(_BlockedReasonWasNoProgress,
                "OnGoalBlocked reported the NoProgress cause. A static obstruction has no agent blocker to wait out, and the GoalOccupied cause deliberately holds UNBOUNDED - reporting it here would put the agent in the one retry policy that never fails.");
            Assert_Equals_Int(_BlockedCount, 1,
                "OnGoalBlocked fired once per blocked EPISODE, not once per re-check");
        }

        Teardown();
        FinishSuccess();
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
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        _Reached = true;
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

        _FailedCount += 1;
        if (_Failed) { return; }

        _Failed = true;
        _FailedAtSec = _ElapsedSec;
    }

    UFUNCTION()
    private void OnGoalBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        if (IsFinished()) { return; }

        _BlockedCount += 1;
        if (_BlockedCount == 1)
        {
            _BlockedReasonWasNoProgress =
                InInfo.Get_Reason() == ECk_CrowdAgent_BlockedReason::NoProgress;
        }
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
        if (ck::IsValid(_WallEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_WallEntity);
            _WallEntity = FCk_Handle();
        }
        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}

class ACk_AutoTest_Crowd_GroundNav_Stall_UnreachableGoalFailsBounded_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_GroundNav_Stall_UnreachableGoalFailsBounded;
    default _TimeoutSeconds = 48.0f;

    // Mirrors the original's list verbatim (CkAutoTest_Crowd_Stall_UnreachableGoalFailsBounded.as
    // :528-550). A goal that cannot be reached is the CONDITION UNDER TEST and every terminal route
    // out of it is warning-level by design; the automation framework escalates any Warning to a
    // test failure, so the test's own deliberate output would fail it. Registered as plain
    // substrings (AddExpectedErrorPlain, Contains, suppress-all) - no regex, and a pattern that
    // never fires is not reported as missing, so listing all three costs nothing.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        // FProcessor_CrowdAgent_BlockedRecheck::DoFailMove - the bounded NoProgress ladder running
        // out of re-checks. Downgraded to Log verbosity in CkCrowd, so this no longer fires; kept
        // as the original keeps it, a zero-cost hedge against it going back to Warning.
        Out.Add("made no progress toward");
        // FProcessor_CrowdAgent_OnPathResolved, Failed branch
        // (CkCrowdAgent_OnPathResolved_Processor.cpp:336) - the plan GroundNav answers Unreachable:
        //   "CrowdAgent [..] PathPending -> Idle (path failed: ..)"
        Out.Add("(path failed:");
        // FCk_Nav_Algorithm::FindPathSync - Recast-only, so inert under a GroundNav world. Kept
        // verbatim from the original so the twin's list does not silently diverge.
        Out.Add("projection FAILED");
        return Out;
    }
}
