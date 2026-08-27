// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A PRESSING AGENT'S BODY STAYS CALM
//
// FProcessor_CrowdAgent_FaceAngle turns the body toward the DESIRED-VELOCITY
// heading at _MaxTurnRate (4.0 rad/s = 229 deg/s), with no speed floor beyond
// KINDA_SMALL_NUMBER and no rejection of transient heading flips. That is fine
// for an agent that is actually travelling: its desired velocity points where
// it is going. It is wrong for an agent that is PRESSING - jammed against
// something it cannot pass, moving barely at all - because there the desired
// velocity is the avoidance sampler's per-frame choice among candidates that
// the navmesh clamp then eats, and it swings wildly frame to frame. The body
// faithfully chases every swing and the agent whips on the spot at up to the
// full turn rate while its feet go nowhere.
//
// THE CONTRACT THIS PINS. Facing must be held below a real speed floor, and a
// large transient heading flip must persist before the body commits to it. So
// a pressing, near-stationary agent's yaw is nearly frozen: it may settle once
// or twice as the press resolves, but it does not alternate direction, and it
// does not sweep a large total arc while standing still.
//
// WHAT THIS DOES *NOT* PIN. The desired-velocity oscillation itself is not
// under test and is not being fixed here - only the body's TRACKING of it. The
// target yaw is therefore read and LOGGED every sample as an attribution
// channel (is the input still oscillating? did the body stop following it?) and
// deliberately never hard-asserted: an assertion on it would fail for a reason
// this test does not own.
//
// FIXTURE - a sustained press through a plugged gap, which is the shape the
// defect was actually observed in.
//   * Two UNavArea_Null slabs span the navmesh in Y with a 150cm gap at the
//     centre. Their outer ends are derived from a runtime probe for the mesh's
//     own +Y and -Y edges and then overrun it, so there is provably no route
//     around: crossing the wall plane is only possible through the gap. The
//     slabs are 300cm thick in X so the gap is a CORRIDOR and the press happens
//     inside it rather than in open mesh (see WallHalfX).
//   * One crowd agent stands parked in the gap centre and is NEVER commanded
//     anywhere. Radius 42 in a 150 gap leaves ~33cm of clear lane per side
//     against the walker's 84cm diameter - geometrically impassable. The
//     stationary markup it paints is a COST, not a hole, so the planner keeps
//     routing through the gap and the walker keeps trying.
//   * The walker starts 500cm short of the stranger and is sent to a point
//     250cm past it - near enough to keep pressing, far enough to stay out of
//     the cluster detector's goal region (see GoalX).
//
// SHARED-WORLD HYGIENE: a leftover nav-null slab would split the navmesh for
// every later crowd test. Both slabs come down before the test reports, the run
// waits for the tiles to return, and DoEndPlay unpaints them as a backstop.
//============================================================================

