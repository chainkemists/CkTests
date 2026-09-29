// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: EVERY EPISODE END RELEASES THE SIDEWALK ROUTE
//============================================================================
//
// The sibling of Stop_ReleasesSidewalkRoute, for the episode ends that are NOT
// a caller's Stop. A PathNetwork follower keeps its corridor after the walk is
// over, and a corridor still carrying a Ready answer at the CURRENT request
// revision is two live bugs at once:
//
//   * OnRouteResolved logs "dropped a current-revision PathNetwork route ...
//     its episode ended without releasing the query" EVERY FRAME for the life
//     of the agent (one NPC in the field: 55,835 lines over 22 minutes);
//   * InvalidateOnRebuild re-plans it on every network epoch change, spending
//     the per-frame route budget on an agent that is not going anywhere.
//
// One class per way an episode ends without a Stop:
//
//   (a) ARRIVAL                    - OnGoalReached.
//   (b) FailMove BLOCKED POLICY    - a stall escalates to a block, and the
//                                    FailMove policy turns it into
//                                    OnGoalFailed(BlockedFailMovePolicy).
//   (c) NoProgress RETRIES SPENT   - the default HoldAndRetry policy holds,
//                                    resumes, re-wedges, and finally reports
//                                    OnGoalFailed(NoProgressRetriesExhausted).
//                                    This case also runs the hold -> resume
//                                    path three times, so a release on the
//                                    HOLD that broke the resume would show up
//                                    here as a missing or wrong terminal.
//
// HOW (b) AND (c) STALL. The agent walks at MaxSpeed 1 cm/s. The no-progress
// detector needs a 30 cm improvement inside a 3 s window, so a 1 cm/s walker
// genuinely makes no progress on every window - the ladder, the block and the
// retries all run exactly as they do for a wedged NPC, with no geometry to
// stage and nothing timing-dependent to race. A painted wall does not work for
// a sidewalk route: the follower compiles its corridor onto the navmesh, so a
// hole across the ribbon makes the ROUTE fail and fall back to CkNavigation,
// and the episode never reaches the PathNetwork terminal under test. (A forced
// sideways drift reaches the same DoBlock through the off-path tier, but needs
// three displacements each landing inside a one-sample window before progress
// refunds the ladder - a race, where the slow walker is deterministic.)
//
// WHAT IS ASSERTED, about 60 frames after the terminal:
//
//   1. the follower's own route reads None - released, not parked Ready;
//   2. the body stays put over a 2 s window (a released route must not
//      re-install and start the agent walking again);
//   3. the waypoint cursor does not move over that window;
//   4. a network epoch bump (a Rebuild with the SAME ribbons) re-plans
//      NOTHING for this agent - no OnRouteReady, and the route never leaves
//      None.
//
// Plus the contracts the release must not disturb: the terminal signal fired
// exactly once and the other one never, with the reason this case stages.
// A Display line reports every measured value so a green run still says what
// it saw.
//============================================================================

