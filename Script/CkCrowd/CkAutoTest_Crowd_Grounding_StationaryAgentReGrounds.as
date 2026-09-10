// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A STATIONARY AGENT RE-GROUNDS ON ITS LEASE
//============================================================================
//
// The grounding lease (FFragment_CrowdAgent_Grounding), and the contract that
// makes it safe to run on a settled crowd.
//
// ConstrainToNavmesh used to early-out whenever a frame staged zero
// displacement, which coupled a stationary agent's grounding to the avoidance
// solver happening to emit something. For years that coupling held BY ACCIDENT:
// PushApart's resolver never terminated, so every settled agent with a touching
// neighbour got sub-millimetre displacement every frame and was re-grounded
// every frame. _PushApartSlopCm ended the non-termination - correctly - and
// stationary agents' Z then froze wherever it was. Any elevation error (a
// spawn-frame fall, a long-frame unclamped vertical integration, a ramp edge)
// became PERMANENT, the agent floated, and every path it asked for came back
// NoRouteFound for the rest of the session.
//
// What this test pins, in four phases:
//
//   A - THE FIX. A settled agent displaced 120cm straight up (inside its 192cm
//     body height, so it reads as drift and not as deliberate elevation) is
//     returned to the surface by the lease, and the correction is Z-ONLY.
//     Without the lease the agent hangs at +120 forever, so the phase cannot
//     pass vacuously - and the lift itself is confirmed observed before any
//     re-ground is accepted, so a SetTransform that silently did nothing cannot
//     be mistaken for an instant recovery.
//
//   B - ANTI-CREEP. Over that same window the three untouched agents hold their
//     formation. This is the half of the contract that makes the lease safe to
//     run at all: ProjectPointToNavigation answers with the nearest poly point,
//     which near a navmesh edge carries a LATERAL nudge, and folding that XY
//     into a resting agent every lease would shove a settled pile a little
//     every second - re-creating exactly the formation creep the push-apart
//     slop exists to end. 8cm is Crowd_BunchUp_SettlesAtSharedGoal's quiet-
//     window limit, restated here for the same reason.
//
//   C - THE FIELD SYMPTOM. The re-grounded agent can path again. The regression
//     QA reported was not "the NPC looks high up", it was permanent
//     NoRouteFound: a floating agent's start projection misses the mesh, so
//     every subsequent move dies before it begins. Asserting the Z came back
//     without asserting the agent can move again would pin the cosmetic half.
//
//   D - THE EXTENT CONTRACT. A DELIBERATELY elevated agent - lifted 4x its body
//     height - is NOT dragged back down. The recovery extent stays +/-Height on
//     purpose: an agent that far off the mesh is REPORTED through
//     Get_IsOffNavmesh, never silently teleported. Widening the vertical
//     recovery to "fix" a floating agent would break every legitimate elevation
//     in a project at once, so the ceiling is pinned from both sides.
//
// WAITS ARE CONDITION-BOUNDED, NOT CLOCK-BOUNDED. The lease interval is read
// from the project setting rather than hardcoded, but only to prove the feature
// is ENABLED for this run (a disabled lease makes every phase below vacuous, so
// it fails loudly instead of hanging). The waits themselves poll named
// conditions: how many passes a lease verify needs is a property of processor
// ordering and frame rate, not of elapsed seconds.
//
// Separations and drifts are measured in 2D on purpose: the bodies are
// cylinders, and this test deliberately moves agents in Z - a 3D metric would
// report the lift itself as lateral drift.
//============================================================================

