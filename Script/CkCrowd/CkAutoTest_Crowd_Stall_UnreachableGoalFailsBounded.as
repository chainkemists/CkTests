// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A PHYSICALLY BLOCKED MOVE FAILS, AND FAILS BOUNDED
//
// The regression this exists for: "a physically blocked move can never fail."
//
// Before the remaining-path-distance no-progress detector existed, an agent
// whose FROZEN polyline ran into geometry the planner had not seen when the
// path was computed simply pressed against it forever. Nothing escalated:
//   - the installed nav result stays Ready, so no nav-side failure fires;
//   - PathRefresh only reacts to stationary-AGENT cost discs, and there are
//     none here;
//   - the old feet-sample centroid ring could not see it either, because
//     ConstrainToNavmesh's FindMoveAlongSurface turns a wall press into a
//     lateral SLIDE - real displacement, zero progress toward the goal.
// The agent stayed Walking, at speed, forever, and no caller could observe it.
//
// Shape: identical staging to Crowd_Stall_RepathsAroundLateObstacle except the
// nav-null wall spans the ENTIRE nav volume in Y (|y| <= 1400 against a volume
// that reaches |y| = 1000). There is no alternate route: once the tiles rebuild
// the goal is in a disconnected component of the mesh. The move MUST terminate,
// within a budget derived from the settings, and the agent MUST end up Idle.
//
// WHAT THIS DOES AND DOES NOT PIN DOWN. The terminal signal can legitimately
// arrive by any of three routes, and the test deliberately accepts all three
// which one fires depends on what Recast returns for a re-path into a
// disconnected component from wherever the agent happens to be standing:
//   (a) BlockedRecheck::DoFailMove - the bounded NoProgress ladder
//       (2 stall re-paths, then GoalBlocked, then 3 bounded re-checks);
//   (b) Steering's partial-path final-stop - a Partial re-path whose reachable
//       end is short of the goal is walked to the end and reported failed;
//   (c) OnPathResolved's Failed branch - an empty/failed re-path result.
// All three are downstream of the SAME trigger: the no-progress detector
// noticing the stall and issuing a re-path at all. Without it none of them are
// ever reached, which is precisely the hang this test locks down. Asserting one
// specific route would encode a Recast implementation detail; asserting
// "terminates, bounded, Idle, and never claims arrival" is the contract.
//
// SHARED-WORLD HYGIENE: a leftover nav-null area would split the navmesh for
// every later crowd test. The wall comes down before the test reports, the run
// waits for the tiles to return, and DoEndPlay unpaints it as a backstop.
//
// Every nav query and rebuild kick goes to the neutral nav surface, and on CkGroundNav the fixture
// stages its own field over the origin floor, so it runs unchanged on any provider.
//============================================================================

