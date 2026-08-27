// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A STALLED WALKER RE-PATHS AROUND A LATE OBSTACLE
//
// The no-progress tier of FProcessor_CrowdAgent_BlockDetect: a Recast polyline
// is FROZEN at plan time, so an obstacle that appears after the path installs
// is invisible to the agent walking it. Nothing else in the pipeline notices
// StationaryMarkup/PathRefresh only react to *agent* cost discs, and the
// installed nav result stays Ready. Without the stall watchdog the agent walks
// into the new hole, is held there by ConstrainToNavmesh, and presses forever.
//
// Shape: a walker is sent from x=-700 to x=+700 across open mesh. The instant
// its FIRST path is installed and it is Walking, a NAV-NULL wall (UNavArea_Null
// via UCk_NavAreaMarkup_UE - a hole, not a cost disc) is painted across the
// corridor at x=0 spanning |y| <= 500. The nav volume reaches |y| = 1000, so
// ~500uu of open mesh survives on each side: an alternate route EXISTS. The
// walker must still arrive.
//
// The wall face is perpendicular to the walker's heading, so there is no
// tangential component for ConstrainToNavmesh's surface walk to convert into a
// slide - the agent stops dead and its REMAINING PATH DISTANCE stops improving.
// That is exactly what the windowed-minimum detector measures.
//
// Two assertions, not one. "Reached the goal" alone would also pass if the
// agent had never been obstructed at all, so the test additionally requires the
// navigation REQUEST REVISION to advance after the wall was painted: the only
// thing that can advance it here is a re-path issued by BlockDetect's stall
// ladder (or BlockedRecheck's resume). No stationary agents exist in this
// fixture, so PathRefresh cannot be the one that moved it.
//
// SHARED-WORLD HYGIENE: an unpainted nav-null area left behind would split the
// navmesh for every later crowd test. The wall is destroyed before the test
// reports, the run waits for the tiles to come back, and DoEndPlay unpaints it
// again as a backstop for the timeout path.
//============================================================================