class UCk_AutoTest_Crowd_Grounding_StationaryAgentReGrounds : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 45.0f;

    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private TArray<FCk_Handle_Transform> _AgentTransforms;
    private TArray<FVector> _SpawnPositions;

    // Positions latched the moment the drift agent is lifted - the baseline both
    // the Z-only pin (Phase A) and the anti-creep pin (Phase B) measure against.
    private TArray<FVector> _LiftBaselinePos;

    private FVector _ProbeStart = FVector::ZeroVector;
    private bool _NavProbeReady = false;
    private float _VerifyIntervalSec = 0.0;
    private FCk_Handle _InitialSettleOwner;
    private FCk_Handle_Timer _InitialSettleTimer;
    private bool _InitialSettleComplete = false;
    private float _InitialSettleElapsedSec = 0.0;
    private float _InitialSettleQuietSinceSec = -1.0;
    private TArray<FVector> _InitialSettleQuietBaseline;

    private int32 _DriftIndex = -1;
    private int32 _ElevatedIndex = -1;

    private FVector _DriftPreLiftPos = FVector::ZeroVector;
    private bool _DriftLiftObserved = false;

    private float _ElevatedPreLiftZ = 0.0;
    private bool _ElevatedStopCompleted = false;
    private bool _ElevatedStopSucceeded = false;
    private int32 _ElevatedPathFailedCount = 0;
    private ECk_Nav_PathFailReason _ElevatedPathFailReason = ECk_Nav_PathFailReason::None;
    private int32 _ElevatedDispatchRevision = 0;
    private int32 _ElevatedExpectedRequestRevision = 0;
    private ECk_NavSurface_Provider _ElevatedProvider = ECk_NavSurface_Provider::Recast;

    private FVector _PostRecoveryGoal = FVector::ZeroVector;
    private bool _PostRecoveryReached = false;
    private bool _PostRecoveryFailed = false;
    private FString _PostRecoveryFailReason;

    private const int32 AgentCount = 4;
    private const float RingRadius = 500.0;
    private const FVector Centre = FVector(0.0, 0.0, 100.0);

    private const float AgentRadius = 42.0f;
    private const float AgentHeight = 192.0f;

    // Inside the 192cm body height, so the projection extent still finds the mesh
    // and this reads as DRIFT - the case the lease exists to reconcile.
    private const float DriftLiftCm = 120.0;

    // 4x body height: past both the ordinary projection extent AND the recovery
    // extent, so this reads as DELIBERATE elevation and must be reported rather
    // than corrected.
    private const float DeliberateLiftCm = 768.0;
    private const float DeliberateHoldFloorCm = 700.0;

    // The lift must be SEEN before a re-ground is believed. Half the lift is well
    // clear of any settling noise and well under the lift itself.
    private const float LiftObservedFloorCm = 60.0;

    // The projection lands the feet on the poly surface, which is where the agent
    // already was, so the round trip should return within a fraction of a cm.
    private const float ReGroundToleranceCm = 5.0;

    // THE Z-ONLY PIN. A folded projection nudge near a navmesh edge is tens of cm;
    // push-apart's residual at rest is bounded by _PushApartSlopCm (0.05cm) and in
    // practice is zero once a formation settles. 2cm separates those two
    // populations rather than splitting either one.
    private const float MaxLateralDriftCm = 2.0;

    // Crowd_BunchUp_SettlesAtSharedGoal's quiet-window limit, restated.
    private const float MaxQuietDriftCm = 8.0;

    private const float SettledSpeedCm = 5.0;
    private const float GoalArrivalToleranceCm = 110.0;

    // The named setup and post-recovery waits retain their bounded sequencer budgets. The initial
    // crowded settlement is the exception: its own elapsed-time deadline makes it independent of
    // editor FPS, while the sequencer waits only for that explicit result.
    private const int32 SettleBudgetPolls = 1200;
    private const int32 LeaseBudgetPolls = 600;
    private const float InitialSettleSampleIntervalSec = 0.1;
    private const float InitialSettleDeadlineSec = 15.0;
    // A terminal crowd can still be coasting when its reported speed first falls
    // under SettledSpeedCm. Require a complete lease interval of measurable
    // planar quiet before latching the anti-creep baseline; otherwise residual
    // arrival motion is misreported as an idle-grounding correction.
    private const float InitialSettleQuietDriftCm = 1.0;
    // This only prevents the sequencer's frame counter racing the elapsed-time deadline above.
    private const int32 InitialSettleSequencerPolls = 2147483647;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step(           "confirm the grounding lease is enabled for this run",
                            n"Step_AssertLeaseEnabled");
        Add_Step(           "kick the navmesh bake and probe a route the agents will walk",
                            n"Step_ProbeNavmesh");
        Add_Step_WaitUntil( "the navmesh answers a real path query",
                            n"Check_NavReady", SettleBudgetPolls);
        Add_Step(           "spawn 4 agents on a ring, every one sent to the SAME point",
                            n"Step_SpawnAgents");
        Add_Step_WaitUntil( "every agent's path resolves Ready",
                            n"Check_AllPathsReady", SettleBudgetPolls);
        Add_Step(           "start the elapsed-time initial settling window",
                            n"Step_BeginInitialSettleTimer");
        Add_Step_WaitUntil( "every agent is terminal and has come to rest",
                            n"Check_InitialSettleComplete", InitialSettleSequencerPolls);
        Add_Step(           "latch the formation and lift one settled agent 120cm",
                            n"Step_LiftDriftAgent");
        Add_Step_WaitUntil( "the lease returns the lifted agent to the surface, Z-only",
                            n"Check_DriftAgentReGrounded", LeaseBudgetPolls);
        Add_Step(           "the untouched agents held their formation throughout",
                            n"Step_AssertNoCreep");
        Add_Step(           "send the re-grounded agent to a point it walked from",
                            n"Step_MoveAfterReGround");
        Add_Step_WaitUntil( "that move resolves successfully instead of NoRouteFound",
                            n"Check_PostRecoveryMoveResolved", SettleBudgetPolls);
        Add_Step(           "drain the elevated agent's prior navigation episode",
                            n"Step_BeginElevatedAgentQuiesce");
        Add_Step_WaitUntil( "that Stop has cleared the prior nav result",
                            n"Check_ElevatedAgentQuiescent", SettleBudgetPolls);
        Add_Step(           "lift the drained agent 4x its body height",
                            n"Step_LiftElevatedAgent");
        Add_Step_WaitUntil( "the deliberately elevated agent is REPORTED off-navmesh",
                            n"Check_ElevatedReportedOffNavmesh", LeaseBudgetPolls);
        Add_Step(           "request a route only after its elevated transform is observed",
                            n"Step_RequestElevatedTerminal");
        Add_Step_WaitUntil( "its expected off-mesh start-projection terminal is observed",
                            n"Check_ElevatedTerminalFailureObserved", LeaseBudgetPolls);
        Add_Step(           "and was reported rather than dragged back down",
                            n"Step_AssertDeliberateElevationHeld");
        Run_Steps(InHandle);
    }

    // ---- Preconditions ------------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertLeaseEnabled(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _VerifyIntervalSec = utils_crowd_settings::Get_GroundingVerifyIntervalSeconds();

        if (_VerifyIntervalSec <= 0.0f)
        {
            FinishFailure(f"the grounding lease is DISABLED for this run (_GroundingVerifyIntervalSeconds = {_VerifyIntervalSec}). Every phase below measures a stationary agent being reconciled against the navmesh, so with the lease off this test would hang rather than report - failing here instead, naming the setting.");
            return;
        }

        ck::crowd::Log(f"[GROUNDING] lease enabled at {_VerifyIntervalSec}s, dead-band {utils_crowd_settings::Get_GroundingVerifyMinCorrectionCm()}cm");
    }

    UFUNCTION()
    private void Step_ProbeNavmesh(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;

        // Probe from a real ring point THROUGH the centre, so the readiness probe
        // travels the same route every agent will. A projection-only probe can
        // select different nav data and false-positive.
        _ProbeStart = Centre + FVector(RingRadius, 0.0, 0.0);
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, _ProbeStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the surface: AutoTests_CkTests_Level has the fixture but the bake is lazy.
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }

    // Retried each poll until the surface answers Success: the rebuild kicked in
    // Step_ProbeNavmesh is async, so the first few polls can legitimately read Unbuilt while the
    // bake finishes.
    UFUNCTION()
    private void Check_NavReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        if (IsFinished()) { return; }

        auto Res = OutResult;

        if (_NavProbeReady)
        {
            Res.Set(true);
            return;
        }

        auto ProbeQuery = FCk_NavSurface_PathQuery(_ProbeStart, Centre);
        const auto Result = utils_nav_surface::Try_FindPathSync(ProbeQuery);

        if (Result.Get_Status() == ECk_NavSurface_QueryStatus::Unbuilt) { return; }

        if (Result.Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            FinishFailure(f"navigation readiness probe returned status {Result.Get_Status()} instead of Success");
            return;
        }

        if (Result.Get_Waypoints().Num() < 1)
        {
            FinishFailure("navigation readiness probe returned no waypoints");
            return;
        }

        _NavProbeReady = true;
        Res.Set(true);
    }

    UFUNCTION()
    private void Step_BeginInitialSettleTimer(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _InitialSettleOwner = InHandle;
        _InitialSettleComplete = false;
        _InitialSettleElapsedSec = 0.0;
        _InitialSettleQuietSinceSec = -1.0;
        _InitialSettleQuietBaseline.Empty();

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(InitialSettleSampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        _InitialSettleTimer = utils_timer::Add(InHandle, TimerParams);
        _InitialSettleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnInitialSettleSample"));
    }

    UFUNCTION()
    private void OnInitialSettleSample(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished())
        {
            Pause_InitialSettleTimer();
            return;
        }

        _InitialSettleElapsedSec += InitialSettleSampleIntervalSec;
        auto Result = utils_shared_bool::Make(false);
        Check_AllSettled(_InitialSettleOwner, Result, FInstancedStruct());
        if (IsFinished())
        {
            Pause_InitialSettleTimer();
            return;
        }

        if (Result.Get())
        {
            Pause_InitialSettleTimer();
            _InitialSettleComplete = true;
            return;
        }

        if (_InitialSettleElapsedSec >= InitialSettleDeadlineSec)
        {
            Pause_InitialSettleTimer();
            FinishFailure(f"the four-agent formation never became terminal and at rest within {InitialSettleDeadlineSec}s after every path resolved Ready. The initial grounding lift requires a genuinely resting crowd, so a walking or coasting formation cannot proceed.");
        }
    }

    UFUNCTION()
    private void Check_InitialSettleComplete(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (IsFinished())
        {
            Pause_InitialSettleTimer();
            return;
        }

        if (_InitialSettleComplete)
        {
            Pause_InitialSettleTimer();
            Res.Set(true);
        }
    }

    private void Pause_InitialSettleTimer()
    {
        if (ck::IsValid(_InitialSettleTimer))
        { utils_timer::Request_Pause(_InitialSettleTimer); }
    }

    // ---- Setup --------------------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SpawnAgents(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;

        const auto AngleStep = (2.0 * Math::PI) / float(AgentCount);
        for (int32 i = 0; i < AgentCount; ++i)
        {
            const auto Angle = AngleStep * float(i);
            const auto Spawn = Centre + FVector(RingRadius * Math::Cos(Angle), RingRadius * Math::Sin(Angle), 0.0);
            DoSpawnAgent(LocalHandle, Spawn, FName(f"GroundingAgent_{i}"));
        }
    }

    private void DoSpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(AgentRadius, AgentHeight);

        // A FRESH child entity per agent. utils_crowd_agent::Add composes onto the handle it is
        // given and permits one agent per entity, so a shared owner leaves a crowd of exactly one.
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        const auto LookDir = Centre - InSpawn;
        const auto Rot = FVector(LookDir.X, LookDir.Y, 0.0).GetSafeNormal().Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(Rot, InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        // Every agent gets the IDENTICAL target: the shape that produces a packed, settled
        // formation, which is the only regime in which the lease is the SOLE writer of an
        // agent's Z. A lone walking agent re-grounds on displacement and proves nothing.
        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(Centre));

        _Agents.Add(Agent);
        _AgentTransforms.Add(AgentTransform);
        _SpawnPositions.Add(InSpawn);
    }

    UFUNCTION()
    private void Check_AllPathsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

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

        Res.Set(true);
    }

    UFUNCTION()
    private void Check_AllSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (DoValidateAgents() == false) { return; }

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            auto Agent = _Agents[i];

            if (utils_crowd_agent::Get_IsGoalFailedHold(Agent))
            {
                FinishFailure(f"agent {i} entered the terminal goal-FAILED hold while the formation was still assembling. This test needs a RESTING crowd - a failed agent is Idle for the wrong reason and its Z is no longer the lease's to own.");
                return;
            }

            const auto IsTerminal = utils_crowd_agent::Get_HasReachedActiveGoal(Agent)
                || utils_crowd_agent::Get_IsGoalBlocked(Agent);
            if (IsTerminal == false) { return; }

            // Quiescence is part of the settle, not just terminality: the GoalBlocked transition
            // does not zero the velocity - it goes Idle and lets AccelClamp ramp down - so an agent
            // latched the instant it blocks is still coasting, and the lift phases below would
            // measure its own braking as drift.
            if (DoGet_Speed(Agent) > SettledSpeedCm) { return; }
        }

        // The expected lease cadence is part of this precondition. The test is
        // about an idle verify being the sole transform writer, which is not
        // true until arrival residuals have remained quiet across one full
        // verify period.
        if (_InitialSettleQuietBaseline.Num() != _Agents.Num())
        {
            _InitialSettleQuietBaseline.Empty();
            for (int32 i = 0; i < _Agents.Num(); ++i)
            { _InitialSettleQuietBaseline.Add(DoGet_Position(_Agents[i])); }
            _InitialSettleQuietSinceSec = _InitialSettleElapsedSec;
            return;
        }

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (DoGet_Dist2D(DoGet_Position(_Agents[i]), _InitialSettleQuietBaseline[i])
                > InitialSettleQuietDriftCm)
            {
                _InitialSettleQuietBaseline.Empty();
                _InitialSettleQuietSinceSec = -1.0;
                return;
            }
        }

        Res.Set(_InitialSettleElapsedSec - _InitialSettleQuietSinceSec >= _VerifyIntervalSec);
    }

    // ---- Phase A + B: the lift, the Z-only re-ground, and the formation that must not move ----------

    UFUNCTION()
    private void Step_LiftDriftAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _DriftIndex = DoPick_DriftAgent();
        if (_DriftIndex < 0)
        {
            FinishFailure("no settled agent to displace - the formation assembled but nothing in it is holding or arrived");
            return;
        }

        _LiftBaselinePos.Empty();
        for (int32 i = 0; i < _Agents.Num(); ++i)
        { _LiftBaselinePos.Add(DoGet_Position(_Agents[i])); }

        _DriftPreLiftPos = _LiftBaselinePos[_DriftIndex];
        _DriftLiftObserved = false;

        DoLift(_DriftIndex, DriftLiftCm);

        ck::crowd::Log(f"[GROUNDING] lifted agent {_DriftIndex} by {DriftLiftCm}cm from {_DriftPreLiftPos} - the lease must drop it back, Z-only");
    }

    UFUNCTION()
    private void Check_DriftAgentReGrounded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (DoValidateAgents() == false) { return; }

        // ANTI-CREEP, sampled every poll rather than once at the end: a formation that drifts and
        // drifts back would pass a final-position check while still shuffling all the way through.
        if (DoCheck_UntouchedAgentsHeldFormation("during the lease recovery window") == false) { return; }

        const auto Pos = DoGet_Position(_Agents[_DriftIndex]);
        const auto RisenCm = float(Pos.Z - _DriftPreLiftPos.Z);

        // POSITIVE CONTROL. A SetTransform that silently did nothing leaves the agent already at its
        // pre-lift Z, which would satisfy the re-ground test on the very first poll and pass this
        // whole phase without the lease ever running. The lift has to be SEEN first.
        if (_DriftLiftObserved == false)
        {
            if (RisenCm >= LiftObservedFloorCm) { _DriftLiftObserved = true; }
            return;
        }

        const auto LateralDrift = DoGet_Dist2D(Pos, _DriftPreLiftPos);
        if (LateralDrift > MaxLateralDriftCm)
        {
            FinishFailure(f"LATERAL CREEP: agent {_DriftIndex} moved {LateralDrift}cm in XY while the lease reconciled its Z (limit {MaxLateralDriftCm}cm). The idle verify must correct Z ONLY - ProjectPointToNavigation answers with the nearest poly point, and folding its lateral nudge into a resting agent shoves a settled formation a little every second.");
            return;
        }

        Res.Set(Math::Abs(RisenCm) <= ReGroundToleranceCm);
    }

    UFUNCTION()
    private void Step_AssertNoCreep(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Pos = DoGet_Position(_Agents[_DriftIndex]);
        const auto ResidualZ = Math::Abs(float(Pos.Z - _DriftPreLiftPos.Z));
        const auto LateralDrift = DoGet_Dist2D(Pos, _DriftPreLiftPos);

        Assert_True(ResidualZ <= ReGroundToleranceCm,
            f"agent {_DriftIndex} settled {ResidualZ}cm off the height it was lifted from (tolerance {ReGroundToleranceCm}cm)");

        Assert_True(LateralDrift <= MaxLateralDriftCm,
            f"agent {_DriftIndex} ended the recovery {LateralDrift}cm away in XY (limit {MaxLateralDriftCm}cm) - the idle verify is folding the projection's lateral nudge into the correction");

        DoCheck_UntouchedAgentsHeldFormation("by the end of the lease recovery window");

        ck::crowd::Log(f"[GROUNDING] agent {_DriftIndex} re-grounded: residualZ={ResidualZ}cm lateral={LateralDrift}cm");
    }

    // ---- Phase C: the field symptom - a re-grounded agent can path again ----------------------------

    UFUNCTION()
    private void Step_MoveAfterReGround(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Agent = _Agents[_DriftIndex];

        // Its OWN spawn point: provably reachable, because the agent walked out of it to get here.
        // A fresh coordinate would risk failing for a fixture reason and reporting as a grounding
        // regression.
        _PostRecoveryGoal = _SpawnPositions[_DriftIndex];

        // Bound HERE rather than at spawn, and future-only: the agent has already completed a move
        // episode (reached or blocked) and a replayed payload from that one would resolve this
        // phase without a second path ever being planned.
        utils_crowd_agent::BindTo_OnGoalReached(Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnPostRecoveryGoalReached"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnPostRecoveryGoalFailed"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(_PostRecoveryGoal));
    }

    UFUNCTION()
    private void OnPostRecoveryGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        _PostRecoveryReached = true;
    }

    UFUNCTION()
    private void OnPostRecoveryGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        _PostRecoveryFailed = true;
        _PostRecoveryFailReason = f"{InInfo.Get_Reason()} / nav={InInfo.Get_NavFailReason()} / noCrowdFreeRoute={InInfo.Get_NoCrowdFreeRouteExisted()}";
    }

    UFUNCTION()
    private void Check_PostRecoveryMoveResolved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (DoValidateAgents() == false) { return; }

        auto Agent = _Agents[_DriftIndex];

        if (_PostRecoveryFailed)
        {
            FinishFailure(f"NO ROUTE AFTER RE-GROUNDING: the agent's move failed ({_PostRecoveryFailReason}) even though its target is the point it originally walked out of. This is the field symptom the lease exists to end - a floating agent's start projection misses the mesh, so every path it asks for comes back NoRouteFound for the rest of the session. The Z coming back is only half the fix.");
            return;
        }

        // Deliberately NO raw Get_PathStatus poll here: the shared nav slot transiently reads
        // Failed while the framework's own ladders are mid-retry - the strict planning phase
        // legitimately fails against the settled pile's confirmed markup discs and re-dispatches
        // once with the permissive filter (measured: this poll caught that transient and failed
        // the test while the permissive plan was still in flight). OnGoalFailed is the episode's
        // single terminal failure channel and fires exactly once, so it is the only failure
        // evidence this phase may act on.
        if (_PostRecoveryReached == false) { return; }

        const auto Dist = DoGet_Dist2D(DoGet_Position(Agent), _PostRecoveryGoal);
        Assert_True(Dist <= GoalArrivalToleranceCm,
            f"the re-grounded agent reported OnGoalReached {Dist}cm from its target (arrival contract {GoalArrivalToleranceCm}cm)");

        Res.Set(true);
    }

    // ---- Phase D: a deliberate elevation is reported, never corrected -------------------------------

    UFUNCTION()
    private void Step_BeginElevatedAgentQuiesce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ElevatedIndex = DoPick_ElevatedAgent();
        if (_ElevatedIndex < 0)
        {
            FinishFailure("no second settled agent to elevate - the rest of the formation is no longer at rest, so a Z hold could not be told from ordinary walking");
            return;
        }

        auto Agent = _Agents[_ElevatedIndex];
        _ElevatedStopCompleted = false;
        _ElevatedStopSucceeded = false;
        utils_crowd_agent::Request_Stop(Agent,
            FCk_Delegate_Request_OnCompleted(this, n"OnElevatedStopCompleted"));
    }

    UFUNCTION()
    private void OnElevatedStopCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        if (_ElevatedIndex < 0 || InRequestOwner != FCk_Handle(_Agents[_ElevatedIndex]))
        {
            FinishFailure("the elevated-agent Stop completed for an unexpected request owner");
            return;
        }

        _ElevatedStopSucceeded = InResult == ECk_Request_OperationResult::Succeeded;
        _ElevatedStopCompleted = true;
    }

    UFUNCTION()
    private void Check_ElevatedAgentQuiescent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        if (_ElevatedIndex < 0 || DoValidateAgents() == false) { return; }
        if (_ElevatedStopCompleted == false) { return; }
        if (_ElevatedStopSucceeded == false)
        {
            FinishFailure("the elevated-agent Stop did not complete successfully, so its prior navigation episode was not proven drained");
            return;
        }

        auto Agent = _Agents[_ElevatedIndex];
        FCk_Handle AgentEntity = Agent;
        if (utils_nav::Get_PathStatus(AgentEntity) != ECk_Nav_PathStatus::None ||
            utils_crowd_agent::Get_HasReachedActiveGoal(Agent) ||
            utils_crowd_agent::Get_IsGoalBlocked(Agent))
        { return; }

        Res.Set(true);
    }

    UFUNCTION()
    private void Step_LiftElevatedAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (_ElevatedIndex < 0)
        {
            FinishFailure("no quiesced agent remains for the deliberate elevation");
            return;
        }

        auto Agent = _Agents[_ElevatedIndex];
        FCk_Handle AgentEntity = Agent;
        _ElevatedPathFailedCount = 0;
        _ElevatedPathFailReason = ECk_Nav_PathFailReason::None;

        // This lift deliberately puts the agent beyond the projection extent. The resulting
        // start-projection failure is the expected terminal proof that the agent was held, not
        // snapped down; bind before the lift and wait for it so its warning cannot leak after the
        // test runner has completed.
        utils_nav::BindTo_OnPathFailed(AgentEntity,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnElevatedPathFailed"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        _ElevatedPreLiftZ = float(DoGet_Position(Agent).Z);
        DoLift(_ElevatedIndex, DeliberateLiftCm);
        ck::crowd::Log(f"[GROUNDING] elevated agent {_ElevatedIndex} by {DeliberateLiftCm}cm (4x body height) from Z={_ElevatedPreLiftZ} - the lease must REPORT this, not correct it");
    }

    UFUNCTION()
    private void Check_ElevatedReportedOffNavmesh(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (DoValidateAgents() == false) { return; }

        auto Agent = _Agents[_ElevatedIndex];
        const auto RisenCm = float(DoGet_Position(Agent).Z - _ElevatedPreLiftZ);

        // Reported BEFORE waiting is over is the whole point: this flag is the positive evidence
        // that the lease actually ran a verify on this agent, so the Z-hold assertion that follows
        // is not merely "nothing happened yet".
        if (RisenCm < DeliberateHoldFloorCm)
        {
            FinishFailure(f"RECOVERY EXTENT OVERREACH: the deliberately elevated agent has come back down to {RisenCm}cm above where it started (floor {DeliberateHoldFloorCm}cm). The recovery extent is +/-Height on purpose - an agent further off the mesh than its own body height is REPORTED through Get_IsOffNavmesh, never silently teleported, or every legitimate elevation in a project breaks at once.");
            return;
        }

        Res.Set(utils_crowd_agent::Get_IsOffNavmesh(Agent));
    }

    UFUNCTION()
    private void Step_RequestElevatedTerminal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (_ElevatedIndex < 0 || DoValidateAgents() == false) { return; }

        auto Agent = _Agents[_ElevatedIndex];

        // The preceding wait proves Grounding has observed the raised transform before this request
        // is accepted. Re-use this agent's spawn point: it is a known reachable XY goal 500cm from
        // the Centre goal, so MoveTo cannot take its 20cm same-goal no-op. The elevated START must
        // therefore produce the one expected StartProjectFailed terminal.
        // The crowd request processor advances its per-agent navigation revision exactly once
        // when it begins this new episode. Capture the visible pre-dispatch value here so the
        // wait below can distinguish this request from a stale slot left by the preceding Stop.
        FCk_Handle AgentEntity = Agent;
        _ElevatedDispatchRevision = utils_nav::Get_PathResult(AgentEntity).Get_RequestRevision();
        _ElevatedExpectedRequestRevision = _ElevatedDispatchRevision + 1;
        _ElevatedProvider = utils_nav_surface::Get_Provider();

        utils_crowd_agent::Request_MoveTo(Agent,
            FCk_Request_CrowdAgent_MoveTo(_SpawnPositions[_ElevatedIndex]));
    }

    UFUNCTION()
    private void OnElevatedPathFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        _ElevatedPathFailedCount += 1;
        const auto Result = utils_nav::Get_PathResult(InHandle);
        _ElevatedPathFailReason = Result.Get_Diagnostics().Get_LastFailReason();
        ck::crowd::Log(f"[GROUNDING] elevated path-failed #{_ElevatedPathFailedCount}: rev={Result.Get_RequestRevision()} status={Result.Get_Status()} reason={_ElevatedPathFailReason}");
    }

    UFUNCTION()
    private void Check_ElevatedTerminalFailureObserved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (_ElevatedIndex < 0 || DoValidateAgents() == false) { return; }

        FCk_Handle AgentEntity = _Agents[_ElevatedIndex];
        const auto Result = utils_nav::Get_PathResult(AgentEntity);
        const auto Status = Result.Get_Status();
        const auto Revision = Result.Get_RequestRevision();
        const auto PendingSinceSeconds = Result.Get_PendingSinceSeconds();
        const auto FailReason = Result.Get_Diagnostics().Get_LastFailReason();
        const auto Snapshot = f"status={Status}, revision={Revision}, expectedRevision={_ElevatedExpectedRequestRevision}, pendingSince={PendingSinceSeconds}, reason={FailReason}";

        // The test has already proven this body is outside Grounding's recovery extent. A route
        // reaching Ready/Partial means Recast accepted a start the test expected to be rejected;
        // None means the MoveTo never established its episode. Neither can become the required
        // off-mesh terminal by waiting longer.
        if (Status == ECk_Nav_PathStatus::Ready || Status == ECk_Nav_PathStatus::Partial ||
            Status == ECk_Nav_PathStatus::None)
        {
            FinishFailure(f"the elevated MoveTo entered an impossible state before its off-mesh terminal: {Snapshot}");
            return;
        }

        if (Revision != _ElevatedExpectedRequestRevision)
        {
            FinishFailure(f"the elevated MoveTo slot was replaced or never advanced to its expected episode revision: {Snapshot}");
            return;
        }

        if (Status == ECk_Nav_PathStatus::Pending && PendingSinceSeconds <= 0.0)
        {
            FinishFailure(f"the elevated MoveTo is Pending without the timestamp required by the bounded deferred/watchdog paths: {Snapshot}");
            return;
        }

        // Recast deliberately parks an unprojectable start and measures its deferral and crowd
        // watchdog horizons from FPlatformTime wall time. A headless AutoTest can advance 600
        // sequencer polls in less than either real-time horizon (Gate100: 3.76 wall seconds), so
        // waiting for its later terminal here would turn a valid parked episode into a false
        // compatibility failure. The direct deferred-queue and pending-watchdog tests own those
        // wall-clock terminal contracts. This test owns the grounding contract: this exact,
        // current-revision Pending slot proves Recast observed the deliberately off-mesh start
        // without silently re-grounding it.
        if (_ElevatedProvider == ECk_NavSurface_Provider::Recast)
        {
            Res.Set(Status == ECk_Nav_PathStatus::Pending);
            return;
        }

        // GroundNav rejects this start synchronously. Observe the shared result
        // as well as the signal so its provider-owned terminal is explicit.
        if (_ElevatedPathFailedCount == 0)
        {
            if (Status == ECk_Nav_PathStatus::Failed)
            {
                _ElevatedPathFailedCount = 1;
                _ElevatedPathFailReason = FailReason;
                ck::crowd::Log(f"[GROUNDING] elevated path terminal from shared result: {Snapshot}");
            }
        }

        if (_ElevatedPathFailedCount > 1)
        {
            FinishFailure(f"the deliberately elevated agent emitted {_ElevatedPathFailedCount} path-failed signals; its expected off-mesh terminal must be single-shot");
            return;
        }

        if (_ElevatedPathFailedCount == 0) { return; }

        const auto IsExpectedOffMeshTerminal =
            _ElevatedPathFailReason == ECk_Nav_PathFailReason::StartProjectFailed ||
            _ElevatedPathFailReason == ECk_Nav_PathFailReason::NoNavData ||
            _ElevatedPathFailReason == ECk_Nav_PathFailReason::PendingTimeout;
        if (!IsExpectedOffMeshTerminal)
        {
            FinishFailure(f"the deliberately elevated agent failed with {_ElevatedPathFailReason}, not an off-mesh start terminal. Beyond the recovery extent its feet must remain off-mesh, so Recast may report its bounded deferred-start terminal (NoNavData or PendingTimeout) while GroundNav reports StartProjectFailed, but no route verdict is valid.");
            return;
        }

        Res.Set(true);
    }

    UFUNCTION()
    private void Step_AssertDeliberateElevationHeld(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Agent = _Agents[_ElevatedIndex];
        const auto RisenCm = float(DoGet_Position(Agent).Z - _ElevatedPreLiftZ);

        Assert_True(RisenCm >= DeliberateHoldFloorCm,
            f"the deliberately elevated agent is only {RisenCm}cm above where it started (floor {DeliberateHoldFloorCm}cm) - the vertical recovery extent has been widened past +/-Height");

        Assert_True(utils_crowd_agent::Get_IsOffNavmesh(Agent),
            f"the elevated agent is {RisenCm}cm off the mesh but Get_IsOffNavmesh reports false - an agent stranded beyond recovery must be self-reporting, or the only way to notice is the NoRouteFound it causes later");

        Assert_True(utils_crowd_agent::Get_SecondsOffNavmesh(Agent) >= 0.0f,
            "the off-navmesh dwell time must be a real accumulated duration, not a negative sentinel");

        // The drift agent went the other way and must still read as grounded, so a blanket
        // "everything is off the mesh" cannot satisfy the assertion above.
        Assert_False(utils_crowd_agent::Get_IsOffNavmesh(_Agents[_DriftIndex]),
            f"agent {_DriftIndex} re-grounded onto the surface yet still reports itself off-navmesh - the flag is latched rather than cleared by a successful verify");

        ck::crowd::Log(f"[GROUNDING] agent {_ElevatedIndex} held at +{RisenCm}cm and reported off-navmesh for {utils_crowd_agent::Get_SecondsOffNavmesh(Agent)}s");
    }

    // ---- Helpers ------------------------------------------------------------------------------------

    // Prefer an agent that is HOLDING rather than the one standing on the goal: the occupant is what
    // every other agent's block is anchored on, and displacing it risks the pack resuming mid-phase,
    // which would fail the anti-creep pin for a reason that has nothing to do with grounding.
    private int32 DoPick_DriftAgent()
    {
        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (utils_crowd_agent::Get_IsGoalBlocked(_Agents[i])) { return i; }
        }

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (utils_crowd_agent::Get_HasReachedActiveGoal(_Agents[i])) { return i; }
        }

        return -1;
    }

    // The arrived agent for this one: nothing is waiting on it and nothing will move it, so a Z hold
    // measured on it cannot be confused with an agent that simply has not started walking yet.
    private int32 DoPick_ElevatedAgent()
    {
        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (i == _DriftIndex) { continue; }
            if (utils_crowd_agent::Get_HasReachedActiveGoal(_Agents[i])) { return i; }
        }

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (i == _DriftIndex) { continue; }
            if (utils_crowd_agent::Get_IsGoalBlocked(_Agents[i])) { return i; }
        }

        return -1;
    }

    private void DoLift(int32 InIndex, float InLiftCm)
    {
        auto AgentTransform = _AgentTransforms[InIndex];
        const auto Current = utils_transform::Get_EntityCurrentTransform(AgentTransform);
        const auto Lifted = Current.GetLocation() + FVector(0.0, 0.0, InLiftCm);

        // The agent's prior episode was explicitly drained before this phase. The displacement itself
        // remains absolute: it has to look like something the world did TO the stationary body, which
        // is how every real source of this defect (a spawn-frame fall, a long-frame vertical overshoot,
        // a ramp edge) arrives.
        utils_transform::Request_SetTransform(AgentTransform,
            FCk_Request_Transform_SetTransform(
                FTransform(Current.GetRotation(), Lifted, Current.GetScale3D())));
    }

    private bool DoCheck_UntouchedAgentsHeldFormation(const FString& InWhen)
    {
        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (i == _DriftIndex) { continue; }

            const auto Drift = DoGet_Dist2D(DoGet_Position(_Agents[i]), _LiftBaselinePos[i]);
            if (Drift > MaxQuietDriftCm)
            {
                FinishFailure(f"FORMATION CREEP: untouched agent {i} moved {Drift}cm from where it settled (limit {MaxQuietDriftCm}cm) {InWhen}. The idle verify runs on every resting agent every lease - if it folds the projection's lateral nudge into the correction, a settled pile creeps a little every second, which is exactly the drift the push-apart slop was introduced to end.");
                return false;
            }
        }

        return true;
    }

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

    // Planar distance: this test deliberately moves agents in Z, so a 3D metric would report the
    // lift itself as lateral drift and the Z-only pin would assert nothing.
    private float DoGet_Dist2D(FVector InA, FVector InB)
    {
        return float(FVector(InA.X - InB.X, InA.Y - InB.Y, 0.0).Size());
    }
}

class ACk_AutoTest_Crowd_Grounding_StationaryAgentReGrounds_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Grounding_StationaryAgentReGrounds;
    default _TimeoutSeconds = 45.0f;

    // The final phase deliberately elevates one settled agent beyond the projection extent and
    // waits for this exact terminal. The selected settled slot is intentionally not fixed, so the
    // expected warning names its invariant terminal rather than one incidental debug name.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("PathPending → Idle (path failed: Start Project Failed)");
        return Out;
    }
}
