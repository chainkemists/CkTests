// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: A TELEPORTED AGENT RE-PATHS INSTEAD OF WALKING BACK
//
// The off-path tier of FProcessor_CrowdAgent_BlockDetect: an agent more than
// _BlockDetectionOffPathRepathThresholdCm (300cm, XY) from the segment it is
// currently following is re-pathed outright.
//
// Without it, nothing in the pipeline notices that the agent no longer stands
// near the corridor it is walking. Steering keeps aiming at the waypoint the
// installed polyline says is next — so a teleport, a save restore or an
// external shove leaves the agent walking BACK to a corridor it has no reason
// to be on, all the way around, before it finally heads for the goal. A
// displacement spends ONE rung of the shared re-path ladder
// (_BlockDetectionMaxStallRepaths = 2, refunded on progress); this fixture
// drifts exactly once, so a single heal must never escalate to a block.
//
// Shape: the scenario needs a MULTI-WAYPOINT path, otherwise the stale-corridor
// bug is unobservable — a one-segment path aims straight at the goal, and an
// agent teleported anywhere still walks straight at the goal, passing the test
// for the wrong reason. So a nav-null wall is painted FIRST, before the MoveTo,
// spanning y in [-1200, +300] at x=0 (past the south edge of the mesh), leaving a
// gap only at the north end. The agent is spawned at (-600, -600) and sent to
// (+600, -600); Recast has to route it north through the gap, giving corners near
// (+/-95, ~+395).
//
// Once it is steering at one of those gap corners it is teleported to (350, -800) —
// already PAST the wall, on the goal side, far off its corridor:
//   * re-pathed: a straight ~320uu run to the goal, ~1.5s;
//   * stale corridor: back to the north-west corner (~1300uu), through the gap,
//     then down to the goal — ~2600uu, ~11s.
// The arrival deadline is set between the two, and the navigation REQUEST
// REVISION is required to advance right after the teleport so the test names
// the mechanism rather than merely timing the outcome.
//
// SHARED-WORLD HYGIENE: the wall is destroyed before the test reports, the run
// waits for the tiles to come back, and DoEndPlay unpaints it as a backstop for
// the timeout path.
//============================================================================

