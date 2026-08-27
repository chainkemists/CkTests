// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: BUNCH-UP SETTLES AT A SHARED GOAL
//============================================================================
//
// 15 agents on a 600cm ring, every one of them commanded to the SAME point.
// Exactly one can stand on it. The other fourteen have to STOP.
//
// Crowd_Goal_OccupiedGoal already covers the two-agent case: the latecomer
// contacts the agent standing ON the goal, the geometric detector fires, and
// it holds. That detector only ever looks at the goal itself, so it answers
// for agent #2 and nobody else - agent #3 contacts agent #2, not the goal,
// and learns nothing. At 15 agents only the innermost ring is in contact with
// anything the detector can see, so the outer twelve press inward forever,
// each one shoving the ring in front of it, and the whole formation fidgets
// indefinitely. That is what this test measures, and why it needs 15 agents
// rather than 3: the defect is in the PROPAGATION, not the detection.
//
// The contract asserted here (the framework fix generalises BlockDetect to
// settle a Walking agent against any SETTLED neighbour that shares its goal
// and is closer to it, so settling propagates transitively outward):
//
//   Phase A - every agent reaches a terminal steering state within 15s of
//     measured time. Terminal means reached-the-goal OR the resumable
//     GoalBlocked hold. The goal-FAILED hold is NOT terminal for our
//     purposes and fails the test outright: a crowd at a busy shelf must
//     degrade to "waiting, will take it when it frees", never to "this move
//     is over". That distinction is the whole point of the hold being
//     resumable (see Crowd_Goal_OccupiedGoal's Phase 2).
//
//   Phase B - 5s of genuine quiet. No agent drifts more than 8cm from where
//     it settled, none exceeds 5cm/s once its brake has finished, none
//     re-enters Walking, and none starts a new move episode. Those four
//     together are what "fidget" means operationally: a jittering agent
//     violates at least one of them every second, while a settled formation
//     violates none.
//
//   And the formation is real, not a collapse: at least one agent genuinely
//   reached the goal, every other one is in the GoalBlocked hold, and no pair
//   interpenetrates.
//
// AT-REST SEPARATION FLOOR - deliberately NOT loosened for the crowd case.
// Crowd_Separation_Convergence derives the number: while agents actively
// drive inward the residual overlap is an EQUILIBRIUM that scales with
// press-speed x frame-time (its 61cm floor), but once the inward drive is
// gone PushApart converges geometrically to exactly the contact distance and
// the floor is the radius sum, 84cm, with only a 0.1cm tolerance for the
// asymptote. Phase B here is that same drive-free regime - a GoalBlocked
// agent is Idle, so Steering never runs on it - and PushApart runs on idle
// agents too. So the same 84 - 0.1 floor applies, and a settled pair reading
// below it is a real resolver defect. Do not add slack to make it pass.
//
// Separations are measured in 2D on purpose: the bodies are cylinders and
// the fix's own contact test is 2D, so a Z difference must not be allowed to
// paper over an XY overlap.
//============================================================================