class UCk_AutoTest_Crowd_Stall_UnreachableGoalFailsBounded : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 48.0f;

    private FCkAutoTest_GroundNavFixture _Field;

    private const float SpawnX = -700.0;
    private const float GoalX = 700.0;
    private const int32 RecoveryCorrelation = 909;

    // |y| <= 1400 against a nav volume that reaches |y| = 1000: the wall runs off
    // both ends of the mesh, so no route survives.
    private const float WallHalfX = 80.0;
    private const float WallHalfY = 1400.0;
    private const float WallHalfZ = 300.0;

    private const float32 WallProbeHalfExtentUu = 20.0f;
    private const float SampleIntervalSec = 0.1;
    // One poll of separation between the terminal broadcast and the state read, so
    // the assertions run against a settled frame rather than the signal's own.
    private const float SettleAfterFailSec = 0.2;

    // Worst case, derived symbolically from CkCrowd project settings rather than
    // measured - the numbers below are the SETTINGS, so a settings change that
    // outgrows this budget shows up as an arithmetic mismatch here, not as flake.
    //
    // Let W = _BlockDetectionNoProgressWindowSeconds (3.0s)
    //     I = _BlockDetectionInterval               (0.5s)
    //     S = _BlockDetectionMaxStallRepaths        (2)
    //     R = _BlockedRecheckInterval               (1.0s)
    //     N = _BlockedMaxRetries                    (3)
    //
    // A "no-progress window" costs W + 2I, not W: DoResetProgressWindow parks
    // _BestRemainingPathDistanceCm at Max, the next sample only SEEDS the baseline,
    // and the sampler runs on the I cadence - so one seed sample plus cadence
    // granularity ride on top of every window. Call that Wc = W + 2I = 4.0s.
    //
    //   staging: approach 620uu / 240cm/s + accel ramp        ~=  3.0s
    //   staging: async tile rebuild after the seal            ~=  2.0s
    //   first block: (S + 1) * Wc            = 3 * 4.0        ~= 12.0s
    //   each bounded retry cycle: R + path round-trip (~0.5s) + Wc
    //                                        = 1.0 + 0.5 + 4.0 = 5.5s
    //     ...and there are N of them         = 3 * 5.5        ~= 16.5s
    //   the re-check that finds the budget spent and calls DoFailMove   ~= 1.0s
    //                                                          ---------
    //                                            total from seal ~= 29.5s
    //                                            total from start ~= 34.5s
    //
    // A resumed retry does NOT re-run the full stall ladder: BlockedRecheck sets
    // _StallRepathCount = _BlockDetectionMaxStallRepaths on resume, so one window of
    // no progress re-blocks directly. Before that fix each cycle re-paid the whole
    // (S+1)-rung ladder - ~10s per cycle, ~40s total - which is what timed this test
    // out at 23.8s with blockedSignals=1 and the agent still Walking mid-resume.
    // If this budget starts failing again, check that invariant before raising it.
    private const float FailDeadlineSec = 38.0;
    private const float HardDeadlineSec = 41.0;
    private const int32 MaxTeardownPolls = 40;

    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_NavSurfaceMarkup _Wall;

    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _WallPainted = false;
    private float _WallPaintedAtSec = 0.0;

    private bool _Failed = false;
    private int32 _FailedCount = 0;
    private float _FailedAtSec = -1.0;
    private bool _Reached = false;

    private int32 _BlockedCount = 0;
    private bool _BlockedReasonWasNoProgress = false;
    private bool _SameGoalSpamIssued = false;
    private bool _SameGoalCompletionSeen = false;
    private ECk_Request_OperationResult _SameGoalCompletionResult =
        ECk_Request_OperationResult::Failed_Cancelled;
    private float _SameGoalSpamAtSec = -1.0;
    private int32 _HeldMoveEpisode = 0;
    private int32 _HeldPathRevision = 0;
    private FVector _HeldPosition;
    private FRotator _HeldRotation;
    private bool _RecoveryIssued = false;
    private float _RecoveryIssuedAtSec = -1.0;
    private FCk_Handle_CrowdAgent _OverlapNeighbor;
    private bool _OverlapStarted = false;
    private float _OverlapStartedAtSec = -1.0;

    private float _ElapsedSec = 0.0;

    private bool _TeardownStarted = false;
    private bool _TeardownPassed = false;
    private FString _TeardownMessage;
    private int32 _TeardownPolls = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // On CkGroundNav nothing in the shared level carries a field, so the fixture stages one over
        // the origin floor; on Recast the level's own navmesh is the surface and nothing is staged.
        if (utils_nav_surface::Get_Provider() == ECk_NavSurface_Provider::GroundNav &&
            _Field.Request_StageOriginField(InHandle) == false)
        {
            FinishFailure(_Field.Get_StagingError());
            return;
        }

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        _Field.Do_ReportCrossover("Crowd_Stall_UnreachableGoalFailsBounded", IsFinished() ? "finished" : "unfinished");
        _Field.Request_ReleaseOriginField();

        Destroy_Wall();
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ElapsedSec += SampleIntervalSec;

        auto SelfHandle = DoGet_ScriptEntity();

        if (_TeardownStarted)
        {
            Tick_Teardown(SelfHandle);
            return;
        }

        // Last-resort guard, ahead of the engine TimeLimit: a wedge in ANY phase must
        // report as a named failure with the wall unpainted, never as an anonymous
        // TimesUp that leaves a nav-null area splitting the shared PIE world.
        if (_ElapsedSec >= HardDeadlineSec)
        {
            Begin_Teardown(false, f"HARD DEADLINE at {_ElapsedSec}s (meshFound={_MeshFound}, wallPainted={_WallPainted}, failed={_Failed}, blocks={_BlockedCount})");
            return;
        }

        if (_MeshFound == false)
        {
            const auto CorridorProbeExtents = FVector(100.0, 100.0, 300.0);
            const auto Projected = Do_ProjectOntoSurface(FVector::ZeroVector, CorridorProbeExtents);
            if (Projected.Get_Status() != ECk_NavSurface_QueryStatus::Success)
            { return; }
            _FloorZ = float(Projected.Get_Location().Z);
            if (Do_ProjectOntoSurface(FVector(SpawnX, 0.0, _FloorZ), CorridorProbeExtents).Get_Status() != ECk_NavSurface_QueryStatus::Success)
            { return; }
            if (Do_ProjectOntoSurface(FVector(GoalX, 0.0, _FloorZ), CorridorProbeExtents).Get_Status() != ECk_NavSurface_QueryStatus::Success)
            { return; }

            _MeshFound = true;
            SpawnWalker(SelfHandle);
            return;
        }

        if (ck::Is_NOT_Valid(_Agent))
        {
            Begin_Teardown(false, "the walker went invalid mid-run");
            return;
        }

        if (_WallPainted == false)
        {
            // The path must be installed BEFORE the wall exists: a MoveTo issued
            // against the already-split mesh would fail at plan time and prove
            // nothing about a frozen polyline meeting new geometry.
            if (utils_nav::Get_PathStatus(_Agent) != ECk_Nav_PathStatus::Ready) { return; }
            if (utils_crowd_agent::Get_MovementState(_Agent) != ECk_CrowdAgent_MovementState::Walking) { return; }

            Paint_Wall();
            _WallPainted = true;
            _WallPaintedAtSec = _ElapsedSec;
            return;
        }

        if (_Reached)
        {
            Begin_Teardown(false, f"FALSE ARRIVAL: the walker reported OnGoalReached for a goal that is in a DISCONNECTED component of the navmesh (t={_ElapsedSec}s). Widening the arrival radius, or treating a partial path's reachable end as an arrival, lies to a caller who asked to stand within its arrival radius of a specific point.");
            return;
        }

        if (_Failed)
        {
            if (_FailedAtSec >= 0.0 && _ElapsedSec < _FailedAtSec + SettleAfterFailSec)
            { return; }

            if (_RecoveryIssued)
            {
                const auto RecoveryEpisode = utils_crowd_agent::Get_ActiveMoveEpisode(_Agent);
                if (RecoveryEpisode == _HeldMoveEpisode)
                {
                    if (_ElapsedSec >= _RecoveryIssuedAtSec + 1.0)
                    {
                        Begin_Teardown(false,
                            "a genuinely new correlated goal did not wake the failed-goal hold within 1s");
                    }
                    return;
                }

                Assert_Equals_Int(RecoveryEpisode, _HeldMoveEpisode + 1,
                    "a new correlated goal starts exactly one fresh movement episode");
                Assert_True(utils_nav::Get_PathResult(_Agent).Get_RequestRevision() != _HeldPathRevision,
                    "a new correlated goal issues exactly one fresh path request after the hold");
                Assert_Equals_Int(utils_crowd_agent::Get_ActiveMoveCorrelationId(_Agent), RecoveryCorrelation,
                    "the recovery episode is owned by the new caller correlation");
                Assert_False(utils_crowd_agent::Get_IsGoalFailedHold(_Agent),
                    "accepting a genuinely new goal clears the failed-goal hold");

                Begin_Teardown(true, "");
                return;
            }

            Assert_Equals_Int(_FailedCount, 1,
                "the blocked move reported OnGoalFailed exactly once - a terminal signal that repeats is not terminal, and a caller that re-dispatches on it would loop");

            const auto State = utils_crowd_agent::Get_MovementState(_Agent);
            Assert_True(State != ECk_CrowdAgent_MovementState::Walking,
                f"the agent STOPPED when its move failed (movement state={State}). A terminal OnGoalFailed while the agent is still Walking means the failure was reported but the press never ended.");

            Assert_False(utils_crowd_agent::Get_IsGoalBlocked(_Agent),
                "the GoalBlocked hold was released when the move failed - a failed move is terminal, so leaving the agent flagged as blocked would have BlockedRecheck keep re-planning an episode nobody owns any more.");
            Assert_True(utils_crowd_agent::Get_IsGoalFailedHold(_Agent),
                "the unreachable goal remains in the stable failed-goal hold");

            if (_SameGoalSpamIssued == false)
            {
                _SameGoalSpamIssued = true;
                _SameGoalSpamAtSec = _ElapsedSec;
                _HeldMoveEpisode = utils_crowd_agent::Get_ActiveMoveEpisode(_Agent);
                _HeldPathRevision = utils_nav::Get_PathResult(_Agent).Get_RequestRevision();
                _HeldPosition = utils_transform::Get_EntityCurrentLocation(
                    utils_transform::DoCastChecked(FCk_Handle(_Agent)));
                _HeldRotation = utils_transform::Get_EntityCurrentRotation(
                    utils_transform::DoCastChecked(FCk_Handle(_Agent)));
                utils_crowd_agent::Request_MoveTo(
                    _Agent,
                    FCk_Request_CrowdAgent_MoveTo(utils_crowd_agent::Get_ActiveGoal(_Agent)),
                    FCk_Delegate_Request_OnCompleted(this, n"OnSameHeldGoalCompleted"));
                return;
            }

            if (_ElapsedSec < _SameGoalSpamAtSec + 0.75)
            { return; }

            Assert_Equals_Int(utils_crowd_agent::Get_ActiveMoveEpisode(_Agent), _HeldMoveEpisode,
                "an identical non-forced MoveTo does not start a new failed movement episode");
            Assert_Equals_Int(utils_nav::Get_PathResult(_Agent).Get_RequestRevision(), _HeldPathRevision,
                "an identical non-forced MoveTo does not issue a new path query while held");
            Assert_True(_SameGoalCompletionSeen,
                "the suppressed held same-goal request completes its caller instead of hanging");
            Assert_True(_SameGoalCompletionResult == ECk_Request_OperationResult::Failed,
                f"the drained-but-undispatched held same-goal request reports Failed, not a misleading success (got {_SameGoalCompletionResult})");
            Assert_True(utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Idle,
                "same-goal spam leaves the failed agent Idle instead of toggling PathPending");
            const auto HeldNow = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Agent)));
            Assert_True((HeldNow - _HeldPosition).Size2D() <= 5.0,
                "same-goal spam produces no visible motion while held");

            // The geometric detector names an AGENT blocker; nothing here is an agent.
            // A GoalOccupied verdict would mean the wrong detector answered.
            if (_BlockedCount > 0)
            {
                Assert_True(_BlockedReasonWasNoProgress,
                    "OnGoalBlocked reported the NoProgress cause. A static obstruction has no agent blocker to wait out, and the GoalOccupied cause deliberately holds UNBOUNDED - reporting it here would put the agent in the one retry policy that never fails.");
                Assert_Equals_Int(_BlockedCount, 1,
                    "OnGoalBlocked fired once per blocked EPISODE, not once per re-check");
            }

            if (_OverlapStarted == false)
            {
                _OverlapStarted = true;
                _OverlapStartedAtSec = _ElapsedSec;
                _HeldPosition = HeldNow;
                auto ScriptEntity = DoGet_ScriptEntity();
                _OverlapNeighbor = SpawnIdleAgent(ScriptEntity, HeldNow);
                return;
            }

            if (_ElapsedSec < _OverlapStartedAtSec + 0.75)
            { return; }

            const auto HeldAfterPush = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Agent)));
            const auto NeighborAfterPush = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_OverlapNeighbor)));
            Assert_True((HeldAfterPush - _HeldPosition).Size2D() <= 2.0,
                "a failed-held agent yields zero displacement to dense PushApart overlap");
            Assert_True((HeldAfterPush - NeighborAfterPush).Size2D() >= 75.0,
                "the non-held neighbor absorbs the overlap correction from a failed-held anchor");
            const auto HeldRotationAfterPush = utils_transform::Get_EntityCurrentRotation(
                utils_transform::DoCastChecked(FCk_Handle(_Agent)));
            Assert_True(Math::Abs(Math::FindDeltaAngleDegrees(_HeldRotation.Yaw, HeldRotationAfterPush.Yaw)) <= 0.5f,
                "a failed-held agent keeps its facing stable through repeated held ticks and dense overlap");

            _RecoveryIssued = true;
            _RecoveryIssuedAtSec = _ElapsedSec;
            auto Recovery = FCk_Request_CrowdAgent_MoveTo(
                FVector(SpawnX, 0.0, _FloorZ));
            Recovery.Set_CorrelationId(RecoveryCorrelation);
            utils_crowd_agent::Request_MoveTo(_Agent, Recovery);
            return;
        }

        if (_ElapsedSec >= FailDeadlineSec)
        {
            const auto Pos = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Agent)));
            const auto State = utils_crowd_agent::Get_MovementState(_Agent);
            const auto Blocks = _BlockedCount;
            const auto Blocked = utils_crowd_agent::Get_IsGoalBlocked(_Agent);
            const auto SinceWall = _ElapsedSec - _WallPaintedAtSec;
            Begin_Teardown(false, f"SILENT HANG: {SinceWall}s after the corridor was sealed the walker has still not reported OnGoalFailed (position={Pos}, state={State}, goalBlocked={Blocked}, blockedSignals={Blocks}). Its goal is in a disconnected component of the navmesh - it can never arrive - so a move that neither succeeds nor fails is unobservable to every caller.");
        }
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
    private void OnSameHeldGoalCompleted(
        FCk_Handle InRequestOwner,
        ECk_Request_OperationResult InResult)
    {
        _SameGoalCompletionSeen = true;
        _SameGoalCompletionResult = InResult;
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

    private void SpawnWalker(FCk_Handle& InOwner)
    {
        const auto Spawn = FVector(SpawnX, 0.0, _FloorZ + 100.0);
        const auto Goal = FVector(GoalX, 0.0, _FloorZ);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        // HoldAndRetry is the DEFAULT and is the policy under test: it is the one
        // that used to hold forever on a NoProgress cause. FailMove would short-
        // circuit the bounded ladder this test exists to exercise.
        Params.Set_BlockedPolicy(ECk_CrowdAgent_BlockedPolicy::HoldAndRetry);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(n"UnreachableGoal_Walker");

        const auto Rot = (Goal - Spawn).Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(Rot, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        _Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

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

    private FCk_Handle_CrowdAgent SpawnIdleAgent(FCk_Handle& InOwner, FVector InSpawn)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(
            AgentEntity,
            FTransform(FRotator::ZeroRotator, InSpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(
            AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(
            AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);
        return Agent;
    }

    private void Paint_Wall()
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(FVector(WallHalfX, WallHalfY, WallHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, _FloorZ), FVector::OneVector));

        _Wall = utils_nav_surface::Request_ImpassableBox(Request);
    }

    private void Destroy_Wall()
    {
        if (ck::Is_NOT_Valid(_Wall)) { return; }
        utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Wall));
        _Wall = FCk_Handle_NavSurfaceMarkup();
    }

    private void Begin_Teardown(bool InPassed, const FString& InFailMessage)
    {
        if (_TeardownStarted) { return; }
        _TeardownStarted = true;
        _TeardownPassed = InPassed;
        _TeardownMessage = InFailMessage;
        _TeardownPolls = 0;
        Destroy_Wall();
    }

    private FCk_NavSurface_ProjectionResult Do_ProjectOntoSurface(FVector InPoint, FVector InSearchHalfExtents) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(InSearchHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query);
    }

    private void Tick_Teardown(FCk_Handle& InSelf)
    {
        _TeardownPolls += 1;

        auto MeshRestored = true;
        if (_MeshFound)
        {
            MeshRestored = Do_ProjectOntoSurface(
                FVector(0.0, 0.0, _FloorZ),
                FVector(WallProbeHalfExtentUu, WallProbeHalfExtentUu, 300.0)).Get_Status() == ECk_NavSurface_QueryStatus::Success;
        }

        if (MeshRestored == false && _TeardownPolls < MaxTeardownPolls)
        { return; }

        if (_TeardownPassed) { FinishSuccess(); }
        else { FinishFailure(_TeardownMessage); }
    }
}