class UCk_AutoTest_Crowd_OffPath_TeleportRepaths : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 34.0f;

    private const float SpawnX = -600.0;
    private const float SpawnY = -600.0;
    private const float GoalX = 600.0;
    private const float GoalY = -600.0;

    // Centred at y=-450 with a half-extent of 750, the wall spans y in [-1200, +300]:
    // it runs off the south edge of the 2000x2000uu nav volume (so Recast erosion
    // cannot leave a sliver open down there) and stops short of the north edge,
    // leaving a ~700uu gap at y in [300, 1000]. That gap is what forces the dog-leg
    // the stale-corridor bug needs in order to be observable at all.
    private const float WallCentreY = -450.0;
    private const float WallHalfX = 80.0;
    private const float WallHalfY = 750.0;
    private const float WallHalfZ = 300.0;

    // Teleport destination: past the wall, on the goal side, ~320uu from the goal
    // and >1200uu from the corridor the agent was following.
    private const float TeleportX = 350.0;
    private const float TeleportY = -800.0;

    // Off-path drift is evaluated on the _BlockDetectionInterval cadence (0.5s),
    // then the re-path has to round-trip through CkNavigation. 2.5s is several
    // times that and still far under the stale-corridor walk.
    private const float RepathDeadlineSec = 2.5;
    // Direct run is ~1.5s; the stale corridor is ~11s. 6s cannot be reached by
    // walking back, and is not tight enough to flake on the accel ramp.
    private const float ArriveDeadlineSec = 6.0;

    private const float ArrivalToleranceUu = 110.0;
    private const float MinWalkBeforeTeleportUu = 150.0;
    // North of the wall's +300 top edge with margin: a waypoint above this can only be
    // a gap corner, and the goal (y=-600) can never be mistaken for one.
    private const float GapMinY = 200.0;
    // Middle of the open gap (y in [300, 1000]) — where the mesh must still be walkable.
    private const float GapProbeY = 650.0;
    private const float32 WallProbeHalfExtentUu = 20.0f;
    private const float SampleIntervalSec = 0.1;
    // Phase deadlines, each ahead of the global guard so a wedge names its phase.
    private const float WallConfirmDeadlineSec = 14.0;
    private const float WalkStartDeadlineSec = 17.0;
    private const float HardDeadlineSec = 28.0;
    private const int32 MaxTeardownPolls = 40;

    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_Transform _AgentTransform;
    private UCk_NavAreaMarkup_UE _Wall = nullptr;

    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _WallPainted = false;
    private bool _WallConfirmed = false;
    private bool _AgentSpawned = false;

    private bool _Teleported = false;
    private float _TeleportedAtSec = -1.0;
    private int32 _RevisionAtTeleport = 0;
    private bool _RepathObserved = false;
    private FVector _SpawnLocation = FVector::ZeroVector;

    private bool _Reached = false;
    private float _ReachedAtSec = -1.0;
    private float _FinalDistToGoal = -1.0;
    private bool _UnexpectedFailure = false;

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

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

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

        // Last-resort guard, ahead of the engine TimeLimit: a wedge in ANY phase must
        // report as a named failure with the wall unpainted, never as an anonymous
        // TimesUp that leaves a nav-null area splitting the shared PIE world.
        if (_ElapsedSec >= HardDeadlineSec)
        {
            Begin_Teardown(false, f"HARD DEADLINE at {_ElapsedSec}s (meshFound={_MeshFound}, wallConfirmed={_WallConfirmed}, spawned={_AgentSpawned}, teleported={_Teleported}, repathObserved={_RepathObserved}, reached={_Reached})");
            return;
        }

        if (_MeshFound == false)
        {
            FVector Projected;
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector::ZeroVector, 100.0f, Projected, 300.0f) == false)
            { return; }
            _FloorZ = float(Projected.Z);
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector(SpawnX, SpawnY, _FloorZ), 100.0f, Projected, 300.0f) == false)
            { return; }
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector(GoalX, GoalY, _FloorZ), 100.0f, Projected, 300.0f) == false)
            { return; }

            _MeshFound = true;
            return;
        }

        if (_WallPainted == false)
        {
            Paint_Wall(SelfHandle);
            _WallPainted = true;
            return;
        }

        if (_WallConfirmed == false)
        {
            // Only plan once the hole is genuinely on the mesh: a MoveTo issued
            // against tiles that have not rebuilt yet would return the straight
            // one-segment path this scenario is built to avoid.
            FVector Probe;
            const auto WallIsHole = utils_nav::Try_ProjectOntoNavmesh(SelfHandle,
                FVector(0.0, WallCentreY, _FloorZ), WallProbeHalfExtentUu, Probe, 300.0f) == false;
            const auto GapIsOpen = utils_nav::Try_ProjectOntoNavmesh(SelfHandle,
                FVector(0.0, GapProbeY, _FloorZ), WallProbeHalfExtentUu, Probe, 300.0f);
            if (WallIsHole == false || GapIsOpen == false)
            {
                if (_ElapsedSec >= WallConfirmDeadlineSec)
                {
                    Begin_Teardown(false, f"FIXTURE NOT READY: the nav-null wall never showed up on the rebuilt navmesh (hole={WallIsHole}, gap={GapIsOpen}) after {_ElapsedSec}s. Without it the path is a single straight segment and the stale-corridor bug is unobservable.");
                }
                return;
            }

            _WallConfirmed = true;
            return;
        }

        if (_AgentSpawned == false)
        {
            SpawnWalker(SelfHandle);
            _AgentSpawned = true;
            return;
        }

        if (ck::Is_NOT_Valid(_Agent))
        {
            Begin_Teardown(false, "the walker went invalid mid-run");
            return;
        }

        if (_UnexpectedFailure)
        {
            Begin_Teardown(false, f"the walker reported OnGoalFailed for a goal that was reachable from its teleport destination the whole time (teleported={_Teleported}, t={_ElapsedSec}s)");
            return;
        }

        if (_Teleported == false)
        {
            Tick_AwaitTeleportWindow(SelfHandle);
            return;
        }

        if (_RepathObserved == false)
        {
            const auto Revision = utils_nav::Get_PathResult(_Agent).Get_RequestRevision();
            if (Revision > _RevisionAtTeleport)
            {
                _RepathObserved = true;
            }
            else if (_ElapsedSec >= _TeleportedAtSec + RepathDeadlineSec)
            {
                const auto Pos = utils_transform::Get_EntityCurrentLocation(
                    utils_transform::DoCastChecked(FCk_Handle(_Agent)));
                Assert_True(false,
                    f"NO RE-PATH: {RepathDeadlineSec}s after being displaced far off its corridor the agent's navigation request revision is still {Revision} (was {_RevisionAtTeleport} at teleport, position={Pos}). Steering is still chasing waypoints on a polyline the agent no longer stands near.");
                _RepathObserved = true;   // report once; let the arrival check add its own evidence
            }
        }

        if (_Reached)
        {
            const auto SinceTeleport = _ReachedAtSec - _TeleportedAtSec;

            Assert_True(_FinalDistToGoal >= 0.0 && _FinalDistToGoal <= ArrivalToleranceUu,
                f"the walker stopped within its arrival contract of the goal (distance={_FinalDistToGoal}, tolerance={ArrivalToleranceUu})");

            Assert_True(SinceTeleport <= ArriveDeadlineSec,
                f"the walker took the DIRECT route from where it was displaced to: it arrived {SinceTeleport}s after the teleport (limit {ArriveDeadlineSec}s). The direct run is ~320uu (~1.5s); walking back to the stale corridor, up through the gap and down again is ~2600uu (~11s), so anything over the limit means it followed the polyline it was no longer standing on.");

            Begin_Teardown(true, "");
            return;
        }

        if (_ElapsedSec >= _TeleportedAtSec + ArriveDeadlineSec)
        {
            const auto Pos = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_Agent)));
            const auto DistToGoal = float((Pos - FVector(GoalX, GoalY, _FloorZ)).Size2D());
            const auto SinceTeleport = _ElapsedSec - _TeleportedAtSec;
            const auto State = utils_crowd_agent::Get_MovementState(_Agent);
            Begin_Teardown(false, f"STALE CORRIDOR: {SinceTeleport}s after the teleport the walker is still {DistToGoal}uu from a goal ~320uu away (position={Pos}, state={State}, repathObserved={_RepathObserved}). It is walking the polyline it was displaced OFF instead of planning from where it actually stands.");
        }
    }

    // The teleport is only meaningful once the agent is genuinely committed to a
    // MULTI-corner corridor and has left its spawn. Both are preconditions, not
    // waits: if either never holds, the scenario proves nothing and says so.
    private void Tick_AwaitTeleportWindow(FCk_Handle& InSelf)
    {
        if (utils_nav::Get_PathStatus(_Agent) != ECk_Nav_PathStatus::Ready) { return; }
        if (utils_crowd_agent::Get_MovementState(_Agent) != ECk_CrowdAgent_MovementState::Walking) { return; }

        const auto Pos = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Agent)));
        const auto Walked = float((Pos - _SpawnLocation).Size2D());
        if (Walked < MinWalkBeforeTeleportUu)
        {
            if (_ElapsedSec >= WalkStartDeadlineSec)
            {
                Begin_Teardown(false, f"the walker never got moving: only {Walked}uu from its spawn after {_ElapsedSec}s");
            }
            return;
        }

        const auto Result = utils_nav::Get_PathResult(_Agent);
        auto Waypoints = Result.Get_Waypoints();
        if (Waypoints.Num() < 2)
        {
            const auto Count = Waypoints.Num();
            Begin_Teardown(false, f"INCONCLUSIVE SCENARIO: the installed path has only {Count} waypoint(s), so it is effectively a straight run at the goal. A teleported agent aims at the goal either way and the stale-corridor bug cannot be observed. The nav-null wall did not bend the route.");
            return;
        }

        // The corridor must genuinely run north through the gap, otherwise the
        // teleport destination is not meaningfully "off" it.
        auto ReachesGap = false;
        for (auto Waypoint : Waypoints)
        {
            if (Waypoint.Y > GapMinY) { ReachesGap = true; }
        }
        if (ReachesGap == false)
        {
            const auto Dump = Dump_Polyline(Waypoints);
            Begin_Teardown(false, f"INCONCLUSIVE SCENARIO: the installed path never routes north of the wall to reach the gap, so it did not go around it. wps={Dump}");
            return;
        }

        // THE precondition this scenario rests on: the corridor the agent is CURRENTLY
        // steering along must lead somewhere OTHER than the goal, so that following it
        // after the displacement is visibly wrong. Concretely — the waypoint it is
        // aiming at right now has to be a gap corner north of the wall, while the goal
        // is south of it.
        //
        // This is a WAIT, not an assertion, and deliberately not a check on waypoint
        // INDEX. Both CkNav FindPathSync call sites pass
        // `/*InAgentRadiusForFirstSkip*/ 0.0f` (CkNav_Processor.cpp:382 and :400), which
        // disables ExtractWaypoints' skip-first pass entirely — so Waypoints[0] is always
        // the agent's own PROJECTED START, not a corner, and Steering retires it within a
        // frame or two of the agent moving. Index 0 therefore holds only for the first
        // instant of any walk; an earlier revision of this test asserted it and failed
        // with "expected 0, got 1". Aiming at a north corner is the property that
        // actually matters, and it is true regardless of how the list is numbered.
        const auto TargetIndex = Math::Clamp(
            utils_crowd_agent::Get_CurrentWaypointIndex(_Agent), 0, Waypoints.Num() - 1);
        const auto TargetWaypoint = Waypoints[TargetIndex];
        if (TargetWaypoint.Y <= GapMinY)
        {
            if (_ElapsedSec >= WalkStartDeadlineSec)
            {
                const auto Dump = Dump_Polyline(Waypoints);
                Begin_Teardown(false, f"INCONCLUSIVE SCENARIO: the walker never steered at a gap corner — after {_ElapsedSec}s it is aiming at waypoint {TargetIndex} ({TargetWaypoint}), which is south of the wall like the goal is. Displacing it there would leave a stale corridor that happens to point AT the goal, so the test could not tell a re-path from blindly following the old polyline.");
            }
            return;
        }

        _RevisionAtTeleport = Result.Get_RequestRevision();
        Do_Teleport(InSelf);
        _Teleported = true;
        _TeleportedAtSec = _ElapsedSec;
    }

    private void Do_Teleport(FCk_Handle& InSelf)
    {
        auto Destination = FVector(TeleportX, TeleportY, _FloorZ + 100.0);

        // Snap to the mesh so the displacement lands somewhere the agent could
        // legitimately have been shoved to — an off-mesh drop would be testing
        // recovery from a different fault.
        FVector Snapped;
        if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector(TeleportX, TeleportY, _FloorZ), 100.0f, Snapped, 300.0f))
        { Destination = FVector(Snapped.X, Snapped.Y, Snapped.Z + 100.0); }

        const auto Current = utils_transform::Get_EntityCurrentTransform(_AgentTransform);

        // Deliberately NOT preceded by Request_Stop: the agent must keep the move
        // it was given. Cancelling it first would hide the defect — the point is
        // that an ACTIVE move survives displacement by re-planning, not by being
        // re-issued from outside.
        utils_transform::Request_SetTransform(_AgentTransform,
            FCk_Request_Transform_SetTransform(
                FTransform(Current.GetRotation(), Destination, Current.GetScale3D())));
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        if (_Reached) { return; }

        _Reached = true;
        _ReachedAtSec = _ElapsedSec;
        const auto Pos = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(InAgent)));
        _FinalDistToGoal = float((Pos - FVector(GoalX, GoalY, _FloorZ)).Size2D());
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        _UnexpectedFailure = true;
    }

    UFUNCTION()
    private void OnGoalBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        if (IsFinished()) { return; }

        // Nothing obstructs this agent — the route from its teleport destination to
        // the goal is open floor. A block here means the displacement was mistaken
        // for a stall, which is exactly the distinction the off-path branch draws.
        Assert_True(false,
            f"DISPLACEMENT MISREAD AS A STALL: OnGoalBlocked fired (reason={InInfo.Get_Reason()}) for an agent whose goal was open floor. One displacement must heal with a re-path, not escalate to a block: the off-path heal spends one of 2 ladder rungs and this fixture drifts exactly once.");
    }

    private FString Dump_Polyline(const TArray<FVector>& InWaypoints)
    {
        auto Dump = FString("");
        for (auto Waypoint : InWaypoints)
        { Dump += f"({Math::RoundToInt(float32(Waypoint.X))},{Math::RoundToInt(float32(Waypoint.Y))}) "; }
        return Dump;
    }

    private void SpawnWalker(FCk_Handle& InOwner)
    {
        _SpawnLocation = FVector(SpawnX, SpawnY, _FloorZ + 100.0);
        const auto Goal = FVector(GoalX, GoalY, _FloorZ);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(n"OffPathTeleport_Walker");

        const auto Rot = (Goal - _SpawnLocation).Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(Rot, _SpawnLocation, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        _AgentTransform = AgentTransform;
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
        _Wall = utils_nav_area_markup::Request_Create(InOwner,
            FTransform(FRotator::ZeroRotator, FVector(0.0, WallCentreY, _FloorZ), FVector::OneVector),
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

    private void Tick_Teardown(FCk_Handle& InSelf)
    {
        _TeardownPolls += 1;

        auto MeshRestored = true;
        if (_MeshFound)
        {
            FVector Restored;
            MeshRestored = utils_nav::Try_ProjectOntoNavmesh(InSelf,
                FVector(0.0, WallCentreY, _FloorZ), WallProbeHalfExtentUu, Restored, 300.0f);
        }

        if (MeshRestored == false && _TeardownPolls < MaxTeardownPolls)
        { return; }

        if (_TeardownPassed) { FinishSuccess(); }
        else { FinishFailure(_TeardownMessage); }
    }
}

class ACk_AutoTest_Crowd_OffPath_TeleportRepaths_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_OffPath_TeleportRepaths;
    default _TimeoutSeconds = 34.0f;

    // The MoveTo is issued only after the wall is confirmed on the mesh, so the
    // route is planned against a settled navmesh and no deliberate failure output
    // is expected. One exception is possible and benign: the frame the agent is
    // teleported, a start projection can land mid-rebuild.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("projection FAILED");
        return Out;
    }
}
