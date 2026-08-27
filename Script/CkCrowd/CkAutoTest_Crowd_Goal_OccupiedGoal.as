// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: OCCUPIED GOAL (block, hold, resume)
//============================================================================
//
// Two agents are given the SAME goal. The first arrives and stands on it. The
// second CANNOT reach it - the goal is physically occupied.
//
// Before the block-detection tier existed, the second agent "rapidly rotated
// left/right, almost vibrating" and eventually shoved the first agent clean off
// its own goal until the point came within arrival radius (observed in PIE, and
// reproduced here: the arrived agent was displaced 69cm and the latecomer
// bulldozed its way to 32cm from the goal).
//
// Three things must now hold, and this test asserts each separately:
//
//   1. DETECT. The latecomer notices the goal is unreachable and reports it
//      OnGoalBlocked, reason GoalOccupied, naming the blocker. The closest it
//      can physically get is (SelfRadius + BlockerRadius) from the blocker's
//      centre, which is further out than its arrival radius. That is geometry,
//      not a timeout: no guessing, no waiting for a stagnation window.
//
//   2. HOLD WITHOUT EVICTING. It stops and waits. The agent that already
//      arrived keeps its spot - no body-checking an NPC away from its shelf.
//
//   3. RESUME. When the goal clears, the latecomer goes and takes it. This is
//      the assertion that rules out the tempting shortcut of silently widening
//      the arrival radius and declaring "arrived": that would be TERMINAL - an
//      agent that has "arrived" 100cm out is Idle and would never walk the last
//      metre once the blocker left.
//============================================================================

