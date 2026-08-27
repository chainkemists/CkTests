// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: CORNER RETIREMENT KEEPS THE AGENT ON THE MESH
//
// FProcessor_CrowdAgent_Steering retires the waypoint it is steering at when
// the agent is within _WaypointArrivalRadius (25uu) of it, OR when the agent
// crosses the plane through it perpendicular to the incoming segment.
//
// PRE-FIX FAILURE MODE. Both tests are laterally BLIND. The plane is unbounded
// perpendicular to the segment, and proximity says nothing about which side of
// the corridor the agent stands on - so a corner is given up while the agent is
// still SHORT of it or BESIDE it, and steering re-aims at Waypoints[k+1] along a
// chord that cuts the UNavArea_Null hole the planner routed around. The polyline
// is FROZEN at plan time (Detour has no such bug: dtPathCorridor re-string-pulls
// from the agent's CURRENT position every frame), so nothing re-plans that aim.
// FProcessor_CrowdAgent_ConstrainToNavmesh then eats the displacement - the
// surface walk keeps only the sliver tangential to the hole face - and the agent
// creeps along the boundary at a few uu/s until BlockDetect's no-progress window
// (3s) notices. Measured in the field: clipFrac 1.00 against a 240uu/s desired
// velocity, 2.8s walking on the spot, nav raycast agent->k+1 BLOCKED while
// segStart->k+1 was CLEAR.
//
// FIXTURE. Probe for the navmesh's -Y edge, then paint a nav-null WALL that runs
// from beyond that edge up to WallTipY, spanning x in [WallMinX, WallMaxX]. It
// plugs the whole southern half of the volume, so the only route from the
// east-side spawn to the west-side goal rounds the wall's NORTH-EAST tip and
// then runs the full length of its north face. Recast therefore string-pulls a
// corner at the eroded NE tip (call it C1) with the next corner ~870uu due west
// at the eroded NW tip (C2).
//
// WHY IT IS RED PRE-FIX - AND WHY THE APPROACH ANGLE IS THE WHOLE FIXTURE.
// Approaching C1, the agent hits the 25uu proximity test while still
// h = 25*sin(theta) SOUTH of the C1->C2 line, theta being the turn angle at the
// corner. The chord from there to C2 runs almost due west and enters the eroded
// wall through its EAST face, so the pre-fix retirement points steering at
// geometry the agent cannot enter; ConstrainToNavmesh keeps only the sliver
// tangential to that face, which is MaxSpeed * h / |C1->C2| - a couple of uu/s
// against a 240uu/s desired velocity - and h decays with a time constant of
// |C1->C2| / MaxSpeed (~3.6s here), so nothing but BlockDetect's 3s ladder ends
// it.
//
// What rescues the agent is its RESIDUAL velocity: at retirement it is still
// aimed at C1 and rotates onto the new aim at _MaxTurnRate, climbing
// (MaxSpeed / MaxTurnRate) * (1 - cos theta) = 60 * (1 - cos theta) uu in the
// process. Reaching C1's level frees it. So the corner only pins when
//
//     60 * (1 - cos theta)  <  25 * sin(theta)   <=>   theta < ~45 deg
//
// at the shipped defaults (MaxSpeed 240, MaxTurnRate 4, _WaypointArrivalRadius
// 25). SpawnY is chosen to put theta at ~23 deg - comfortably inside the pinning
// regime while leaving h ~10uu, big enough that the chord is unambiguously
// blocked against voxel-quantised erosion. An earlier revision of this fixture
// approached at 58 deg and passed with the gate OFF for exactly this reason:
// measured, the agent cleared the corner in 0.1s and never clipped at all.
// POST-FIX the chord reads blocked, the corner is NOT retired, the agent walks
// to C1 - on-mesh by construction - and turns there.
//
// Red-green via UCk_Crowd_ProjectSettings_UE::_WaypointRetirementLineOfSight.
//
// NOTE ON WHICH LEG IS EXERCISED: a single agent has no lateral force acting on
// it, so its approach lane is exactly the planned leg and the PROXIMITY leg is
// what fires first here. The plane leg carries the identical blindness and is
// gated by the same code; reproducing it deterministically needs a lateral
// displacement source (a neighbour, a shove) that would make this fixture
// non-deterministic.
//
// ASSERTIONS. The agent reaches the goal; it never stalls (a 1.0s window in
// which it is Walking with a desired velocity >= StallSpeedFloorUu but moved
// less than StallDisplacementUu); it ends on the navmesh. Two anti-vacuity
// guards: it must have been observed moving at all, and it must have passed
// within MaxTipApproachUu of the wall's NE corner - otherwise it took some
// other route and never met the corner under test.
//
// SHARED-WORLD HYGIENE: an unpainted nav-null area left behind would split the
// navmesh for every later crowd test. The wall comes down before the test
// reports, the run waits for the tiles to come back, and DoEndPlay unpaints it
// again as a backstop for the timeout path.
//
// REQUIREMENT: AutoTests_CkTests_Level's NavMeshBoundsVolume + floor.
//============================================================================