class UCk_AutoTest_Crowd_BunchUp_SettlesAtSharedGoal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 40.0f;

    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private TArray<FVector> _QuietStartPos;
    private TArray<int32> _QuietStartEpisode;

    private bool _NavProbeReady = false;
    private bool _AgentsSpawned = false;
    private bool _Measuring = false;
    private bool _QuietWindowOpen = false;

    private float _PrepElapsedSec = 0.0;    // navmesh bake + spawn + path resolution
    private float _ElapsedSec = 0.0;        // measured time since every path resolved Ready
    private float _QuietElapsedSec = 0.0;
    private int32 _MovingSamples = 0;

    private const int32 AgentCount = 15;
    private const float RingRadius = 600.0;
    private const FVector Centre = FVector(0.0, 0.0, 100.0);

    // Accumulated by the constant interval, never from InDeltaT - the timer's delta can read 0.0.
    private const float SampleIntervalSec = 0.1;

    // The discrimination is carried by the ALL-15-terminal requirement, not by this number: every
    // pre-fix run left at least one agent Walking FOREVER (measured 14/15 at 15s, 12/15 at 8s), so
    // no deadline makes the pre-fix behaviour pass. 15s exists to cover the loaded-machine settle
    // path honestly: markup roots the chain only after 1.5s of windowed stillness, each ring blocks
    // on a 0.5s cadence, blocked agents coast to rest, and a 4-lane full-suite run dilates all of
    // it - measured 14/15 by 8s with the last block landing late, zero direction reversals anywhere.
    private const float SettleDeadlineSec = 15.0;

    // Bounds the pre-measurement stretch (navmesh bake, spawn, 15 path resolutions) so a setup that
    // never resolves names what it was waiting on instead of dying as an anonymous engine TimesUp.
    private const float PrepDeadlineSec = 10.0;

    private const float QuietWindowSec = 5.0;

    // A GoalBlocked agent is not stopped by the transition itself - AccelClamp's Idle branch ramps
    // it down over roughly half a second. The whole formation is already quiescent at Phase-B entry
    // (see DoSamplePhaseA), so this grace only covers the last few frames of that ramp.
    private const float QuietSpeedGraceSec = 1.0;

    private const float MaxQuietDriftCm = 8.0;
    private const float SettledSpeedCm = 5.0;

    // Anti-vacuous guard: a run where pathing silently failed and nobody ever moved would satisfy
    // every "is it still?" assertion below. At 100ms sampling a 2.5s transit produces ~25 samples
    // with real motion, so 10 is a floor that only a genuinely dead run can miss.
    private const float MovingSpeedCm = 20.0;
    private const int32 MinMovingSamples = 10;

    private const float MinPairwiseSepCm = 84.0;    // _Radius * 2 - asserted AT REST
    private const float ContactToleranceCm = 0.1;   // admits PushApart's asymptote and nothing else
    private const float GoalMatchToleranceCm = 1.0; // _ActiveGoal stores the raw request target

    // Peak heading swing over the agent's whole run, from the diag recorder. This catches the
    // in-place fidgeter that every position/speed check can miss: an agent can end the run settled
    // and still have spent the middle of it spinning on the spot. Measured on the first red run
    // the 14 agents that transited cleanly peaked at ~9-12 degrees, while the one that never settled
    // peaked at 96.4. 60 is 5x the clean norm and well under the fidget signature, so it separates
    // the two populations rather than splitting either one.
    private const float MaxAngularDeltaDeg = 60.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Probe from a real ring point through the centre, so the readiness probe travels the same
        // route every agent will. A projection-only probe can select different nav data and
        // false-positive.
        const auto ProbeStart = Centre + FVector(RingRadius, 0.0, 0.0);
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, ProbeStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::BindTo_OnPathReady(LocalHandle,
            FCk_Delegate_Nav_OnPathReady(this, n"OnNavProbeReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_nav::BindTo_OnPathFailed(LocalHandle,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnNavProbeFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Kick the navmesh: AutoTests_CkTests_Level has the fixture but the bake is lazy.
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);
        utils_nav::Request_FindPath(LocalHandle, FCk_Request_Nav_FindPath(Centre));

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSample"));
    }

    UFUNCTION()
    private void OnNavProbeReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        if (InResult.Get_Status() != ECk_Nav_PathStatus::Ready)
        {
            FinishFailure(f"navigation readiness probe returned status {InResult.Get_Status()} instead of Ready");
            return;
        }

        if (InResult.Get_Waypoints().Num() < 1)
        {
            FinishFailure("navigation readiness probe returned no waypoints");
            return;
        }

        _NavProbeReady = true;
    }

    UFUNCTION()
    private void OnNavProbeFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_nav::Get_PathResult(InHandle);
        FinishFailure(f"navigation readiness probe failed: reason={Result.Get_Diagnostics().Get_LastFailReason()}");
    }

    UFUNCTION()
    private void OnSample(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_Measuring == false)
        {
            _PrepElapsedSec += SampleIntervalSec;
            if (_PrepElapsedSec >= PrepDeadlineSec)
            {
                FinishFailure(f"SETUP NEVER COMPLETED within {PrepDeadlineSec}s: navProbeReady={_NavProbeReady} agentsSpawned={_AgentsSpawned}. The navmesh bake or the agents' path requests never resolved, so nothing this test exists to measure ever ran.");
                return;
            }
        }

        if (_AgentsSpawned == false)
        {
            if (_NavProbeReady == false) { return; }

            auto SelfHandle = DoGet_ScriptEntity();
            DoSpawnAgents(SelfHandle);
            _AgentsSpawned = true;
            return;
        }

        if (DoValidateAgents() == false) { return; }

        if (_Measuring == false)
        {
            DoTryStartMeasuring();
            return;
        }

        if (_QuietWindowOpen == false)
        {
            DoSamplePhaseA();
            return;
        }

        DoSamplePhaseB();
    }

    // ---- Phase A: everyone must reach a terminal state, and come to rest in it -------------------

    private void DoSamplePhaseA()
    {
        _ElapsedSec += SampleIntervalSec;

        auto AnyAgentMovedThisSample = false;
        auto TerminalCount = 0;
        auto QuiescentCount = 0;

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            auto Agent = _Agents[i];

            if (utils_crowd_agent::Get_IsGoalFailedHold(Agent))
            {
                DoEmitDigests();
                FinishFailure(f"TERMINAL FAILURE: agent {i} entered the goal-FAILED hold at t={_ElapsedSec}s. A crowd at an occupied goal must degrade to the RESUMABLE GoalBlocked hold - an agent that has terminally failed will never take the spot when it frees.");
                return;
            }

            const auto Speed = DoGet_Speed(Agent);
            if (Speed > MovingSpeedCm) { AnyAgentMovedThisSample = true; }
            if (Speed <= SettledSpeedCm) { ++QuiescentCount; }
            if (DoIsTerminal(Agent)) { ++TerminalCount; }
        }

        if (AnyAgentMovedThisSample) { ++_MovingSamples; }

        // Quiescence is part of the entry condition, not just terminality. The GoalBlocked
        // transition does not zero the velocity - it goes Idle and lets AccelClamp ramp down - so
        // an agent latched the instant it blocks is still coasting, and Phase B would measure its
        // own braking as drift. Crowd_Goal_OccupiedGoal makes the same distinction when it latches
        // the squatter's resting spot.
        if (TerminalCount == _Agents.Num() && QuiescentCount == _Agents.Num())
        {
            DoOpenQuietWindow();
            return;
        }

        if (_ElapsedSec >= SettleDeadlineSec)
        {
            const auto Census = DoBuild_Census();
            const auto Total = _Agents.Num();
            DoEmitDigests();
            FinishFailure(f"NEVER SETTLED: {TerminalCount}/{Total} agents reached a terminal state within {SettleDeadlineSec}s ({QuiescentCount} were at rest). {Census}. Agents commanded to an already-taken goal have no way to learn it is taken from anything except the goal itself, so every agent behind the first ring presses inward forever.");
        }
    }

    private void DoOpenQuietWindow()
    {
        _QuietStartPos.Empty();
        _QuietStartEpisode.Empty();

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            _QuietStartPos.Add(DoGet_Position(_Agents[i]));
            _QuietStartEpisode.Add(utils_crowd_agent::Get_ActiveMoveEpisode(_Agents[i]));
        }

        _QuietElapsedSec = 0.0;
        _QuietWindowOpen = true;

        ck::crowd::Log(f"[BUNCHUP] all {_Agents.Num()} agents terminal and at rest at t={_ElapsedSec}s - opening the {QuietWindowSec}s quiet window");
    }

    // ---- Phase B: the formation must stay put -----------------------------------------------------

    private void DoSamplePhaseB()
    {
        _QuietElapsedSec += SampleIntervalSec;

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            auto Agent = _Agents[i];

            if (utils_crowd_agent::Get_IsGoalFailedHold(Agent))
            {
                DoEmitDigests();
                FinishFailure(f"agent {i} fell out of its hold into the terminal goal-FAILED state {_QuietElapsedSec}s into the quiet window - the hold must survive as long as the goal stays taken");
                return;
            }

            const auto Drift = DoGet_Dist2D(DoGet_Position(Agent), _QuietStartPos[i]);
            if (Drift > MaxQuietDriftCm)
            {
                DoEmitDigests();
                FinishFailure(f"FIDGET: agent {i} moved {Drift}cm from where it settled (limit {MaxQuietDriftCm}cm) at {_QuietElapsedSec}s into the quiet window. A settled crowd holds its formation; this one is still shuffling.");
                return;
            }

            if (_QuietElapsedSec > QuietSpeedGraceSec)
            {
                const auto Speed = DoGet_Speed(Agent);
                if (Speed > SettledSpeedCm)
                {
                    DoEmitDigests();
                    FinishFailure(f"FIDGET: agent {i} is still moving at {Speed}cm/s (limit {SettledSpeedCm}cm/s) {_QuietElapsedSec}s into the quiet window");
                    return;
                }
            }

            const auto State = utils_crowd_agent::Get_MovementState(Agent);
            if (State == ECk_CrowdAgent_MovementState::Walking)
            {
                DoEmitDigests();
                FinishFailure(f"RE-ENGAGED: agent {i} went back to Walking {_QuietElapsedSec}s into the quiet window. The hold is supposed to end when the goal CLEARS; nothing cleared here, so the agent is oscillating between holding and pressing.");
                return;
            }

            const auto StartEpisode = _QuietStartEpisode[i];
            const auto Episode = utils_crowd_agent::Get_ActiveMoveEpisode(Agent);
            if (Episode != StartEpisode)
            {
                DoEmitDigests();
                FinishFailure(f"NEW EPISODE: agent {i}'s move episode changed from {StartEpisode} to {Episode} during the quiet window. A hold retains its episode - a fresh one means the agent re-issued its own move and the settle is not stable.");
                return;
            }
        }

        if (_QuietElapsedSec < QuietWindowSec) { return; }

        DoAssertFinalFormation();
    }

    private void DoAssertFinalFormation()
    {
        auto ReachedCount = 0;
        TArray<FVector> Finals;

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            auto Agent = _Agents[i];
            Finals.Add(DoGet_Position(Agent));

            if (utils_crowd_agent::Get_HasReachedActiveGoal(Agent))
            {
                ++ReachedCount;
            }
            else
            {
                Assert_True(utils_crowd_agent::Get_IsGoalBlocked(Agent),
                    f"agent {i} came to a stop without reaching the goal and without being in the resumable GoalBlocked hold - it is parked in a state nothing will ever resume, and state={utils_crowd_agent::Get_MovementState(Agent)}");
            }

            const auto GoalDelta = float((utils_crowd_agent::Get_ActiveGoal(Agent) - Centre).Size());
            Assert_True(GoalDelta <= GoalMatchToleranceCm,
                f"agent {i}'s active goal sits {GoalDelta}cm from the shared centre - its MoveTo never took, so this run never measured the shared-goal case at all");

            // Asserted here, at the END of the quiet window, so it reports even on a run that
            // settled: a clean settle and a violent one are indistinguishable from final positions.
            const auto Recorder = utils_crowd_agent_diag::Get_RecorderData(Agent);
            const auto AngularDelta = Recorder.Get_MaxAngularDeltaDeg();
            Assert_True(AngularDelta <= MaxAngularDeltaDeg,
                f"JITTER: agent {i} swung {AngularDelta} degrees between consecutive diag samples (ceiling {MaxAngularDeltaDeg}). An agent that transits and settles cleanly peaks around 12; this one spun on the spot instead of walking.");
        }

        const auto Total = _Agents.Num();
        const auto HoldingCount = Total - ReachedCount;

        Assert_True(ReachedCount >= 1,
            f"NOBODY TOOK THE GOAL: {ReachedCount} of {Total} agents reached it. The formation settled around a point none of them is standing on, which means they blocked each other out of a goal that was free.");

        Assert_True(_MovingSamples >= MinMovingSamples,
            f"only {_MovingSamples} samples saw an agent above {MovingSpeedCm}cm/s (need >= {MinMovingSamples}) - the crowd never actually walked, so every stillness assertion above passed vacuously");

        for (int32 i = 0; i < Finals.Num(); ++i)
        {
            for (int32 j = i + 1; j < Finals.Num(); ++j)
            {
                const auto PairSep = DoGet_Dist2D(Finals[i], Finals[j]);
                Assert_True(PairSep >= MinPairwiseSepCm - ContactToleranceCm,
                    f"agents {i} and {j} are interpenetrating at rest: {PairSep}cm apart, floor {MinPairwiseSepCm}cm (the radius sum). PushApart runs on idle agents and converges to the contact distance once the inward drive stops, so a settled pair below the floor is a resolver defect.");
            }
        }

        ck::crowd::Log(f"[BUNCHUP] settled formation verified: {ReachedCount} reached, {HoldingCount} holding, {_MovingSamples} moving samples during transit");

        FinishSuccess();
    }

    // ---- Setup -------------------------------------------------------------------------------------

    private void DoSpawnAgents(FCk_Handle& InOwner)
    {
        const auto AngleStep = (2.0 * Math::PI) / float(AgentCount);
        for (int32 i = 0; i < AgentCount; ++i)
        {
            const auto Angle = AngleStep * float(i);
            const auto Spawn = Centre + FVector(RingRadius * Math::Cos(Angle), RingRadius * Math::Sin(Angle), 0.0);
            _Agents.Add(SpawnAgent(InOwner, Spawn, FName(f"BunchUpAgent_{i}")));
        }
    }

    private void DoTryStartMeasuring()
    {
        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            FCk_Handle AgentEntity = _Agents[i];
            const auto Status = utils_nav::Get_PathStatus(AgentEntity);

            if (Status == ECk_Nav_PathStatus::Failed || Status == ECk_Nav_PathStatus::Partial)
            {
                const auto Result = utils_nav::Get_PathResult(AgentEntity);
                FinishFailure(f"agent {i}'s path failed before the crowd ever started walking: status={Status}, reason={Result.Get_Diagnostics().Get_LastFailReason()}");
                return;
            }

            if (Status != ECk_Nav_PathStatus::Ready) { return; }
        }

        // Only now does the measured clock start: the settle deadline must budget steering time,
        // never the navmesh bake and path resolution that precede it.
        _ElapsedSec = 0.0;
        _Measuring = true;
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        // A FRESH child entity per agent. utils_crowd_agent::Add composes onto the handle it is
        // given and permits one agent per entity, so a shared owner leaves a crowd of exactly one.
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        const auto Rot = (Centre - InSpawn).Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(Rot, InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        // Every agent gets the IDENTICAL target - that is the condition under test.
        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(Centre));

        // Opt into the diag recorder so a red run dumps a per-agent path digest instead of a bare
        // count. Display verbosity, so it never escalates into an assertion failure of its own.
        utils_crowd_agent_diag::Track(Agent, InSpawn, Centre);

        return Agent;
    }

    // ---- Helpers -----------------------------------------------------------------------------------

    private bool DoValidateAgents()
    {
        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (ck::Is_NOT_Valid(_Agents[i]))
            {
                FinishFailure(f"agent {i} went invalid mid-run - possible early destroy / lifetime issue");
                return false;
            }
        }
        return true;
    }

    private bool DoIsTerminal(FCk_Handle_CrowdAgent InAgent)
    {
        return utils_crowd_agent::Get_HasReachedActiveGoal(InAgent)
            || utils_crowd_agent::Get_IsGoalBlocked(InAgent);
    }

    private float DoGet_Speed(FCk_Handle_CrowdAgent InAgent)
    {
        FCk_Handle Generic = InAgent;
        return float(utils_velocity::Get_CurrentVelocity(
            utils_velocity::DoCastChecked(Generic)).Size());
    }

    private FVector DoGet_Position(FCk_Handle_CrowdAgent InAgent)
    {
        FCk_Handle Generic = InAgent;
        return utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(Generic));
    }

    // Planar distance: the bodies are cylinders, so a Z difference must not mask an XY overlap.
    private float DoGet_Dist2D(FVector InA, FVector InB)
    {
        return float(FVector(InA.X - InB.X, InA.Y - InB.Y, 0.0).Size());
    }

    private FString DoBuild_Census()
    {
        auto ReachedCount = 0;
        auto BlockedCount = 0;
        auto FailedHoldCount = 0;
        auto WalkingCount = 0;
        auto PathPendingCount = 0;
        auto IdleCount = 0;
        auto NoStateCount = 0;

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            auto Agent = _Agents[i];

            if (utils_crowd_agent::Get_HasReachedActiveGoal(Agent)) { ++ReachedCount; }
            if (utils_crowd_agent::Get_IsGoalBlocked(Agent)) { ++BlockedCount; }
            if (utils_crowd_agent::Get_IsGoalFailedHold(Agent)) { ++FailedHoldCount; }

            const auto State = utils_crowd_agent::Get_MovementState(Agent);
            if (State == ECk_CrowdAgent_MovementState::Walking) { ++WalkingCount; }
            else if (State == ECk_CrowdAgent_MovementState::PathPending) { ++PathPendingCount; }
            else if (State == ECk_CrowdAgent_MovementState::Idle) { ++IdleCount; }
            else { ++NoStateCount; }
        }

        return f"census: reached={ReachedCount} goalBlocked={BlockedCount} failedHold={FailedHoldCount} | movement Walking={WalkingCount} PathPending={PathPendingCount} Idle={IdleCount} None={NoStateCount}";
    }

    private void DoEmitDigests()
    {
        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (ck::Is_NOT_Valid(_Agents[i])) { continue; }
            utils_crowd_agent_diag::EmitDigest_ForAgent(_Agents[i], 0, "BunchUp", i);
        }
    }
}

class ACk_AutoTest_Crowd_BunchUp_SettlesAtSharedGoal_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_BunchUp_SettlesAtSharedGoal;
    default _TimeoutSeconds = 40.0f;
}