class UCk_AutoTest_Crowd_Goal_OccupiedGoal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle_CrowdAgent _Squatter;   // arrives first, then stands on the goal
    private FCk_Handle_CrowdAgent _Latecomer;  // arrives second, finds the goal taken

    private bool _SquatterArrived = false;
    private bool _SquatterSettled = false;
    private bool _LatecomerReachedGoal = false;
    private FVector _SquatterRestPos = FVector::ZeroVector;

    private bool _BlockedFired = false;
    private bool _BlockedReasonWasOccupied = false;
    private bool _BlockedNamedABlocker = false;

    private bool _SquatterSentAway = false;

    private float _ElapsedSec = 0.0;
    private float _MaxSquatterDrift = 0.0;

    private const FVector Goal           = FVector(400.0, 0.0, 0.0);
    private const FVector SquatterSpawn  = FVector(200.0, 0.0, 0.0);    // near - arrives first
    private const FVector LatecomerSpawn = FVector(-300.0, 0.0, 0.0);   // far  - arrives second
    private const FVector SquatterExit   = FVector(-100.0, 350.0, 0.0); // where we send it to free the goal

    private const float SampleIntervalSec = 0.05;

    // Give the latecomer time to reach the occupied goal, detect the block, and settle.
    private const float BlockDeadlineSec = 9.0;
    // Then free the goal and give it time to notice, re-path, and walk in.
    private const float ClearGoalAtSec   = 10.0;
    private const float ResumeDeadlineSec = 24.0;

    // The squatter has ARRIVED. Nothing should push it meaningfully off the spot it chose. Some give
    // is physical (the newcomer's body de-overlapping as it comes to a stop), but the wholesale
    // eviction seen in PIE - 69cm, most of a body width - must be gone.
    private const float MaxSquatterDriftCm = 25.0;

    // Speed (cm/s) below which the squatter counts as having come to rest.
    private const float SettledSpeedCm = 5.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        _Squatter = SpawnAgent(LocalHandle, SquatterSpawn, n"OccupiedGoal_Squatter");
        _Latecomer = SpawnAgent(LocalHandle, LatecomerSpawn, n"OccupiedGoal_Latecomer");

        utils_crowd_agent::BindTo_OnGoalReached(_Squatter,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnSquatterArrived"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalReached(_Latecomer,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnLatecomerArrived"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalBlocked(_Latecomer,
            FCk_Delegate_CrowdAgent_OnGoalBlocked(this, n"OnLatecomerBlocked"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Both are sent to the SAME point. That is the condition under test.
        utils_crowd_agent::Request_MoveTo(_Squatter, FCk_Request_CrowdAgent_MoveTo(Goal));
        utils_crowd_agent::Request_MoveTo(_Latecomer, FCk_Request_CrowdAgent_MoveTo(Goal));

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSample"));
    }

    UFUNCTION()
    private void OnSquatterArrived(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        if (_SquatterArrived) { return; }

        // NOTE: the agent has NOT stopped yet. OnGoalReached fires on ENTERING the arrival radius,
        // while the agent is still moving at speed; AccelClamp then ramps it down over ~0.5s, during
        // which it coasts a further ~30cm. Latching its "resting spot" here would count that coast as
        // eviction - the drift number would be dominated by the squatter's own braking, not by anything
        // the latecomer did. Wait until it has actually come to rest (see OnSample).
        _SquatterArrived = true;

        ck::crowd::Log("[OCCUPIED] squatter reached its goal - waiting for it to come to rest before measuring");
    }

    UFUNCTION()
    private void OnLatecomerArrived(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }

        // Only counts once the goal has actually been freed. If this fired while the squatter was
        // still standing on the goal, the latecomer got there by SHOVING it - the original bug.
        _LatecomerReachedGoal = true;
        ck::crowd::Log(f"[OCCUPIED] latecomer reached the goal at t={_ElapsedSec} (squatterSentAway={_SquatterSentAway})");
    }

    UFUNCTION()
    private void OnLatecomerBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        if (IsFinished()) { return; }

        _BlockedFired = true;
        _BlockedReasonWasOccupied = InInfo.Get_Reason() == ECk_CrowdAgent_BlockedReason::GoalOccupied;
        _BlockedNamedABlocker = ck::IsValid(InInfo.Get_BlockedBy());

        ck::crowd::Log(f"[OCCUPIED] latecomer BLOCKED at t={_ElapsedSec}: reason={InInfo.Get_Reason()} distToGoal={InInfo.Get_DistanceToGoal()}");
    }

    UFUNCTION()
    private void OnSample(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ElapsedSec += SampleIntervalSec;

        if (ck::Is_NOT_Valid(_Squatter) || ck::Is_NOT_Valid(_Latecomer))
        {
            FinishFailure("an agent went invalid mid-run");
            return;
        }

        if (_SquatterArrived)
        {
            const auto SquatterPos = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Squatter)));

            if (!_SquatterSettled)
            {
                // Latch the resting spot only once the agent has genuinely STOPPED. Anything before
                // this is its own deceleration coast, not displacement by anyone else.
                const auto Speed = float(utils_velocity::Get_CurrentVelocity(
                    utils_velocity::DoCastChecked(FCk_Handle(_Squatter))).Size());

                if (Speed <= SettledSpeedCm)
                {
                    _SquatterSettled = true;
                    _SquatterRestPos = SquatterPos;
                    ck::crowd::Log(f"[OCCUPIED] squatter came to rest at {_SquatterRestPos} (t={_ElapsedSec})");
                }
            }
            else
            {
                const auto Drift = float((SquatterPos - _SquatterRestPos).Size());
                if (Drift > _MaxSquatterDrift) { _MaxSquatterDrift = Drift; }
            }
        }

        // ---- Phase 1: the goal is occupied. Detect, hold, do not evict. ----
        if (!_SquatterSentAway && _ElapsedSec >= BlockDeadlineSec)
        {
            Assert_True(_SquatterArrived,
                "the first agent never reached the goal - this test never got to the condition it exists to measure");

            Assert_True(_BlockedFired,
                f"NO DETECTION: the latecomer never reported OnGoalBlocked, even though the goal was occupied for {BlockDeadlineSec}s. It has no way to know its goal is unreachable, so it will press against the blocker forever.");

            Assert_True(_BlockedReasonWasOccupied,
                "OnGoalBlocked fired with the wrong reason - the goal was occupied by a standing agent, which the geometric detector should identify exactly (not fall back to the no-progress safety net).");

            Assert_True(_BlockedNamedABlocker,
                "OnGoalBlocked did not name the blocking agent. The payload is what a gameplay-side queue manager needs in order to send the NPC elsewhere instead of having it stand and wait.");

            Assert_True(utils_crowd_agent::Get_IsGoalBlocked(_Latecomer),
                "the latecomer is not in the GoalBlocked state - it must HOLD (and be resumable), not silently give up or keep pressing.");

            Assert_True(!_LatecomerReachedGoal,
                "the latecomer reported OnGoalReached while the goal was still occupied - it can only have got there by SHOVING the agent that was standing on it. That is the eviction bug.");

            Assert_True(_MaxSquatterDrift <= MaxSquatterDriftCm,
                f"EVICTION: the agent that had already ARRIVED was pushed {_MaxSquatterDrift}cm off the spot it stopped on (limit {MaxSquatterDriftCm}cm). A later arrival is body-checking a standing agent off its own goal.");

            // ---- Free the goal. ----
            _SquatterSentAway = true;
            utils_crowd_agent::Request_MoveTo(_Squatter, FCk_Request_CrowdAgent_MoveTo(SquatterExit));
            ck::crowd::Log(f"[OCCUPIED] goal freed at t={_ElapsedSec} - squatter sent to {SquatterExit}");
            return;
        }

        // ---- Phase 2: the goal is free. The held agent must go and take it. ----
        if (_SquatterSentAway && _LatecomerReachedGoal)
        {
            FinishSuccess();
            return;
        }

        if (_SquatterSentAway && _ElapsedSec >= ResumeDeadlineSec)
        {
            const auto LatePos = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Latecomer)));
            const auto DistToGoal = float((LatePos - Goal).Size());

            FinishFailure(f"NOT RESUMED: the goal was freed at t={ClearGoalAtSec} but the latecomer never took it - still {DistToGoal}cm away at t={_ElapsedSec}, blocked={utils_crowd_agent::Get_IsGoalBlocked(_Latecomer)}. Being blocked must be a HOLD, not a terminal state. (This is exactly why the arrival radius must never be silently widened to fake an arrival: an agent that has 'arrived' 100cm out is Idle and never walks the last metre when the blocker leaves.)");
            return;
        }
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        const auto Rot = (Goal - InSpawn).Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(Rot, InSpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        return Agent;
    }
}

class ACk_AutoTest_Crowd_Goal_OccupiedGoal_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Goal_OccupiedGoal;
    default _TimeoutSeconds = 30.0f;
}
