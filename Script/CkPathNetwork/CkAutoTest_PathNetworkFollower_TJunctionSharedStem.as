// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: T-JUNCTION SHARED STEM (2-AGENT STANDOFF)
//============================================================================
//
// REPRO for the T JUNCTION gym standoff seen in PIE (2026-07-13): two agents
// share the stem, and instead of both splitting to their branches they lock up
// pushing against each other — one shoves the other, and the one being shoved
// wants to travel back to a point BEHIND the shover.
//
// Headless replica of the gym's T JUNCTION lane
// (CkPathNetworkGym_Following_PlayerController.as:129-133, :169-171), translated
// to Y=0 and kept inside the AutoTests level's baked navmesh (+/-500cm) per the
// follower-test geometry rule. Same shape, same agent defaults, same
// OffPathCostMultiplier(3.0), and — critically — the same CO-LOCATED SPAWN:
//
//        stem:    (450,0) ------------------ (-200,0)
//        branch:                    (-200,-200) .. (-200,+200)   [vertical]
//        both agents spawn at (480,0)   <-- SAME POINT
//        goal S:  (-250,-250)      goal N: (-250,+250)
//
// WHY CO-LOCATION MATTERS: at spawn RelativeOffset ~= 0, so the separation
// processor's SafeDistance clamp (0.01) makes the push DIRECTION degenerate to
// noise while the falloff is at full strength — the pair is blasted apart at up
// to MaxSpeed in an arbitrary bearing, including ALONG the stem. That is what can
// carry an agent past a waypoint it never came within _WaypointArrivalRadius(25cm)
// of.
//
//----------------------------------------------------------------------------
// WHAT THIS TEST DISCRIMINATES (it is a diagnostic, not just a pass/fail)
//
// Steering retires waypoints on PROXIMITY ALONE (CkCrowdAgent_Steering_Processor
// .cpp:68-72: Dist(Loc, Waypoint) <= 25cm) with no "have I passed its plane" test.
// Two rival explanations for the standoff:
//
//   H1 (un-retired waypoint): separation shoved the agent past a waypoint by more
//       than 25cm, so it was never retired. Path-follow now aims BACKWARD at a
//       point the agent has already physically passed — through the neighbour.
//   H2 (corridor routes backward): the compiled corridor legitimately contains a
//       backward leg at the junction (e.g. a side-keeping offset flip), so the
//       backward aim is CORRECT and the standoff is purely a separation vs
//       path-follow equilibrium.
//
// On stall this test logs, per agent: position, waypoint cursor, the FULL compiled
// corridor, and the distance from the agent to every waypoint. If the cursor points
// at a waypoint the agent has already walked past -> H1. If it points at a waypoint
// genuinely still ahead -> H2. One run separates them.
//
// The standoff is a stable equilibrium, which is why it never resolves: path-follow
// is damped by separation intensity (PathFollowDamp = max(0, 1 - SepMag/MaxSpeed),
// Steering:169), so the harder an agent presses toward a waypoint behind its
// neighbour, the more the ONLY force that could resolve the conflict is throttled.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_TJunctionSharedStem : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle _Self;
    private FCk_Handle_PathNetwork _Network;

    private FCk_Handle_CrowdAgent _AgentSouth;
    private FCk_Handle_CrowdAgent _AgentNorth;
    private FCk_Handle_PathNetworkFollower _FollowerSouth;
    private FCk_Handle_PathNetworkFollower _FollowerNorth;

    private bool _ReachedSouth = false;
    private bool _ReachedNorth = false;

    private float _ElapsedSec = 0.0;

    // Anti-vacuous-pass instrumentation. Two agents spawned at EXACTLY the same point have
    // RelativeOffset == 0, so the separation processor's Push = -OffsetPlanar/SafeDistance is the
    // ZERO vector and Force.IsNearlyZero() short-circuits to no force at all
    // (CkCrowdAgent_Separation_Processor.cpp:67-88). If their stem corridors are also identical, the
    // pair walks in perfect LOCKSTEP, never influences each other, and splits cleanly — a pass that
    // proves nothing. These track whether the agents ever actually interacted.
    private float _MinInterAgentDist = 999999.0;
    private float _MaxSepMag = 0.0;

    // Longest UNBROKEN stretch of agent-agent contact — the standoff's signature. See
    // MaxAllowedContactSec.
    private float _ContactRunSec = 0.0;
    private float _MaxContactRunSec = 0.0;

    private const FVector Spawn = FVector(480.0, 0.0, 0.0);
    private const FVector GoalS = FVector(-250.0, -250.0, 0.0);
    private const FVector GoalN = FVector(-250.0, 250.0, 0.0);

    private const float HalfWidth         = 90.0;
    private const float OffPathMultiplier = 3.0;

    private const float SampleIntervalSec = 0.25;

    // ARRIVAL IS A LIVENESS CHECK, NOT THE DEFECT DETECTOR. An earlier version of this test asserted
    // "both agents arrive within 8s" and was FLAKY: a healthy avoidance manoeuvre swerves around the
    // neighbour, which legitimately lengthens the walk, so a slow-but-correct run failed. Worse, the
    // obvious repair (raise the deadline) destroys the test: the original standoff self-resolved at
    // ~10.5s and both agents then limped home, so ANY deadline past that passes while the bug is
    // present. Time-to-arrival simply cannot separate "deadlocked" from "took the long way round".
    private const float WatchdogSec       = 20.0;

    // THE DEFECT DETECTOR. The standoff's signature is not slowness — it is two agents PINNED
    // TOGETHER, leaning on each other, unable to resolve. Combined radius is 42+42 = 84cm, so a gap
    // at or under ContactThresholdCm means they are touching. Measured:
    //   deadlocked (avoidance sampler blind while overlapping): ~9.5s of UNBROKEN contact
    //   healthy    (sampler steers out of the overlap):         ~1.0s, then they separate for good
    // 4s sits 4x above healthy and 2.4x below the defect. This assertion is insensitive to how long
    // the walk takes, which is exactly why it does not flake.
    private const float ContactThresholdCm    = 90.0;
    private const float MaxAllowedContactSec  = 4.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Self = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        TArray<FCk_PathNetwork_Ribbon> Ribbons;

        // Stem: runs -X along Y=0. Its endpoint lands on the branch ribbon's interior -> T-split.
        {
            TArray<FCk_PathNetwork_RibbonPoint> Points;
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(450.0, 0.0, 0.0), HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-200.0, 0.0, 0.0), HalfWidth));
            Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        }

        // Branch: the vertical bar of the T.
        {
            TArray<FCk_PathNetwork_RibbonPoint> Points;
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-200.0, -200.0, 0.0), HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-200.0, 200.0, 0.0), HalfWidth));
            Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        }

        _Network = utils_path_network::Add(LocalHandle, FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        WaitOneFrame(n"OnReadyToMove");
    }

    UFUNCTION()
    private void OnReadyToMove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_path_network::Get_IsBuilt(_Network),
            "network must be built before the MoveTo");

        // Both agents spawn at the SAME point. That is the gym's setup and the condition under test.
        _AgentSouth = SpawnAgent(n"TJunction_South");
        _FollowerSouth = AddFollower(_AgentSouth);

        _AgentNorth = SpawnAgent(n"TJunction_North");
        _FollowerNorth = AddFollower(_AgentNorth);

        utils_crowd_agent::BindTo_OnGoalReached(_AgentSouth,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnSouthReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(_AgentSouth,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnSouthFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalReached(_AgentNorth,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnNorthReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(_AgentNorth,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnNorthFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_AgentSouth, FCk_Request_CrowdAgent_MoveTo(GoalS));
        utils_crowd_agent::Request_MoveTo(_AgentNorth, FCk_Request_CrowdAgent_MoveTo(GoalN));

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(_Self, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnWatchdog"));
    }

    UFUNCTION()
    private void OnWatchdog(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ElapsedSec += SampleIntervalSec;

        Trace();

        // THE REGRESSION ASSERTION. Fires the moment the pair has been pinned together longer than
        // any healthy avoidance manoeuvre could explain — i.e. mid-standoff, not after it eventually
        // unsticks itself. Checked every sample so the failure lands while the agents are still in it.
        if (_MaxContactRunSec > MaxAllowedContactSec)
        {
            Describe("SOUTH", _AgentSouth, _FollowerSouth, GoalS, _ReachedSouth);
            Describe("NORTH", _AgentNorth, _FollowerNorth, GoalN, _ReachedNorth);

            FinishFailure(f"T-JUNCTION STANDOFF: the two agents stayed in unbroken contact (gap <= {ContactThresholdCm}cm) for {_MaxContactRunSec}s, which exceeds the {MaxAllowedContactSec}s a healthy avoidance manoeuvre can explain (~1s measured). They are leaning on each other instead of steering around each other. This is the avoidance sampler going blind while agents overlap: TimeToCollision returns a candidate-INDEPENDENT value once C < 0, so the ToI penalty is constant across the sample pattern, the collision term stops discriminating, and the sampler falls back to the path-follow anchor -- driving each agent straight into the neighbour it is supposed to avoid. Per-agent corridor + waypoint-cursor dump logged above under LogCkPathNetwork.");
            return;
        }

        if (_ReachedSouth && _ReachedNorth)
        {
            // GUARD: a lockstep walk-through is not a passing scenario, it is a scenario that never
            // ran. Two agents spawned at EXACTLY the same point have RelativeOffset == 0, which makes
            // the separation push degenerate to the zero vector — so a co-located pair could in
            // principle walk in perfect LOCKSTEP, never influence each other, and "pass" without ever
            // exercising the interaction under test.
            //
            // That case is caught by the CONTACT assertion above, not here: a lockstep pair sits at a
            // gap of ~0 for the entire run, which is unbroken contact, which trips MaxAllowedContactSec
            // within four seconds. This guard only has to establish that the two agents were ever
            // NEIGHBOURS at all (probe reach = 2 x ProbeRadius).
            //
            // Deliberately NOT asserting that the separation force ever fired. That assertion was here,
            // and it was WRONG: it assumed agent-agent interaction must manifest as repulsion. With the
            // avoidance sampler working, the pair resolves its conflict AT A DISTANCE — they de-overlap
            // from the co-located spawn and walk the shared stem in single file ~145-190cm apart, which
            // never enters _SeparationRadius (100cm), so the separation force correctly stays at zero
            // for the whole run. Requiring a non-zero repulsion would be requiring the agents to crowd
            // each other, i.e. asserting the very behaviour the avoidance layer exists to prevent.
            Assert_True(_MinInterAgentDist <= 284.0,
                f"VACUOUS PASS: the two agents never came within probe reach of each other (closest approach {_MinInterAgentDist}cm > 284cm = 2x ProbeRadius). They walked the shared stem without ever being neighbours, so the standoff scenario was never exercised.");

            FinishSuccess();
            return;
        }

        if (_ElapsedSec < WatchdogSec) { return; }

        // LIVENESS backstop: they never deadlocked (the contact assertion above would have caught
        // that) but they still never arrived. Something else is wrong -- a route that never
        // installed, an agent stuck on geometry, a corridor that cannot be walked.
        Describe("SOUTH", _AgentSouth, _FollowerSouth, GoalS, _ReachedSouth);
        Describe("NORTH", _AgentNorth, _FollowerNorth, GoalN, _ReachedNorth);

        FinishFailure(f"agents never arrived within {WatchdogSec}s (reachedSouth={_ReachedSouth} reachedNorth={_ReachedNorth}), yet the pair's longest unbroken contact was only {_MaxContactRunSec}s -- so this is NOT the standoff. Something else is blocking arrival. Per-agent corridor + waypoint-cursor dump logged above under LogCkPathNetwork.");
    }

    // Per-sample trace: the timeline of the encounter. Records closest approach and peak separation
    // so a lockstep no-op run is distinguishable from a real interaction that happened to resolve.
    private void Trace()
    {
        if (ck::Is_NOT_Valid(_AgentSouth) || ck::Is_NOT_Valid(_AgentNorth))
        { return; }

        const auto LocS = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_AgentSouth)));
        const auto LocN = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_AgentNorth)));

        const auto Dist = float((LocS - LocN).Size());
        if (Dist < _MinInterAgentDist) { _MinInterAgentDist = Dist; }

        // Unbroken-contact run. Resets the moment they genuinely separate, so a healthy brush-past
        // scores ~1s while a standoff accumulates without interruption.
        if (Dist <= ContactThresholdCm)
        {
            _ContactRunSec += SampleIntervalSec;
            if (_ContactRunSec > _MaxContactRunSec) { _MaxContactRunSec = _ContactRunSec; }
        }
        else
        {
            _ContactRunSec = 0.0;
        }

        const auto SepS = float(utils_crowd_agent::Get_SeparationForce(_AgentSouth).Size());
        const auto SepN = float(utils_crowd_agent::Get_SeparationForce(_AgentNorth).Size());
        if (SepS > _MaxSepMag) { _MaxSepMag = SepS; }
        if (SepN > _MaxSepMag) { _MaxSepMag = SepN; }

        const auto CurS = utils_crowd_agent::Get_CurrentWaypointIndex(_AgentSouth);
        const auto CurN = utils_crowd_agent::Get_CurrentWaypointIndex(_AgentNorth);

        ck::pathnetwork::Log(f"[TRACE] t={_ElapsedSec} gap={Dist} | S pos={LocS} cursor={CurS} sep={SepS} | N pos={LocN} cursor={CurN} sep={SepN}");
    }

    // The diagnostic. Reports WHICH waypoint each agent is steering at plus the whole corridor, so
    // an already-passed target (H1) is distinguishable from a genuinely-unreached one (H2).
    private void Describe(FString InLabel, FCk_Handle_CrowdAgent InAgent,
        FCk_Handle_PathNetworkFollower InFollower, FVector InGoal, bool InReached)
    {
        if (ck::Is_NOT_Valid(InAgent))
        {
            ck::pathnetwork::Log(f"[STANDOFF][{InLabel}] agent handle INVALID");
            return;
        }

        const auto Loc = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(InAgent)));
        const auto Index = utils_crowd_agent::Get_CurrentWaypointIndex(InAgent);
        const auto SepForce = utils_crowd_agent::Get_SeparationForce(InAgent);
        const auto DesiredVel = utils_crowd_agent::Get_DesiredVelocity(InAgent);
        const auto DistToGoal = float((Loc - InGoal).Size());

        ck::pathnetwork::Log(f"[STANDOFF][{InLabel}] reached={InReached} pos={Loc} goal={InGoal} distToGoal={DistToGoal} waypointCursor={Index} sepForce={SepForce} desiredVel={DesiredVel}");

        if (ck::Is_NOT_Valid(InFollower))
        {
            ck::pathnetwork::Log(f"[STANDOFF][{InLabel}] follower handle INVALID — corridor unavailable");
            return;
        }

        const auto Route = utils_path_network_follower::Get_RouteResult(InFollower);
        const auto Waypoints = Route.Get_CompiledWaypoints();

        ck::pathnetwork::Log(f"[STANDOFF][{InLabel}] routeStatus={Route.Get_Status()} corridorWaypoints={Waypoints.Num()}");

        if (Index >= 0 && Index < Waypoints.Num())
        {
            const auto Target = Waypoints[Index];
            const auto DistToTarget = float((Target - Loc).Size());
            ck::pathnetwork::Log(f"[STANDOFF][{InLabel}] STEERING AT wp[{Index}] = {Target} (distance {DistToTarget}cm)");
        }
        else
        {
            ck::pathnetwork::Log(f"[STANDOFF][{InLabel}] waypoint cursor {Index} is OUT OF RANGE for {Waypoints.Num()} waypoints");
        }

        for (int32 i = 0; i < Waypoints.Num(); ++i)
        {
            const auto W = Waypoints[i];
            const auto D = float((W - Loc).Size());
            ck::pathnetwork::Log(f"[STANDOFF][{InLabel}]   wp[{i}] = {W} (dist from agent {D}cm)");
        }
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        FCk_Handle GenericAgent = utils_entity_lifetime::Request_CreateEntity(_Self);
        GenericAgent.Set_DebugName(InDebugName);

        auto AgentTransform = utils_transform::Add(GenericAgent,
            FTransform(FRotator::ZeroRotator, Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(GenericAgent,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(GenericAgent,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(GenericAgent);

        return Agent;
    }

    private FCk_Handle_PathNetworkFollower AddFollower(FCk_Handle_CrowdAgent InAgent)
    {
        FCk_Handle GenericAgent = InAgent;

        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_OffPathCostMultiplier(OffPathMultiplier);

        return utils_path_network_follower::Add(GenericAgent, FollowerParams);
    }

    UFUNCTION()
    private void OnSouthReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        _ReachedSouth = true;
    }

    UFUNCTION()
    private void OnNorthReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        _ReachedNorth = true;
    }

    UFUNCTION()
    private void OnSouthFailed(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        FinishFailure("agent SOUTH reported OnGoalFailed — the route never resolved. That is NOT the standoff under test; the corridor failed to install.");
    }

    UFUNCTION()
    private void OnNorthFailed(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        FinishFailure("agent NORTH reported OnGoalFailed — the route never resolved. That is NOT the standoff under test; the corridor failed to install.");
    }
}

class ACk_AutoTest_PathNetworkFollower_TJunctionSharedStem_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_PathNetworkFollower_TJunctionSharedStem;
    default _TimeoutSeconds = 30.0f;
}