class UCk_AutoTest_Crowd_Facing_CalmWhilePressingBlockedGap : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 40.0f;

    // ---- fixture geometry -------------------------------------------------
    private const float WalkerSpawnX = -500.0;

    // 250cm past the stranger is load-bearing, not a round number. The cluster
    // detector blocks an agent that comes to rest in contact with a settled
    // neighbour parked inside its GOAL REGION, which at depth 0 is
    // SelfRadius + NbrRadius + ArrivalRadius + _CrowdedGoalContactPadCm
    // = 42 + 42 + 30 + 10 = 124cm. A goal any nearer the stranger would put it
    // inside that region, the walker would HOLD on contact instead of pressing,
    // and the whip this test measures would never happen. 250 is a 2x margin.
    private const float GoalX = 250.0;

    private const float GapHalfWidthUu = 75.0;   // 150cm gap, centred on y = 0

    // Thicker than Crowd_Stall_UnreachableGoalFailsBounded's 80, and the extra
    // thickness is load-bearing rather than cosmetic: it makes the gap a 300cm
    // CORRIDOR, and contact happens INSIDE it. The walker latches contact at
    // 104cm from the stranger, i.e. at x = -104, which sits 46cm past the mouth
    // at x = -150 - so both walls are beside it while it presses and its lateral
    // room is +/-33cm (75 gap half-width minus its own 42 radius). That matters
    // because a press in OPEN mesh is not a press: the avoidance sampler's
    // lateral candidates would become a real wall-face SLIDE at full speed, and
    // an agent genuinely travelling sideways is entitled to face sideways. The
    // corridor removes that escape, leaving the near-stationary regime the
    // facing contract is actually about. It also lengthens the runway a
    // PushApart-evicted stranger must be shoved along before the plug opens.
    private const float WallHalfX = 150.0;

    private const float WallHalfZ = 300.0;
    private const float WallOverrunUu = 400.0;   // how far past the mesh edge each slab runs

    private const float32 AgentRadiusUu = 42.0f;
    private const float32 AgentHeightUu = 192.0f;

    // Radius sum plus the same 20cm slack the module's own engagement ranges
    // use. Reaching this means the two bodies are touching, not merely near.
    private const float ContactRangeUu = 104.0;

    // ---- navmesh probing (mirrors Crowd_Avoidance_WallSegmentsKeepAgentOnMesh) ----
    private const float32 ProbeExtentUu = 5.0f;
    private const float32 ProbeVerticalExtentUu = 300.0f;
    private const float32 SlabProbeHalfExtentUu = 20.0f;
    private const float CoarseStepUu = 250.0;
    private const float RefineStepUu = 5.0;
    private const float MaxProbeUu = 20000.0;

    // ---- sampling / deadlines --------------------------------------------
    // Accumulated by the constant interval, never from InDeltaT - the timer's delta can read 0.0.
    private const float SampleIntervalSec = 0.1;

    // Bounds the pre-measurement stretch (bake, edge probes, slab paint, async
    // tile rebuild, spawn, path resolution) so a setup that never completes
    // names what it was waiting on instead of dying as an anonymous TimesUp.
    private const float PrepDeadlineSec = 12.0;

    // Approach is ~400cm at 240cm/s plus the accel ramp - under 2s. 12 covers a
    // loaded 4-lane run without ever masking a walker that simply never arrives.
    private const float ContactDeadlineSec = 12.0;

    private const float PressWindowSec = 6.0;
    private const float MinPressSec = 3.0;
    private const int32 MinPressSamples = 30;

    // Below this a delta is sampling noise, not a turn, and must not create a
    // spurious sign alternation.
    private const float NonTrivialDeltaDeg = 3.0;

    // A clean press may adjust once or twice as the contact resolves. The whip
    // alternates continuously - pre-fix runs are expected well above ten.
    private const int32 ReversalCeiling = 2;

    // PEAK PER-SAMPLE DELTA IS NOT ASSERTABLE HERE, on purpose. _MaxTurnRate is
    // 4.0 rad/s = 229.2 deg/s, so at a 100ms sampling interval the largest delta
    // physics can produce is 22.9 degrees. Any ceiling at or above ~23 is
    // unfalsifiable and any ceiling below it is measuring the sampler's phase,
    // not the defect. The discriminating quantity is the TOTAL arc swept over
    // the whole window: an agent standing still has no reason to sweep more
    // than a quarter turn in total, while a saturated whip accumulates hundreds
    // of degrees. Peak is still recorded and reported - for diagnosis, not as a
    // gate.
    private const float TotalYawTravelCeilingDeg = 90.0;

    // Anti-vacuous: a run where the path silently failed and the walker never
    // moved would satisfy every "is it calm?" assertion below.
    private const float MovingSpeedCm = 20.0;
    private const int32 MinApproachMovingSamples = 5;

    // Last-resort guard ahead of the engine TimeLimit: a wedge in ANY phase must
    // report as a named failure with the slabs unpainted, never as an anonymous
    // TimesUp that leaves nav-null areas splitting the shared PIE world.
    private const float HardDeadlineSec = 34.0;
    private const int32 MaxTeardownPolls = 40;

    // ---- fixture state ----------------------------------------------------
    private FCk_Handle_CrowdAgent _Walker;
    private FCk_Handle_CrowdAgent _Stranger;

    private UCk_NavAreaMarkup_UE _SlabPosY = nullptr;
    private UCk_NavAreaMarkup_UE _SlabNegY = nullptr;

    private float _FloorZ = 0.0;
    private float _EdgeAbsYPos = 0.0;
    private float _EdgeAbsYNeg = 0.0;
    private float _ProbedEdgeAbsY = 0.0;
    private float _SlabProbeY = 0.0;

    private bool _MeshFound = false;
    private bool _SlabsPainted = false;
    private bool _SlabsSealed = false;
    private bool _GapOpen = false;
    private bool _AgentsSpawned = false;
    private bool _Measuring = false;
    private bool _InContact = false;

    // ---- measurement ------------------------------------------------------
    private float _ElapsedSec = 0.0;
    private float _MeasureElapsedSec = 0.0;
    private float _PressElapsedSec = 0.0;
    private int32 _PressSamples = 0;
    private int32 _ApproachMovingSamples = 0;

    private float _PrevBodyYaw = 0.0;
    private float _TotalYawTravelDeg = 0.0;
    private float _PeakAbsDeltaDeg = 0.0;
    private int32 _BodyReversalCount = 0;
    private int32 _PrevBodySign = 0;
    private bool _HasPrevBodySign = false;

    private float _PrevTargetYaw = 0.0;
    private float _PeakTargetDeltaDeg = 0.0;
    private int32 _TargetReversalCount = 0;
    private int32 _PrevTargetSign = 0;
    private bool _HasPrevTargetSign = false;

    // ---- teardown ---------------------------------------------------------
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

        // Kick the navmesh first thing: AutoTests_CkTests_Level ships the
        // fixture but the bake is lazy, and every probe below is synchronous.
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSample"));
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Destroy_Slabs();
    }

    UFUNCTION()
    private void OnSample(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
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
            Begin_Teardown(false, f"HARD DEADLINE at {_ElapsedSec}s (meshFound={_MeshFound}, slabsSealed={_SlabsSealed}, gapOpen={_GapOpen}, spawned={_AgentsSpawned}, measuring={_Measuring}, inContact={_InContact})");
            return;
        }

        if (_Measuring == false && _ElapsedSec >= PrepDeadlineSec)
        {
            Begin_Teardown(false, f"SETUP NEVER COMPLETED within {PrepDeadlineSec}s: meshFound={_MeshFound} slabsPainted={_SlabsPainted} slabsSealed={_SlabsSealed} gapOpen={_GapOpen} agentsSpawned={_AgentsSpawned}. Either the bake never landed, the nav-null slabs never reached the mesh, the 150cm gap did not survive the bake, or the walker's path never resolved - nothing this test exists to measure ever ran.");
            return;
        }

        if (_MeshFound == false)
        {
            Tick_FindMesh(SelfHandle);
            return;
        }

        if (_SlabsPainted == false)
        {
            Paint_Slabs(SelfHandle);
            _SlabsPainted = true;
            return;
        }

        if (_SlabsSealed == false || _GapOpen == false)
        {
            Tick_WaitForSeal(SelfHandle);
            return;
        }

        if (_AgentsSpawned == false)
        {
            Spawn_Agents(SelfHandle);
            _AgentsSpawned = true;
            return;
        }

        if (ck::Is_NOT_Valid(_Walker) || ck::Is_NOT_Valid(_Stranger))
        {
            Begin_Teardown(false, "an agent went invalid mid-run - possible early destroy / lifetime issue");
            return;
        }

        // Ahead of every gate below, so the approach-motion window spans the walker's whole
        // journey rather than the subset of it the phase machine happens to fall through to.
        if (_InContact == false)
        { Sample_ApproachMotion(); }

        if (_Measuring == false)
        {
            Tick_WaitForPath();
            return;
        }

        _MeasureElapsedSec += SampleIntervalSec;

        if (_InContact == false)
        {
            Tick_Approach();
            return;
        }

        Tick_Press();
    }

    // ---- Phase 0: fixture ---------------------------------------------------------------------

    private void Tick_FindMesh(FCk_Handle& InSelf)
    {
        FVector Projected;
        if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector::ZeroVector, 100.0f, Projected, ProbeVerticalExtentUu) == false)
        { return; }   // bake not done yet - keep polling

        _FloorZ = float(Projected.Z);

        if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector(WalkerSpawnX, 0.0, _FloorZ), 100.0f, Projected, ProbeVerticalExtentUu) == false)
        { return; }
        if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector(GoalX, 0.0, _FloorZ), 100.0f, Projected, ProbeVerticalExtentUu) == false)
        { return; }

        // The slabs are sized from the mesh's OWN extent rather than a hardcoded
        // half-extent, so "there is no way around" is a property this run
        // measured rather than one the level is assumed to have.
        if (DoFind_MeshEdgeAlongY(InSelf, 1.0) == false)
        {
            Begin_Teardown(false, f"navmesh +Y edge not found within {MaxProbeUu}uu of the origin - the slabs cannot be sized to foreclose a detour, so this run could not test a plugged gap at all. Test level changed?");
            return;
        }
        _EdgeAbsYPos = _ProbedEdgeAbsY;

        if (DoFind_MeshEdgeAlongY(InSelf, -1.0) == false)
        {
            Begin_Teardown(false, f"navmesh -Y edge not found within {MaxProbeUu}uu of the origin - the slabs cannot be sized to foreclose a detour, so this run could not test a plugged gap at all. Test level changed?");
            return;
        }
        _EdgeAbsYNeg = _ProbedEdgeAbsY;

        // Midway between the gap edge and the mesh edge: inside the +Y slab by
        // construction, and inside the mesh before the slab bakes. That makes it
        // valid both as the seal probe and as the teardown restore probe.
        _SlabProbeY = (GapHalfWidthUu + _EdgeAbsYPos) * 0.5;

        _MeshFound = true;
    }

    private void Paint_Slabs(FCk_Handle& InOwner)
    {
        const auto OuterPos = _EdgeAbsYPos + WallOverrunUu;
        const auto CentrePos = (GapHalfWidthUu + OuterPos) * 0.5;
        const auto HalfPos = (OuterPos - GapHalfWidthUu) * 0.5;

        _SlabPosY = utils_nav_area_markup::Request_Create(InOwner,
            FTransform(FRotator::ZeroRotator, FVector(0.0, CentrePos, _FloorZ), FVector::OneVector),
            FVector(WallHalfX, HalfPos, WallHalfZ),
            UNavArea_Null);

        const auto OuterNeg = _EdgeAbsYNeg + WallOverrunUu;
        const auto CentreNeg = (GapHalfWidthUu + OuterNeg) * 0.5;
        const auto HalfNeg = (OuterNeg - GapHalfWidthUu) * 0.5;

        _SlabNegY = utils_nav_area_markup::Request_Create(InOwner,
            FTransform(FRotator::ZeroRotator, FVector(0.0, -CentreNeg, _FloorZ), FVector::OneVector),
            FVector(WallHalfX, HalfNeg, WallHalfZ),
            UNavArea_Null);
    }

    // The tile rebuild is async, so both halves of the fixture are WAITED ON as
    // conditions rather than budgeted as a delay: the wall must actually be a
    // hole in the mesh, and the gap must actually still be walkable.
    private void Tick_WaitForSeal(FCk_Handle& InSelf)
    {
        FVector Unused;

        if (_SlabsSealed == false)
        {
            const auto StillWalkable = utils_nav::Try_ProjectOntoNavmesh(InSelf,
                FVector(0.0, _SlabProbeY, _FloorZ), SlabProbeHalfExtentUu, Unused, ProbeVerticalExtentUu);
            if (StillWalkable) { return; }
            _SlabsSealed = true;
        }

        _GapOpen = utils_nav::Try_ProjectOntoNavmesh(InSelf,
            FVector(0.0, 0.0, _FloorZ), SlabProbeHalfExtentUu, Unused, ProbeVerticalExtentUu);
    }

    private void Spawn_Agents(FCk_Handle& InOwner)
    {
        // The stranger goes down FIRST so the walker's very first path is planned
        // with it already standing in the gap. It is NEVER commanded anywhere
        // that is what makes it an obstruction rather than a participant.
        _Stranger = Spawn_Agent(InOwner, FVector(0.0, 0.0, _FloorZ + 100.0),
            FRotator::ZeroRotator, n"BlockedGap_Stranger");

        const auto Spawn = FVector(WalkerSpawnX, 0.0, _FloorZ + 100.0);
        const auto Goal = FVector(GoalX, 0.0, _FloorZ);
        _Walker = Spawn_Agent(InOwner, Spawn, (Goal - Spawn).Rotation(), n"BlockedGap_Walker");

        utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    private FCk_Handle_CrowdAgent Spawn_Agent(FCk_Handle& InOwner, FVector InSpawn, FRotator InRot, FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(AgentRadiusUu, AgentHeightUu);

        // A FRESH child entity per agent. utils_crowd_agent::Add composes onto
        // the handle it is given and permits one agent per entity, so a shared
        // owner leaves a crowd of exactly one.
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(InRot, InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
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

    private void Tick_WaitForPath()
    {
        FCk_Handle WalkerEntity = _Walker;
        const auto Status = utils_nav::Get_PathStatus(WalkerEntity);

        if (Status == ECk_Nav_PathStatus::Failed || Status == ECk_Nav_PathStatus::Partial)
        {
            const auto Result = utils_nav::Get_PathResult(WalkerEntity);
            Begin_Teardown(false, f"the walker's path to the far side came back status={Status} (reason={Result.Get_Diagnostics().Get_LastFailReason()}). The 150cm gap is supposed to stay WALKABLE - the stranger standing in it paints a cost disc, not a hole. A non-Ready path means the slabs closed the gap outright, so this run never staged a press.");
            return;
        }

        if (Status != ECk_Nav_PathStatus::Ready) { return; }

        // Only now does the measured clock start: the contact deadline must
        // budget walking time, never the bake, the tile rebuild, or path resolution.
        _MeasureElapsedSec = 0.0;
        _Measuring = true;
    }

    // ---- Approach: get the walker into contact, and prove it walked ---------------------------

    // Counted on EVERY poll from the one after the MoveTo is issued until contact latches, which
    // is why it lives at the top of OnSample and not inside Tick_Approach. Tick_Approach runs only
    // once the path-ready gate has opened, and only on polls that reach the bottom of the phase
    // machine - a strictly smaller window than "the walker was on its way", and small enough that
    // a ~400cm / ~1.9s approach which should show 15+ moving samples measured 4. The guard was
    // therefore one short of its own floor for a reason that had nothing to do with the walker's
    // motion, and would have false-failed a legitimately calm post-fix run.
    private void Sample_ApproachMotion()
    {
        if (DoGet_Speed(_Walker) > MovingSpeedCm)
        { _ApproachMovingSamples += 1; }
    }

    private void Tick_Approach()
    {
        const auto Distance = DoGet_Dist2D(DoGet_Position(_Walker), DoGet_Position(_Stranger));
        if (Distance <= ContactRangeUu)
        {
            _InContact = true;
            _PressElapsedSec = 0.0;
            _PressSamples = 1;
            _PrevBodyYaw = DoGet_BodyYaw();
            _PrevTargetYaw = utils_crowd_agent::Get_TargetYawDegrees(_Walker);
            return;
        }

        if (_MeasureElapsedSec >= ContactDeadlineSec)
        {
            const auto State = utils_crowd_agent::Get_MovementState(_Walker);
            Begin_Teardown(false, f"NEVER MADE CONTACT: {_MeasureElapsedSec}s after its path resolved the walker is still {Distance}uu from the stranger (contact range {ContactRangeUu}uu, state={State}, {_ApproachMovingSamples} samples above {MovingSpeedCm}cm/s). Without contact there is no press, and every calmness assertion below would pass vacuously.");
        }
    }

    // ---- The press window ----------------------------------------------------------------------

    private void Tick_Press()
    {
        _PressElapsedSec += SampleIntervalSec;
        _PressSamples += 1;

        // BODY yaw - the quantity under test. Wrapped delta, never raw
        // subtraction: a 179 -> -179 crossing is a 2-degree turn, not 358.
        const auto BodyYaw = DoGet_BodyYaw();
        const auto BodyDelta = Math::FindDeltaAngleDegrees(_PrevBodyYaw, BodyYaw);
        const auto AbsBodyDelta = Math::Abs(BodyDelta);
        _PrevBodyYaw = BodyYaw;

        _TotalYawTravelDeg += AbsBodyDelta;
        if (AbsBodyDelta > _PeakAbsDeltaDeg) { _PeakAbsDeltaDeg = AbsBodyDelta; }

        if (AbsBodyDelta > NonTrivialDeltaDeg)
        {
            auto Sign = -1;
            if (BodyDelta > 0.0) { Sign = 1; }
            if (_HasPrevBodySign && Sign != _PrevBodySign) { _BodyReversalCount += 1; }
            _PrevBodySign = Sign;
            _HasPrevBodySign = true;
        }

        // TARGET yaw - attribution only. Reported, never gated on: the desired
        // velocity's own oscillation is a separate defect this test does not own.
        const auto TargetYaw = utils_crowd_agent::Get_TargetYawDegrees(_Walker);
        const auto TargetDelta = Math::FindDeltaAngleDegrees(_PrevTargetYaw, TargetYaw);
        const auto AbsTargetDelta = Math::Abs(TargetDelta);
        _PrevTargetYaw = TargetYaw;

        if (AbsTargetDelta > _PeakTargetDeltaDeg) { _PeakTargetDeltaDeg = AbsTargetDelta; }

        if (AbsTargetDelta > NonTrivialDeltaDeg)
        {
            auto Sign = -1;
            if (TargetDelta > 0.0) { Sign = 1; }
            if (_HasPrevTargetSign && Sign != _PrevTargetSign) { _TargetReversalCount += 1; }
            _PrevTargetSign = Sign;
            _HasPrevTargetSign = true;
        }

        if (_PressElapsedSec >= PressWindowSec)
        {
            Report();
            return;
        }

        // The no-progress ladder legitimately ends the press by blocking the
        // move; so does the walker somehow getting through. Either is a valid
        // window end ONLY once enough of a press has been observed to measure.
        const auto Blocked = utils_crowd_agent::Get_IsGoalBlocked(_Walker);
        const auto FailedHold = utils_crowd_agent::Get_IsGoalFailedHold(_Walker);
        const auto Reached = utils_crowd_agent::Get_HasReachedActiveGoal(_Walker);

        if (Blocked == false && FailedHold == false && Reached == false) { return; }

        if (_PressElapsedSec >= MinPressSec && _PressSamples >= MinPressSamples)
        {
            Report();
            return;
        }

        const auto Diagnostic = DoBuild_Diagnostic();
        Begin_Teardown(false, f"PRESS ENDED TOO EARLY: the walker held contact for only {_PressElapsedSec}s / {_PressSamples} samples (need {MinPressSec}s / {MinPressSamples}) before goalBlocked={Blocked} goalFailedHold={FailedHold} reachedGoal={Reached}. {Diagnostic}. A press that short cannot show whether the body stays calm - and a REACHED goal means the plug did not hold, i.e. the stranger was shoved clear of the gap and the fixture stopped testing what it exists for.");
    }

    private void Report()
    {
        const auto Diagnostic = DoBuild_Diagnostic();

        // Log, never Warning: the automation harness escalates any Warning into
        // a test failure, which would fail this test on its own attribution output.
        ck::crowd::Log(f"[CROWD-FACING] press window closed - {Diagnostic}");

        Assert_True(_PressSamples >= MinPressSamples,
            f"only {_PressSamples} press samples were taken (need >= {MinPressSamples}) - the press was too short to say anything about facing stability. {Diagnostic}");

        Assert_True(_ApproachMovingSamples >= MinApproachMovingSamples,
            f"only {_ApproachMovingSamples} approach samples saw the walker above {MovingSpeedCm}cm/s (need >= {MinApproachMovingSamples}) - it never really walked to the gap, so every calmness assertion here would pass vacuously. {Diagnostic}");

        Assert_True(_BodyReversalCount <= ReversalCeiling,
            f"WHIP: the walker's body yaw changed direction {_BodyReversalCount} times while pressing (ceiling {ReversalCeiling}). A pressing agent may settle its facing once or twice; alternating repeatedly means the body is chasing the per-frame desired-velocity heading instead of holding still. {Diagnostic}");

        Assert_True(_TotalYawTravelDeg <= TotalYawTravelCeilingDeg,
            f"WHIP: the walker's body swept {_TotalYawTravelDeg} degrees of total yaw travel while pressing (ceiling {TotalYawTravelCeilingDeg}). It is jammed against a body it cannot pass and is going nowhere - there is no heading it legitimately needs to sweep a quarter turn to find. {Diagnostic}");

        Begin_Teardown(true, "");
    }

    private FString DoBuild_Diagnostic()
    {
        return f"press={_PressElapsedSec}s samples={_PressSamples} | body yaw: reversals={_BodyReversalCount} totalTravel={_TotalYawTravelDeg}deg peakDelta={_PeakAbsDeltaDeg}deg | attribution target yaw: reversals={_TargetReversalCount} peakDelta={_PeakTargetDeltaDeg}deg | approachMovingSamples={_ApproachMovingSamples}";
    }

    // ---- Teardown -------------------------------------------------------------------------------

    private void Begin_Teardown(bool InPassed, const FString& InFailMessage)
    {
        if (_TeardownStarted) { return; }
        _TeardownStarted = true;
        _TeardownPassed = InPassed;
        _TeardownMessage = InFailMessage;
        _TeardownPolls = 0;
        Destroy_Slabs();
    }

    private void Tick_Teardown(FCk_Handle& InSelf)
    {
        _TeardownPolls += 1;

        auto MeshRestored = true;
        if (_MeshFound)
        {
            FVector Restored;
            MeshRestored = utils_nav::Try_ProjectOntoNavmesh(InSelf,
                FVector(0.0, _SlabProbeY, _FloorZ), SlabProbeHalfExtentUu, Restored, ProbeVerticalExtentUu);
        }

        if (MeshRestored == false && _TeardownPolls < MaxTeardownPolls)
        { return; }

        if (_TeardownPassed) { FinishSuccess(); }
        else { FinishFailure(_TeardownMessage); }
    }

    private void Destroy_Slabs()
    {
        if (ck::IsValid(_SlabPosY))
        {
            utils_nav_area_markup::Request_Destroy(_SlabPosY);
            _SlabPosY = nullptr;
        }
        if (ck::IsValid(_SlabNegY))
        {
            utils_nav_area_markup::Request_Destroy(_SlabNegY);
            _SlabNegY = nullptr;
        }
    }

    // ---- Helpers ---------------------------------------------------------------------------------

    // Walks +Y or -Y from the origin until projection fails, then refines. Writes
    // the last walkable |Y| into _ProbedEdgeAbsY. Same coarse/refine shape
    // Crowd_Avoidance_WallSegmentsKeepAgentOnMesh uses for the -X edge.
    private bool DoFind_MeshEdgeAlongY(FCk_Handle& InSelf, float InSign)
    {
        FVector Unused;

        float LastGoodAbsY = 0.0;
        float CoarseFailAbsY = 0.0;
        bool CoarseFailed = false;

        for (float AbsY = CoarseStepUu; AbsY <= MaxProbeUu; AbsY += CoarseStepUu)
        {
            if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector(0.0, InSign * AbsY, _FloorZ), ProbeExtentUu, Unused, ProbeVerticalExtentUu) == false)
            {
                CoarseFailAbsY = AbsY;
                CoarseFailed = true;
                break;
            }
            LastGoodAbsY = AbsY;
        }

        if (CoarseFailed == false)
        { return false; }

        for (float AbsY = LastGoodAbsY + RefineStepUu; AbsY < CoarseFailAbsY; AbsY += RefineStepUu)
        {
            if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector(0.0, InSign * AbsY, _FloorZ), ProbeExtentUu, Unused, ProbeVerticalExtentUu) == false)
            { break; }
            LastGoodAbsY = AbsY;
        }

        _ProbedEdgeAbsY = float(LastGoodAbsY);
        return true;
    }

    private float DoGet_BodyYaw()
    {
        return float(utils_transform::Get_EntityCurrentRotation(
            utils_transform::DoCastChecked(FCk_Handle(_Walker))).Yaw);
    }

    private FVector DoGet_Position(FCk_Handle_CrowdAgent InAgent)
    {
        FCk_Handle Generic = InAgent;
        return utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(Generic));
    }

    private float DoGet_Speed(FCk_Handle_CrowdAgent InAgent)
    {
        FCk_Handle Generic = InAgent;
        return float(utils_velocity::Get_CurrentVelocity(
            utils_velocity::DoCastChecked(Generic)).Size());
    }

    // Planar distance: the bodies are cylinders, so a Z difference must not mask
    // an XY contact.
    private float DoGet_Dist2D(FVector InA, FVector InB)
    {
        return float(FVector(InA.X - InB.X, InA.Y - InB.Y, 0.0).Size());
    }
}

class ACk_AutoTest_Crowd_Facing_CalmWhilePressingBlockedGap_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Facing_CalmWhilePressingBlockedGap;
    default _TimeoutSeconds = 40.0f;

    // Pressing an agent into an impassable plug is the CONDITION UNDER TEST, and
    // the terminal routes out of it are warning-level by design. The automation
    // framework escalates any Warning to a test failure, so the fixture's own
    // deliberate output would fail it. Same hedge, and the same three plain
    // substrings, Crowd_Stall_UnreachableGoalFailsBounded registers - a
    // suppress-all pattern that never fires is not reported as missing, so
    // listing all three costs nothing.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        // FProcessor_CrowdAgent_BlockedRecheck::DoFailMove - the bounded
        // NoProgress ladder running out of re-checks.
        Out.Add("made no progress toward");
        // FProcessor_CrowdAgent_OnPathResolved, Failed branch - a re-path issued
        // by the stall ladder that Recast answers with no path at all.
        Out.Add("(path failed:");
        // FCk_Nav_Algorithm::FindPathSync - start projection can fail on the
        // frame the tiles under the pressed agent are mid-rebuild.
        Out.Add("projection FAILED");
        return Out;
    }
}
