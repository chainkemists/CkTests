// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: WALL SEGMENTS KEEP A SAMPLED AGENT ON THE MESH
//
// FProcessor_CrowdAgent_AvoidanceSample scores candidate velocities against
// dtCrowd's local boundary (FFragment_CrowdAgent_LocalBoundary — the port of
// dtLocalBoundary + dtObstacleAvoidanceQuery::addSegment) as well as against
// neighbouring agents.
//
// PRE-FIX FAILURE MODE. The sampler scored NEIGHBOURS ONLY, so a candidate
// velocity aimed straight at a navmesh boundary cost exactly nothing. Two
// things then conspire against an agent walking beside a wall:
//   * the cheapest way to dodge a neighbour is "away from it", and if the
//     neighbour sits on the wall side then that direction is INTO the wall;
//   * _AvoidanceSidePreference (PassLeft by default) independently biases
//     candidates to the agent's left, which here is also the wall.
// The winner is then a velocity pointing into geometry the agent cannot enter,
// FProcessor_CrowdAgent_ConstrainToNavmesh eats the displacement, and the agent
// grinds along the boundary instead of walking around the neighbour through the
// wide-open mesh on its other side. In a crowd this is the "walking on the
// spot" mode: 329 near-zero-velocity walkers and 33 into-wall pinned samples in
// a 14-NPC soak, against 1 and 2 with the sampler disabled entirely.
//
// FIXTURE. Probe for the navmesh's -X edge, then run walker A up the +Y axis on
// a lane CorridorInsetUu inboard of it. Blocker B stands still on that lane but
// nudged BlockerWallOffsetUu further toward the wall, so the gap between B and
// the boundary is far narrower than the 84uu radius sum — squeezing past on the
// wall side is geometrically impossible — while the interior (+X) side is
// wide-open mesh.
//
// ASSERTIONS. A reaches its goal; A never stalls longer than MaxStallSec
// (sampled every SampleIntervalSec, so a pinned agent is caught rather than
// waited out); A passes B on the INTERIOR side at closest approach; A stays on
// the navmesh. Two anti-vacuity guards: A must have been observed moving, and A
// must actually have come near B — a silently failed path, or a stationary
// markup detour that re-routes A before it ever meets B, would otherwise
// satisfy every other check without exercising the sampler at all.
//
// ---------------------------------------------------------------------------
// THIS TEST PINS THE CONTRACT. IT DOES NOT REPRODUCE THE PRE-FIX FAILURE.
// ---------------------------------------------------------------------------
// It is NOT red-green on _AvoidanceWallSegments: measured 2026-08-16, it passes
// with the setting Disabled exactly as it passes with it Enabled (walker 128uu
// clear on the INTERIOR side, worst stall 0.3s). What it guards is a regression
// that drives the walker onto the boundary or deadlocks it — real value, but
// not proof that the wall term is what keeps it off. A "red-green" claim stood
// in this header before; it was never true.
//
// FOUR FIXTURES WERE BUILT AND MEASURED TRYING TO MAKE IT BITE, AND EACH FAILED
// FOR A DIFFERENT STRUCTURAL REASON. Read these before spending a day on a
// fifth:
//
//  1. B ON THE WALL SIDE (this fixture). "Dodge away from the neighbour"
//     already points at the open interior, so the sampler is never asked to
//     choose the wall and the wall term has nothing to overrule.
//
//  2. B MOVED INBOARD, so the cheap dodge points at the wall. Then SEPARATION,
//     not the sampler, decides: it is a reactive force computed from the
//     current neighbour offset with no navmesh in its path, and inside its
//     radius it dominates the desired velocity. Measured with the wall term
//     ENABLED: the walker ended 6.7uu off the boundary, stalled 6.4s, never
//     arrived.
//
//  3. AS (2) WITH _SeparationWeight = 0 on both agents, to leave the sampler
//     alone in charge. Against a STATIONARY obstacle the sampler's cheapest
//     candidate is a slower version of straight ahead — slowing pushes the
//     predicted collision past the horizon and costs almost nothing — so the
//     walker crept up and dithered, and push-apart owned the endgame. Measured
//     with the term ENABLED: 5.1uu off the boundary, worst stall 10.2s.
//
//  4. B REPLACED BY A NON-YIELDING MOVING OPPOSER (TAG_CrowdAvoidance_
//     NeverSample), head-on, separation zeroed, probe reach widened — a closing
//     pair has no escape in time, so the choice really is lateral. The sampler
//     emits the MINIMUM deflection that clears the predicted collision, contact
//     happens anyway, and PushApart — wall-blind by design, and a different
//     setting — carries the walker onto the boundary. Measured with the term
//     ENABLED, both with an inboard opposer lane and with a dead-on one: 5uu
//     off the boundary.
//
// AND THE STRUCTURAL REASON THE WALL TERM IS WEAK AT RANGE, which is the thing
// worth looking at if this test should ever go red-green: the segment branch
// scores a candidate through IntersectRaySegment2D, whose ray parameter is
// clamped to [0,1]. With a candidate VELOCITY as the ray direction that
// parameter is SECONDS, so a boundary further away than (candidate speed * 1s)
// is not scored at all — no penalty, not even a small one. A minimal-deflection
// winner is therefore already committed to the wall side by the time the term
// engages. dtCrowd has the same clamp, so this is port-faithful; it is a limit
// of the feature, not a defect in the fixture.
//
// (Its sibling, Crowd_Steering_CornerRetirementKeepsAgentOnMesh, IS red-green
// on _WaypointRetirementLineOfSight — see that file for the shape of a fixture
// that discriminates.)
//
// REQUIREMENT: AutoTests_CkTests_Level's NavMeshBoundsVolume + floor.
//============================================================================