class UCk_AutoTest_Crowd_Steering_CornerRetirementKeepsAgentOnMesh : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 40.0f;

    // ---- navmesh probing ----
    private const float32 EdgeProbeExtentUu = 5.0f;
    private const float32 ProbeVerticalExtentUu = 300.0f;
    private const float32 OnMeshAssertExtentUu = 15.0f;
    // Small enough that a successful projection at the wall's centre means the
    // hole is genuinely there (a wide probe would snap to mesh outside it).
    private const float32 HoleProbeHalfExtentUu = 20.0f;
    private const float CoarseStepUu = 250.0;
    private const float RefineStepUu = 5.0;
    private const float MaxProbeUu = 20000.0;

    // ---- fixture ----
    private const float32 AgentRadiusUu = 42.0f;
    private const float32 AgentHeightUu = 192.0f;

    // The wall's own geometry. Its north face is the long one the agent must run
    // after rounding the tip - length is what sets the pre-fix pin duration.
    private const float WallMinX = -700.0;
    private const float WallMaxX = 100.0;
    private const float WallTipY = 300.0;
    private const float WallOverhangUu = 200.0;   // reaches PAST the mesh's -Y edge, so no southern gap
    private const float WallHalfZ = 300.0;

    private const float SpawnX = 600.0;
    // The load-bearing number. The turn at C1 is theta = atan((C1.y - SpawnY) / (SpawnX - C1.x));
    // with the eroded tip near (135, 347) that is ~23 deg, inside the pinning regime derived in
    // the header. Raising SpawnY toward the tip SHRINKS theta (longer pin, but a smaller lateral
    // error h to keep the chord unambiguously blocked); LOWERING it grows theta, and past ~45 deg
    // the agent's residual velocity clears the corner on its own - that is the configuration this
    // test shipped with, and it passed with the gate OFF.
    private const float SpawnY = 150.0;
    private const float GoalX = -830.0;
    private const float RunY = -400.0;            // the goal, well south of the tip

    // ---- sampling / stall detection ----
    private const float SampleIntervalSec = 0.1;
    private const int32 StallWindowSamples = 10;  // 1.0s of history at SampleIntervalSec
    private const float StallDisplacementUu = 15.0;
    private const float StallSpeedFloorUu = 60.0;
    private const int32 MinMotionSamples = 10;

    // ---- deadlines ----
    private const float ArriveDeadlineSec = 28.0;   // ~2500uu of route at 240uu/s plus ramp and slack
    private const float HardDeadlineSec = 34.0;     // ahead of the engine TimeLimit, so the wall always comes down
    private const int32 MaxTeardownPolls = 40;

    // ---- assertions ----
    private const float ArrivalToleranceUu = 110.0;
    private const float MaxTipApproachUu = 250.0;

    private FCk_Handle_CrowdAgent _Agent;
    private UCk_NavAreaMarkup_UE _Wall = nullptr;

    private float _FloorZ = 0.0;
    private float _SouthEdgeY = 0.0;
    private bool _MeshFound = false;
    private bool _WallPainted = false;
    private bool _HoleConfirmed = false;

    private float _ElapsedSec = 0.0;
    private float _SpawnedAtSec = -1.0;
    private int32 _SamplesWithMotion = 0;

    private TArray<FVector> _History;
    private float _WorstWindowDisplacementUu = -1.0;
    private float _WorstWindowAtSec = -1.0;
    private int32 _StalledSamples = 0;

    private float _MinDistanceToTipUu = 999999.0;
    private FVector _LastAgentLoc = FVector::ZeroVector;

    private bool _Reached = false;
    private bool _UnexpectedFailure = false;
    private int32 _BlockedCount = 0;
    private float _FinalDistToGoal = -1.0;

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

        // AutoTests_CkTests_Level has the fixture but the bake is lazy, and the edge probe below
        // is synchronous.
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    // The nav-null area is a WORLD-scoped side effect with no owner-driven lifetime, so it has to
    // come down on every exit path - including the one where the engine TimeLimit kills the test
    // before OnPoll can react.
    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
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

        if (_ElapsedSec >= HardDeadlineSec)
        {
            Begin_Teardown(false, f"HARD DEADLINE at {_ElapsedSec}s (meshFound={_MeshFound}, wallPainted={_WallPainted}, holeConfirmed={_HoleConfirmed}, reached={_Reached}, blocks={_BlockedCount})");
            return;
        }

        if (_MeshFound == false)
        {
            Tick_WaitForMesh(SelfHandle);
            return;
        }

        if (_HoleConfirmed == false)
        {
            Tick_WaitForHole(SelfHandle);
            return;
        }

        if (ck::Is_NOT_Valid(_Agent))
        {
            Begin_Teardown(false, "the walker went invalid mid-run");
            return;
        }

        if (_UnexpectedFailure)
        {
            Begin_Teardown(false, f"the walker reported OnGoalFailed even though the route around the wall's north tip was open the whole time (worst 1s displacement {_WorstWindowDisplacementUu}uu at t={_WorstWindowAtSec}s, stalled samples={_StalledSamples}, blocks={_BlockedCount}). Retiring the tip corner early aims it into the north face, the navmesh clamp eats the displacement, and BlockDetect's ladder runs out.");
            return;
        }

        Sample_Walker();

        if (_Reached)
        {
            Report(SelfHandle);
            return;
        }

        const auto RunSec = _ElapsedSec - _SpawnedAtSec;
        if (RunSec >= ArriveDeadlineSec)
        {
            const auto Loc = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Agent)));
            const auto DistToGoal = float((Loc - FVector(GoalX, RunY, _FloorZ)).Size2D());
            const auto State = utils_crowd_agent::Get_MovementState(_Agent);
            Begin_Teardown(false, f"NEVER ARRIVED: the walker was still {DistToGoal}uu from its goal after {RunSec}s (state={State}, stalled samples={_StalledSamples}, worst 1s displacement {_WorstWindowDisplacementUu}uu at t={_WorstWindowAtSec}s, blocks={_BlockedCount}). A corner retired before the chord onward is navigable points steering into the wall face.");
        }
    }

    private void Tick_WaitForMesh(FCk_Handle& InSelf)
    {
        FVector OriginOnMesh;
        if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector::ZeroVector, 100.0f, OriginOnMesh, ProbeVerticalExtentUu) == false)
        { return; }   // bake not done yet - keep polling

        _FloorZ = float(OriginOnMesh.Z);

        if (FindMeshEdgeTowardsNegativeY(InSelf) == false)
        {
            Begin_Teardown(false, f"navmesh -Y edge not found within {MaxProbeUu}uu of origin - test level changed?");
            return;
        }

        _MeshFound = true;
        Paint_Wall(InSelf);
        _WallPainted = true;
    }

    // The markup schedules an async tile rebuild. Spawning before the hole exists would let the
    // walker's first path go STRAIGHT to the goal, and the corner under test would never exist.
    private void Tick_WaitForHole(FCk_Handle& InSelf)
    {
        FVector Unused;
        const auto HoleCentre = FVector(0.5 * (WallMinX + WallMaxX), 0.0, _FloorZ);
        if (utils_nav::Try_ProjectOntoNavmesh(InSelf, HoleCentre, HoleProbeHalfExtentUu, Unused, ProbeVerticalExtentUu))
        { return; }   // mesh still there - the rebuild has not landed

        _HoleConfirmed = true;
        SpawnWalker(InSelf);
        _SpawnedAtSec = _ElapsedSec;
    }

    private void Sample_Walker()
    {
        const auto Loc = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Agent)));
        _LastAgentLoc = Loc;

        const auto DesiredVelocity = utils_crowd_agent::Get_DesiredVelocity(_Agent);
        if (DesiredVelocity.IsNearlyZero() == false)
        { ++_SamplesWithMotion; }

        const auto DistToTip = float((Loc - FVector(WallMaxX, WallTipY, _FloorZ)).Size2D());
        if (DistToTip < _MinDistanceToTipUu)
        { _MinDistanceToTipUu = DistToTip; }

        // Only a WALKING agent can stall: PathPending has no steering output by design, and the
        // history is dropped across the transition so a re-path window never reads as one.
        const auto IsWalking =
            utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking;
        if (IsWalking == false)
        {
            _History.Empty();
            return;
        }

        _History.Add(Loc);
        if (_History.Num() > StallWindowSamples)
        { _History.RemoveAt(0); }

        if (_History.Num() < StallWindowSamples)
        { return; }

        // Wanting to move but not moving is the signature: the clamp is eating a displacement
        // steering aimed at geometry. A braking or arrived agent has a small desired velocity and
        // is deliberately excluded.
        if (float(DesiredVelocity.Size2D()) < StallSpeedFloorUu)
        { return; }

        const auto WindowDisplacement =
            float((_History[_History.Num() - 1] - _History[0]).Size2D());

        if (_WorstWindowDisplacementUu < 0.0 || WindowDisplacement < _WorstWindowDisplacementUu)
        {
            _WorstWindowDisplacementUu = WindowDisplacement;
            _WorstWindowAtSec = _ElapsedSec;
        }

        if (WindowDisplacement < StallDisplacementUu)
        { ++_StalledSamples; }
    }

    private void Report(FCk_Handle& InSelf)
    {
        Assert_True(_SamplesWithMotion >= MinMotionSamples,
            f"only {_SamplesWithMotion} samples saw a non-zero desired velocity (need >= {MinMotionSamples}) - the walker never really moved, so every other assertion here would pass vacuously");

        Assert_True(_MinDistanceToTipUu <= MaxTipApproachUu,
            f"the walker never came closer than {_MinDistanceToTipUu}uu to the wall's north-east corner ({WallMaxX}, {WallTipY}) (limit {MaxTipApproachUu}uu) - it never rounded the tip, so it never met the corner this test is about and the run proves nothing");

        Assert_True(_FinalDistToGoal >= 0.0 && _FinalDistToGoal <= ArrivalToleranceUu,
            f"the walker stopped within its arrival contract of the goal (distance={_FinalDistToGoal}, tolerance={ArrivalToleranceUu})");

        // The decisive one. Rounding the tip, the 25uu proximity test fires while the walker is
        // still south of the north-face line; the chord from there to the far corner cuts the
        // eroded wall. Retiring on it points steering into the face, ConstrainToNavmesh keeps only
        // the sliver tangential to it, and the walker creeps at a few uu/s for the length of the
        // face divided by its speed.
        Assert_True(_StalledSamples == 0,
            f"the walker was Walking with a desired velocity of at least {StallSpeedFloorUu}uu/s yet covered only {_WorstWindowDisplacementUu}uu in a 1.0s window (limit {StallDisplacementUu}uu, at t={_WorstWindowAtSec}s, {_StalledSamples} such samples) - that is the navmesh clamp eating a displacement steering aimed at the wall face after giving up the tip corner too early");

        AssertOnMesh(InSelf, _LastAgentLoc);

        Begin_Teardown(true, "");
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished() || _Reached) { return; }

        _Reached = true;
        const auto Loc = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(InAgent)));
        _FinalDistToGoal = float((Loc - FVector(GoalX, RunY, _FloorZ)).Size2D());
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        _UnexpectedFailure = true;
    }

    // A block is not asserted on directly: BlockDetect legitimately fires while the tiles under a
    // freshly painted wall are still rebuilding. What must not happen is a stall or a failed move,
    // and both of those are asserted.
    UFUNCTION()
    private void OnGoalBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        if (IsFinished()) { return; }
        _BlockedCount += 1;
    }

    private void SpawnWalker(FCk_Handle& InOwner)
    {
        const auto Spawn = FVector(SpawnX, SpawnY, _FloorZ + 100.0);
        const auto Goal = FVector(GoalX, RunY, _FloorZ);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(AgentRadiusUu, AgentHeightUu);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(n"CornerRetirement_Walker");

        // Facing the wall's tip at spawn, so the first frames are not spent turning around.
        const auto Rot = (FVector(WallMaxX, WallTipY, _FloorZ) - Spawn).Rotation();
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

    // UNavArea_Null is a HOLE, not a toll: a cost area would leave the corridor traversable and the
    // path would simply pay to cross it, producing no corner at all.
    private void Paint_Wall(FCk_Handle& InOwner)
    {
        const auto WallSouthY = _SouthEdgeY - WallOverhangUu;
        const auto Centre = FVector(
            0.5 * (WallMinX + WallMaxX),
            0.5 * (WallSouthY + WallTipY),
            _FloorZ);
        const auto HalfExtents = FVector(
            0.5 * (WallMaxX - WallMinX),
            0.5 * (WallTipY - WallSouthY),
            WallHalfZ);

        _Wall = utils_nav_area_markup::Request_Create(InOwner,
            FTransform(FRotator::ZeroRotator, Centre, FVector::OneVector),
            HalfExtents,
            UNavArea_Null);
    }

    private void Destroy_Wall()
    {
        if (ck::Is_NOT_Valid(_Wall)) { return; }
        utils_nav_area_markup::Request_Destroy(_Wall);
        _Wall = nullptr;
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

    // Unregistering the markup schedules an async tile rebuild. Handing the shared PIE world to the
    // next crowd test with a half-restored navmesh is the same class of contamination as leaking an
    // entity, so wait for the hole to close - bounded, because the unregister has already happened
    // and the rebuild completes regardless.
    private void Tick_Teardown(FCk_Handle& InSelf)
    {
        _TeardownPolls += 1;

        auto MeshRestored = true;
        if (_WallPainted)
        {
            FVector Restored;
            const auto HoleCentre = FVector(0.5 * (WallMinX + WallMaxX), 0.0, _FloorZ);
            MeshRestored = utils_nav::Try_ProjectOntoNavmesh(InSelf,
                HoleCentre, HoleProbeHalfExtentUu, Restored, ProbeVerticalExtentUu);
        }

        if (MeshRestored == false && _TeardownPolls < MaxTeardownPolls)
        { return; }

        if (_TeardownPassed) { FinishSuccess(); }
        else { FinishFailure(_TeardownMessage); }
    }

    private void AssertOnMesh(FCk_Handle& InSelf, FVector InAgentLoc)
    {
        FVector OnMesh;
        const auto Projected = utils_nav::Try_ProjectOntoNavmesh(
            InSelf, InAgentLoc, OnMeshAssertExtentUu, OnMesh, ProbeVerticalExtentUu);

        const auto AgentX = float(InAgentLoc.X);
        const auto AgentY = float(InAgentLoc.Y);
        Assert_True(Projected,
            f"the walker ended OFF the navmesh at ({AgentX}, {AgentY})");
    }

    // Mirrors the -X sweep in Crowd_Avoidance_WallSegmentsKeepAgentOnMesh: coarse steps until the
    // projection fails, then a fine sweep back for the last on-mesh sample.
    private bool FindMeshEdgeTowardsNegativeY(FCk_Handle& InSelf)
    {
        FVector Unused;

        float LastGoodY = 0.0;
        float CoarseFailY = 1.0;
        bool CoarseFailed = false;
        for (float Y = -CoarseStepUu; Y >= -MaxProbeUu; Y -= CoarseStepUu)
        {
            if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector(0.0, Y, _FloorZ), EdgeProbeExtentUu, Unused, ProbeVerticalExtentUu) == false)
            {
                CoarseFailY = Y;
                CoarseFailed = true;
                break;
            }
            LastGoodY = Y;
        }

        if (CoarseFailed == false)
        { return false; }

        for (float Y = LastGoodY - RefineStepUu; Y > CoarseFailY; Y -= RefineStepUu)
        {
            if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector(0.0, Y, _FloorZ), EdgeProbeExtentUu, Unused, ProbeVerticalExtentUu) == false)
            { break; }
            LastGoodY = Y;
        }

        _SouthEdgeY = LastGoodY;
        return true;
    }
}

class ACk_AutoTest_Crowd_Steering_CornerRetirementKeepsAgentOnMesh_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Steering_CornerRetirementKeepsAgentOnMesh;
    default _TimeoutSeconds = 40.0f;
}