class ACk_AutoTest_Crowd_Stall_UnreachableGoalFailsBounded_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Stall_UnreachableGoalFailsBounded;
    default _TimeoutSeconds = 48.0f;

    // Sealing the corridor is the CONDITION UNDER TEST, and every terminal route
    // out of it is warning-level by design. The automation framework escalates any
    // Warning to a test failure, so the test's own deliberate output would fail it.
    // Same mechanism CkAutoTest_Crowd_Pathfinding_Failure uses for its deliberate
    // projection failure. Registered as plain substrings (AddExpectedErrorPlain,
    // Contains, suppress-all) - no regex, and a pattern that never fires is not
    // reported as missing, so listing all three costs nothing.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        // FProcessor_CrowdAgent_BlockedRecheck::DoFailMove - the bounded NoProgress
        // ladder running out of re-checks:
        //   "CrowdAgent [..] made no progress toward .. across N re-path attempts .."
        // Downgraded to Log verbosity in CkCrowd (an unreachable goal is a legitimate
        // gameplay outcome), so this no longer fires. Kept as a zero-cost hedge: a
        // suppress-all pattern that never matches is not reported as missing, and the
        // day it goes back to Warning this test does not start failing on its own
        // deliberate output.
        Out.Add("made no progress toward");
        // FProcessor_CrowdAgent_OnPathResolved, Failed branch - a re-path into the
        // disconnected component that Recast answers with no path at all:
        //   "CrowdAgent [..] PathPending -> Idle (path failed: ..)"
        Out.Add("(path failed:");
        // FCk_Nav_Algorithm::FindPathSync - start projection can fail on the frame the
        // tiles under the pressed agent are mid-rebuild:
        //   "FindPathSync: [Start] projection FAILED. .."
        Out.Add("projection FAILED");
        return Out;
    }
}