class UCk_AutoTest_Crowd_Avoidance_WallSegmentsKeepAgentOnMesh : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    // ---- navmesh edge probe (mirrors Crowd_PushApart_AgentStaysOnNavmesh) ----
    private const float32 ProbeExtentUu = 5.0f;
    private const float32 ProbeVerticalExtentUu = 300.0f;
    private const float32 OnMeshAssertExtentUu = 15.0f;
    private const float CoarseStepUu = 250.0;
    private const float RefineStepUu = 5.0;
    private const float MaxProbeUu = 20000.0;

    // ---- fixture ----
    private const float32 AgentRadiusUu = 42.0f;
    private const float32 AgentHeightUu = 192.0f;
    private const float CorridorInsetUu = 60.0;      // walker lane, inboard of the -X boundary
    private const float BlockerWallOffsetUu = 25.0;  // blocker sits this much further toward the wall
    private const float ApproachUu = 350.0;          // short on purpose: the encounter must beat the
                                                     // stationary-markup delay, or PathRefresh
                                                     // detours the walker and the sampler never runs
    private const float RunOutUu = 350.0;

    // ---- sampling / deadlines ----
    private const float SampleIntervalSec = 0.1;
    private const float MaxStallSec = 1.0;
    private const float ProgressEpsilonUu = 5.0;
    private const float ArriveDeadlineSec = 16.0;
    private const int32 MinMotionSamples = 10;
    private const float ArrivalToleranceUu = 110.0;
    private const float MaxEngagementDistanceUu = 500.0;

    private FCk_Handle_CrowdAgent _Walker;
    private FCk_Handle_CrowdAgent _Blocker;

    private float _EdgeX = 0.0;
    private float _FloorZ = 0.0;
    private float _CorridorX = 0.0;
    private float _BlockerX = 0.0;
    private float _GoalY = 0.0;
    private bool _MeshFound = false;

    private float _ElapsedSec = 0.0;
    private int32 _SamplesWithMotion = 0;

    private float _BestY = -999999.0;
    private float _SecondsSinceProgress = 0.0;
    private float _WorstStallSec = 0.0;

    private float _ClosestAlignmentY = 999999.0;
    private float _WalkerXAtClosestAlignment = -999999.0;
    private float _MinDistanceToBlocker = 999999.0;
    private float _MinWalkerX = 999999.0;
    private FVector _LastWalkerLoc = FVector::ZeroVector;

    private bool _Reached = false;
    private bool _Failed = false;
    private float _FinalDistToGoal = -1.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the navmesh: AutoTests_CkTests_Level has the fixture but the bake is lazy, and the
        // edge probe below is synchronous.
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSample"));
    }

    UFUNCTION()
    private void OnSample(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto SelfHandle = DoGet_ScriptEntity();

        if (_MeshFound == false)
        {
            Tick_WaitForMesh(SelfHandle);
            return;
        }

        _ElapsedSec += SampleIntervalSec;

        if (ck::Is_NOT_Valid(_Walker) || ck::Is_NOT_Valid(_Blocker))
        {
            FinishFailure("an agent went invalid mid-run");
            return;
        }

        if (_Failed)
        {
            FinishFailure(f"the walker reported OnGoalFailed even though the interior side of the blocker was open mesh the whole time (elapsed {_ElapsedSec}s)");
            return;
        }

        Sample_Walker();

        if (_Reached)
        {
            Report(SelfHandle);
            return;
        }

        if (_ElapsedSec >= ArriveDeadlineSec)
        {
            const auto Loc = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Walker)));
            const auto DistToGoal = float((Loc - FVector(_CorridorX, _GoalY, _FloorZ)).Size2D());
            const auto State = utils_crowd_agent::Get_MovementState(_Walker);
            const auto WallGap = float(Loc.X - _EdgeX);
            FinishFailure(f"NEVER ARRIVED: the walker was still {DistToGoal}uu from its goal at t={_ElapsedSec}s (state={State}, worst stall {_WorstStallSec}s, {WallGap}uu from the navmesh edge). The sampler steered it into the boundary instead of around the blocker through open mesh.");
        }
    }

    private void Tick_WaitForMesh(FCk_Handle& InSelfHandle)
    {
        FVector OriginOnMesh;
        if (utils_nav::Try_ProjectOntoNavmesh(InSelfHandle, FVector::ZeroVector, 100.0f, OriginOnMesh, ProbeVerticalExtentUu) == false)
        { return; }   // bake not done yet — keep polling

        _MeshFound = true;
        _FloorZ = float(OriginOnMesh.Z);

        if (FindMeshEdgeTowardsNegativeX(InSelfHandle) == false)
        {
            FinishFailure(f"navmesh -X edge not found within {MaxProbeUu}uu of origin — test level changed?");
            return;
        }

        _CorridorX = _EdgeX + CorridorInsetUu;
        _BlockerX = _CorridorX - BlockerWallOffsetUu;
        _GoalY = RunOutUu;

        // The blocker goes down FIRST so the walker's very first path is planned with it already
        // standing there. It is idle — no MoveTo — which is what makes it an obstacle rather than a
        // participant in a mutual dodge.
        _Blocker = SpawnAgent(InSelfHandle, FVector(_BlockerX, 0.0, _FloorZ + 100.0), n"WallSegments_Blocker");

        const auto Spawn = FVector(_CorridorX, -ApproachUu, _FloorZ + 100.0);
        const auto Goal = FVector(_CorridorX, _GoalY, _FloorZ);
        _Walker = SpawnAgent(InSelfHandle, Spawn, n"WallSegments_Walker");
        _LastWalkerLoc = Spawn;
        _BestY = float(Spawn.Y);

        utils_crowd_agent::BindTo_OnGoalReached(_Walker,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(_Walker,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    private void Sample_Walker()
    {
        const auto Loc = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Walker)));
        const auto BlockerLoc = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Blocker)));

        const auto DesiredVelocity = utils_crowd_agent::Get_DesiredVelocity(_Walker);
        if (DesiredVelocity.IsNearlyZero() == false)
        { ++_SamplesWithMotion; }

        // Progress is measured along the run axis, not as raw displacement: a wall-pinned agent
        // still jitters in place, and displacement would read that jitter as motion.
        if (float(Loc.Y) > _BestY + ProgressEpsilonUu)
        {
            _BestY = float(Loc.Y);
            _SecondsSinceProgress = 0.0;
        }
        else
        {
            _SecondsSinceProgress += SampleIntervalSec;
            if (_SecondsSinceProgress > _WorstStallSec)
            { _WorstStallSec = _SecondsSinceProgress; }
        }

        if (float(Loc.X) < _MinWalkerX)
        { _MinWalkerX = float(Loc.X); }

        const auto DistanceToBlocker = float((Loc - BlockerLoc).Size2D());
        if (DistanceToBlocker < _MinDistanceToBlocker)
        { _MinDistanceToBlocker = DistanceToBlocker; }

        const auto AlignmentY = Math::Abs(float(Loc.Y - BlockerLoc.Y));
        if (AlignmentY < _ClosestAlignmentY)
        {
            _ClosestAlignmentY = AlignmentY;
            _WalkerXAtClosestAlignment = float(Loc.X);
        }

        _LastWalkerLoc = Loc;
    }

    private void Report(FCk_Handle& InSelfHandle)
    {
        Assert_True(_SamplesWithMotion >= MinMotionSamples,
            f"only {_SamplesWithMotion} samples saw a non-zero desired velocity (need >= {MinMotionSamples}) — the walker never really moved, so every other assertion here would pass vacuously");

        Assert_True(_MinDistanceToBlocker <= MaxEngagementDistanceUu,
            f"the walker never came closer than {_MinDistanceToBlocker}uu to the blocker (limit {MaxEngagementDistanceUu}uu) — it was routed around before the avoidance sampler ever had to choose a side, so this run proves nothing about wall segments");

        Assert_True(_FinalDistToGoal >= 0.0 && _FinalDistToGoal <= ArrivalToleranceUu,
            f"the walker stopped within its arrival contract of the goal (distance={_FinalDistToGoal}, tolerance={ArrivalToleranceUu})");

        Assert_True(_WorstStallSec <= MaxStallSec,
            f"the walker stopped making progress along its run for {_WorstStallSec}s (limit {MaxStallSec}s) — that is the navmesh clamp eating a displacement the sampler aimed at the boundary, i.e. walking on the spot");

        // The decisive one. The blocker sits toward the wall, leaving a gap far narrower than the
        // 84uu radius sum, so the only passable side is the interior. Both the neighbour dodge and
        // the PassLeft side preference point the other way; only the wall term can overrule them.
        const auto WallSideGapUu = _BlockerX - _EdgeX;
        Assert_True(_WalkerXAtClosestAlignment > _BlockerX,
            f"at closest alignment the walker was at X={_WalkerXAtClosestAlignment}, on the WALL side of the blocker (X={_BlockerX}, navmesh edge X={_EdgeX}). It tried to squeeze through a {WallSideGapUu}uu gap instead of passing through open mesh on the interior side.");

        Assert_True(_MinWalkerX > _EdgeX,
            f"the walker's centre reached X={_MinWalkerX}, at or past the navmesh edge X={_EdgeX}");

        AssertOnMesh(InSelfHandle, _LastWalkerLoc, "walker");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished() || _Reached) { return; }

        _Reached = true;
        const auto Loc = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(InAgent)));
        _FinalDistToGoal = float((Loc - FVector(_CorridorX, _GoalY, _FloorZ)).Size2D());
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        _Failed = true;
    }

    private void AssertOnMesh(FCk_Handle& InSelfHandle, FVector InAgentLoc, FString InWho)
    {
        FVector OnMesh;
        const auto Projected = utils_nav::Try_ProjectOntoNavmesh(
            InSelfHandle, InAgentLoc, OnMeshAssertExtentUu, OnMesh, ProbeVerticalExtentUu);

        const auto AgentX = float(InAgentLoc.X);
        Assert_True(Projected,
            f"{InWho} ended OFF the navmesh at X={AgentX} (mesh edge X={_EdgeX})");
    }

    private bool FindMeshEdgeTowardsNegativeX(FCk_Handle& InSelfHandle)
    {
        FVector Unused;

        float LastGoodX = 0.0;
        float CoarseFailX = 1.0;
        bool CoarseFailed = false;
        for (float X = -CoarseStepUu; X >= -MaxProbeUu; X -= CoarseStepUu)
        {
            if (utils_nav::Try_ProjectOntoNavmesh(InSelfHandle, FVector(X, 0.0, _FloorZ), ProbeExtentUu, Unused, ProbeVerticalExtentUu) == false)
            {
                CoarseFailX = X;
                CoarseFailed = true;
                break;
            }
            LastGoodX = X;
        }

        if (CoarseFailed == false)
        { return false; }

        for (float X = LastGoodX - RefineStepUu; X > CoarseFailX; X -= RefineStepUu)
        {
            if (utils_nav::Try_ProjectOntoNavmesh(InSelfHandle, FVector(X, 0.0, _FloorZ), ProbeExtentUu, Unused, ProbeVerticalExtentUu) == false)
            { break; }
            LastGoodX = X;
        }

        _EdgeX = LastGoodX;
        return true;
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(AgentRadiusUu, AgentHeightUu);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
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

class ACk_AutoTest_Crowd_Avoidance_WallSegmentsKeepAgentOnMesh_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Avoidance_WallSegmentsKeepAgentOnMesh;
    default _TimeoutSeconds = 30.0f;
}