class UCk_AutoTest_Crowd_EpisodeEnd_ReleasesSidewalkRoute : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    // Which episode end this class stages. 0 = arrival, 1 = FailMove policy, 2 = NoProgress retries.
    UPROPERTY(EditAnywhere, BlueprintReadOnly, meta = (AllowPrivateAccess = "true"))
    int32 _Case = 0;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, meta = (AllowPrivateAccess = "true"))
    float _TerminalDeadlineSec = 20.0f;

    private const int32 CaseArrival = 0;
    private const int32 CaseFailMove = 1;
    private const int32 CaseNoProgress = 2;

    private const FVector Spawn = FVector(-300.0, 0.0, 0.0);
    private const FVector Goal = FVector(300.0, 0.0, 0.0);
    private const float WalkSpeed = 60.0f;
    // Under the 30 cm per 3 s progress epsilon on every window, so each one reads as a stall.
    private const float StallSpeed = 1.0f;
    private const int32 SettleAfterTerminalFrames = 60;
    private const float StaticWindowSec = 2.0f;
    private const float MaxStaticDriftUu = 1.0;
    private const int32 SettleAfterEpochBumpFrames = 60;

    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_PathNetworkFollower _Follower;
    private FCk_Handle_PathNetwork _Network;
    private TArray<FCk_PathNetwork_Ribbon> _Ribbons;

    private int32 _GoalReachedCount = 0;
    private int32 _GoalFailedCount = 0;
    private int32 _GoalBlockedCount = 0;
    private ECk_CrowdAgent_GoalFailReason _LastFailReason = ECk_CrowdAgent_GoalFailReason::PathFailed;
    private int32 _RouteReadyCount = 0;
    private int32 _RouteReadyCountAtBump = 0;

    private FVector _LocationAtRelease = FVector::ZeroVector;
    private int32 _WaypointIndexAtRelease = 0;
    private int32 _EpochBeforeBump = 0;

    private FString Get_CaseName() const
    {
        if (_Case == CaseFailMove) { return "FailMovePolicy"; }
        if (_Case == CaseNoProgress) { return "NoProgressRetriesExhausted"; }
        return "Arrival";
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step(           "compose a sidewalk-following agent and route it", n"Step_Arrange");
        Add_Step_WaitUntil( "the episode reaches its terminal",                n"Check_Terminal",
                            1000000, _TerminalDeadlineSec);
        Add_Step_WaitFrames("let the terminal's release drain",                SettleAfterTerminalFrames);
        Add_Step(           "the follower's own route is released",           n"Step_AssertRouteReleased");
        Add_Step_WaitSeconds("the released agent is left alone",              StaticWindowSec);
        Add_Step(           "the body and the waypoint cursor stayed put",     n"Step_AssertStatic");
        Add_Step(           "bump the network epoch with the same ribbons",    n"Step_BumpEpoch");
        Add_Step_WaitUntil( "the network rebuilt at a newer epoch",            n"Check_EpochAdvanced");
        Add_Step_WaitFrames("give an invalidation replan every chance to run", SettleAfterEpochBumpFrames);
        Add_Step(           "the epoch bump re-planned nothing for this agent", n"Step_AssertNoReplan");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        LocalHandle.Set_DebugName(FName(f"EpisodeEnd_{Get_CaseName()}_Agent"));
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto Points = TArray<FCk_PathNetwork_RibbonPoint>();
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-400.0, 0.0, 0.0), 100.0));
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 0.0, 0.0), 100.0));
        _Ribbons.Reset();
        _Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        _Network = utils_path_network::Add(LocalHandle, FCk_Fragment_PathNetwork_ParamsData(_Ribbons));

        auto AgentTransform = utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        AgentParams.Set_MaxSpeed(_Case == CaseArrival ? WalkSpeed : StallSpeed);
        if (_Case == CaseFailMove)
        { AgentParams.Set_BlockedPolicy(ECk_CrowdAgent_BlockedPolicy::FailMove); }
        _Agent = utils_crowd_agent::Add(AgentTransform, AgentParams);

        utils_velocity::Add(LocalHandle,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(LocalHandle,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(LocalHandle);

        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        _Follower = utils_path_network_follower::Add(LocalHandle, FollowerParams);

        utils_path_network_follower::BindTo_OnRouteReady(_Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(this, n"OnRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
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

    UFUNCTION()
    private void OnRouteReady(FCk_Handle_PathNetworkFollower InFollower, FCk_PathNetwork_RouteResult InResult)
    { ++_RouteReadyCount; }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    { ++_GoalReachedCount; }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        ++_GoalFailedCount;
        _LastFailReason = InInfo.Get_Reason();
    }

    UFUNCTION()
    private void OnGoalBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    { ++_GoalBlockedCount; }

    UFUNCTION()
    private void Check_Terminal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_GoalReachedCount + _GoalFailedCount > 0);
    }

    private FVector Get_AgentLocation() const
    {
        return utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Agent)));
    }

    UFUNCTION()
    private void Step_AssertRouteReleased(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Route = utils_path_network_follower::Get_RouteResult(_Follower);
        const auto RouteStatus = Route.Get_Status();
        const auto ActiveRevision = utils_nav::Get_PathResult(_Agent).Get_RequestRevision();

        ck::crowd::Display(f"[EPISODEEND] case={Get_CaseName()} terminal: reached={_GoalReachedCount} failed={_GoalFailedCount} failReason={_LastFailReason} blocked={_GoalBlockedCount} routeReadyCount={_RouteReadyCount} route={RouteStatus} routeRevision={Route.Get_RequestRevision()} navSlotRevision={ActiveRevision} state={utils_crowd_agent::Get_MovementState(_Agent)} location={Get_AgentLocation()}");

        // The route must have come from the sidewalk at least once, or the terminal below is not
        // the PathNetwork episode end this test exists for.
        Assert_True(_RouteReadyCount > 0,
            f"[{Get_CaseName()}] the follower never produced a Ready route, so this episode never ran on the sidewalk network and its end proves nothing about releasing one");

        if (_Case == CaseArrival)
        {
            Assert_True(_GoalReachedCount == 1 && _GoalFailedCount == 0,
                f"[{Get_CaseName()}] expected exactly one OnGoalReached and no OnGoalFailed, got reached={_GoalReachedCount} failed={_GoalFailedCount}");
        }
        else
        {
            const auto ExpectedReason = _Case == CaseFailMove
                ? ECk_CrowdAgent_GoalFailReason::BlockedFailMovePolicy
                : ECk_CrowdAgent_GoalFailReason::NoProgressRetriesExhausted;
            Assert_True(_GoalFailedCount == 1 && _GoalReachedCount == 0,
                f"[{Get_CaseName()}] expected exactly one OnGoalFailed and no OnGoalReached, got failed={_GoalFailedCount} reached={_GoalReachedCount}");
            Assert_True(_LastFailReason == ExpectedReason,
                f"[{Get_CaseName()}] OnGoalFailed carried reason {_LastFailReason}, expected {ExpectedReason} - the staging reached a different terminal than the one under test");
        }

        Assert_True(RouteStatus == ECk_PathNetwork_RouteStatus::None,
            f"[{Get_CaseName()}] {SettleAfterTerminalFrames} frames after the episode ended the follower still reports its route as {RouteStatus} (route revision {Route.Get_RequestRevision()}, agent revision {ActiveRevision}). The episode ended without releasing the query it acquired: a current-revision Ready route logs a 'dropped' line every frame and is re-planned on every network epoch change");

        _LocationAtRelease = Get_AgentLocation();
        _WaypointIndexAtRelease = utils_crowd_agent::Get_CurrentWaypointIndex(_Agent);
    }

    UFUNCTION()
    private void Step_AssertStatic(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Drift = float((Get_AgentLocation() - _LocationAtRelease).Size());
        const auto WaypointIndex = utils_crowd_agent::Get_CurrentWaypointIndex(_Agent);

        ck::crowd::Display(f"[EPISODEEND] case={Get_CaseName()} static window: drift={Drift} waypointIndex {_WaypointIndexAtRelease} -> {WaypointIndex} state={utils_crowd_agent::Get_MovementState(_Agent)}");

        Assert_True(Drift <= MaxStaticDriftUu,
            f"[{Get_CaseName()}] the agent moved {Drift}uu in the {StaticWindowSec}s after its episode ended (ceiling {MaxStaticDriftUu}uu)");
        Assert_True(WaypointIndex == _WaypointIndexAtRelease,
            f"[{Get_CaseName()}] the waypoint cursor moved from {_WaypointIndexAtRelease} to {WaypointIndex} after the episode ended");
    }

    UFUNCTION()
    private void Step_BumpEpoch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _EpochBeforeBump = utils_path_network::Get_BuildEpoch(_Network);
        _RouteReadyCountAtBump = _RouteReadyCount;
        utils_path_network::Request_Rebuild(_Network, FCk_Request_PathNetwork_Rebuild(_Ribbons));
    }

    UFUNCTION()
    private void Check_EpochAdvanced(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_path_network::Get_BuildEpoch(_Network) > _EpochBeforeBump);
    }

    UFUNCTION()
    private void Step_AssertNoReplan(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto ReplansAfterBump = _RouteReadyCount - _RouteReadyCountAtBump;
        const auto RouteStatus = utils_path_network_follower::Get_RouteResult(_Follower).Get_Status();

        ck::crowd::Display(f"[EPISODEEND] case={Get_CaseName()} epoch bump: epoch {_EpochBeforeBump} -> {utils_path_network::Get_BuildEpoch(_Network)} replans={ReplansAfterBump} route={RouteStatus}");

        Assert_True(ReplansAfterBump == 0,
            f"[{Get_CaseName()}] the network epoch bump re-planned this agent's route {ReplansAfterBump} time(s) although its episode had ended - route budget spent on an agent that is not going anywhere");
        Assert_True(RouteStatus == ECk_PathNetwork_RouteStatus::None,
            f"[{Get_CaseName()}] after the network epoch bump the ended episode's route reads {RouteStatus}, expected None");
    }
}

// (b) A stall escalates to a block and the FailMove policy ends the episode with OnGoalFailed.
class UCk_AutoTest_Crowd_EpisodeEnd_ReleasesSidewalkRoute_FailMovePolicy : UCk_AutoTest_Crowd_EpisodeEnd_ReleasesSidewalkRoute
{
    // Three 3 s no-progress windows (two ladder re-paths, then the block) plus route installs.
    default _TimeoutSeconds = 45.0f;
    default _Case = 1;
    default _TerminalDeadlineSec = 30.0f;
}

// (c) HoldAndRetry holds, resumes and re-wedges until the bounded retries are spent.
class UCk_AutoTest_Crowd_EpisodeEnd_ReleasesSidewalkRoute_NoProgressExhausted : UCk_AutoTest_Crowd_EpisodeEnd_ReleasesSidewalkRoute
{
    // The ladder (~11 s), then three hold -> resume -> re-wedge cycles (~4.5 s each) at defaults.
    default _TimeoutSeconds = 75.0f;
    default _Case = 2;
    default _TerminalDeadlineSec = 60.0f;
}