class UCk_AutoTest_Crowd_Stall_RepathsAroundLateObstacle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private const float SpawnX = -700.0;
    private const float GoalX = 700.0;

    // 160uu thick across the corridor; |y| <= 500 leaves ~500uu of open mesh on
    // each side of the 2000x2000uu nav volume for the detour to use.
    private const float WallHalfX = 80.0;
    private const float WallHalfY = 500.0;
    private const float WallHalfZ = 300.0;

    // Small enough that a successful projection at the wall centre means the
    // hole is genuinely gone (the wall is 160uu thick, so a 100uu probe would
    // snap to mesh just outside it and report a false "restored").
    private const float32 WallProbeHalfExtentUu = 20.0f;

    private const float SampleIntervalSec = 0.1;
    private const float ArrivalToleranceUu = 110.0;

    // approach (620uu ~= 2.6s + ramp) + one no-progress window (3s) + the detour
    // (~1550uu ~= 6.5s) + async tile rebuild slack.
    private const float ArriveDeadlineSec = 22.0;
    // Last-resort guard, ahead of the engine TimeLimit, so a wedge in ANY phase
    // reports as a named failure with the wall unpainted rather than arriving as
    // an anonymous TimesUp with a nav-null area still splitting the shared world.
    private const float HardDeadlineSec = 25.0;
    private const int32 MaxTeardownPolls = 40;

    private FCk_Handle_CrowdAgent _Agent;
    private UCk_NavAreaMarkup_UE _Wall = nullptr;

    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _WallPainted = false;

    private int32 _RevisionAtPaint = 0;
    private int32 _MaxRevisionSeen = 0;

    private bool _Reached = false;
    private bool _UnexpectedFailure = false;
    private int32 _BlockedCount = 0;
    private float _ElapsedSec = 0.0;
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

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    // The nav-null area is a WORLD-scoped side effect with no owner-driven
    // lifetime, so it has to come down on every exit path - including the one
    // where the engine TimeLimit kills the test before OnPoll can react.
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
            Begin_Teardown(false, f"HARD DEADLINE at {_ElapsedSec}s (meshFound={_MeshFound}, wallPainted={_WallPainted}, reached={_Reached}, blocks={_BlockedCount})");
            return;
        }

        if (_MeshFound == false)
        {
            // Gate on the WHOLE corridor, not just the origin: the walker's first
            // FindPath must resolve immediately. CkNav defers a request whose start
            // tile isn't baked, and a deferred first path could resolve AFTER the
            // wall paints - planning around it and proving nothing.
            FVector Projected;
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector::ZeroVector, 100.0f, Projected, 300.0f) == false)
            { return; }
            _FloorZ = float(Projected.Z);
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector(SpawnX, 0.0, _FloorZ), 100.0f, Projected, 300.0f) == false)
            { return; }
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector(GoalX, 0.0, _FloorZ), 100.0f, Projected, 300.0f) == false)
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
            // Paint only once the FIRST path is installed and the agent is actually
            // Walking: the whole point is a frozen polyline that predates the wall.
            if (utils_nav::Get_PathStatus(_Agent) != ECk_Nav_PathStatus::Ready) { return; }
            if (utils_crowd_agent::Get_MovementState(_Agent) != ECk_CrowdAgent_MovementState::Walking) { return; }

            _RevisionAtPaint = utils_nav::Get_PathResult(_Agent).Get_RequestRevision();
            _MaxRevisionSeen = _RevisionAtPaint;
            Paint_Wall(SelfHandle);
            _WallPainted = true;
            return;
        }

        const auto Revision = utils_nav::Get_PathResult(_Agent).Get_RequestRevision();
        if (Revision > _MaxRevisionSeen) { _MaxRevisionSeen = Revision; }

        if (_UnexpectedFailure)
        {
            const auto Rev = _MaxRevisionSeen;
            const auto Blocks = _BlockedCount;
            Begin_Teardown(false, f"the walker reported OnGoalFailed even though an alternate route around the wall existed the whole time (revision {Rev} vs {_RevisionAtPaint} at paint, blocks={Blocks}). The stall ladder either never re-pathed, or re-pathed against a mesh that had not finished rebuilding and then gave up.");
            return;
        }

        if (_Reached)
        {
            Assert_True(_FinalDistToGoal >= 0.0 && _FinalDistToGoal <= ArrivalToleranceUu,
                f"the walker stopped within its arrival contract of the goal (distance={_FinalDistToGoal}, tolerance={ArrivalToleranceUu})");

            // Reaching the goal is not by itself evidence the stall tier engaged
            // it would also hold if the wall had never obstructed the walker. The
            // only producer of a new navigation request in this fixture is
            // BlockDetect's stall/off-path re-path or BlockedRecheck's resume.
            Assert_True(_MaxRevisionSeen > _RevisionAtPaint,
                f"the walker RE-PATHED after the obstacle appeared: navigation request revision advanced past the one installed before the wall was painted (at paint={_RevisionAtPaint}, max seen={_MaxRevisionSeen}). Without an advance the agent reached the goal on its ORIGINAL frozen polyline, so the fixture never actually obstructed it and the test proves nothing.");

            Begin_Teardown(true, "");
            return;
        }

        if (_ElapsedSec >= ArriveDeadlineSec)
        {
            const auto Pos = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Agent)));
            const auto DistToGoal = float((Pos - FVector(GoalX, 0.0, _FloorZ)).Size2D());
            const auto Rev = _MaxRevisionSeen;
            const auto Blocks = _BlockedCount;
            const auto State = utils_crowd_agent::Get_MovementState(_Agent);
            Begin_Teardown(false, f"NEVER ARRIVED: the walker was still {DistToGoal}uu from its goal at t={_ElapsedSec}s (state={State}, revision {Rev} vs {_RevisionAtPaint} at paint, blocks={Blocks}). A frozen path that walks into a hole must be noticed by the no-progress detector and re-planned around it.");
        }
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        if (_Reached) { return; }

        _Reached = true;
        const auto Pos = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(InAgent)));
        _FinalDistToGoal = float((Pos - FVector(GoalX, 0.0, _FloorZ)).Size2D());
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        _UnexpectedFailure = true;
    }

    // A block is NOT a failure here: if a stall re-path lands while the tiles under
    // the wall are still rebuilding, the ladder can legitimately spend its budget and
    // block before BlockedRecheck resumes it onto a good detour. What must not happen
    // is the move ending - that is OnGoalFailed's job and it is asserted above.
    UFUNCTION()
    private void OnGoalBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        if (IsFinished()) { return; }
        _BlockedCount += 1;
    }

    private void SpawnWalker(FCk_Handle& InOwner)
    {
        const auto Spawn = FVector(SpawnX, 0.0, _FloorZ + 100.0);
        const auto Goal = FVector(GoalX, 0.0, _FloorZ);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(n"StallRepath_Walker");

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

    private void Paint_Wall(FCk_Handle& InOwner)
    {
        // UNavArea_Null is a HOLE, not a toll: a cost disc (what stationary agents
        // paint) would leave the corridor traversable and the walker would simply
        // pay to cross it, exercising nothing.
        _Wall = utils_nav_area_markup::Request_Create(InOwner,
            FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, _FloorZ), FVector::OneVector),
            FVector(WallHalfX, WallHalfY, WallHalfZ),
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

    // Unregistering the markup schedules an async tile rebuild. Handing the shared PIE
    // world to the next crowd test with a half-restored navmesh is the same class of
    // contamination as leaking an entity, so wait for the hole to close - bounded,
    // because the unregister has already happened and the rebuild completes regardless.
    private void Tick_Teardown(FCk_Handle& InSelf)
    {
        _TeardownPolls += 1;

        auto MeshRestored = true;
        if (_MeshFound)
        {
            FVector Restored;
            MeshRestored = utils_nav::Try_ProjectOntoNavmesh(InSelf,
                FVector(0.0, 0.0, _FloorZ), WallProbeHalfExtentUu, Restored, 300.0f);
        }

        if (MeshRestored == false && _TeardownPolls < MaxTeardownPolls)
        { return; }

        if (_TeardownPassed) { FinishSuccess(); }
        else { FinishFailure(_TeardownMessage); }
    }
}

class ACk_AutoTest_Crowd_Stall_RepathsAroundLateObstacle_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Stall_RepathsAroundLateObstacle;
    default _TimeoutSeconds = 30.0f;
}
