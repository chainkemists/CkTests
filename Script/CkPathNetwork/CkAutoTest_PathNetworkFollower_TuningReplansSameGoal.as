// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: LIVE TUNING REPLANS THE SAME GOAL
//============================================================================
//
// A Ready corridor is retuned without rebuilding its network or changing its
// goal. The follower must emit a second Ready result with a newer tuning
// revision and geometry produced by the new side offset/waypoint spacing.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_TuningReplansSameGoal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private FCk_Handle_CrowdAgent _Agent;
    private int32 _ReadyCount = 0;
    private int32 _NetworkEpoch = 0;
    private int32 _FirstRevision = 0;
    private int32 _FirstWaypointCount = 0;
    private TArray<FVector> _SecondExpectedWaypoints;
    private const FVector Goal = FVector(450.0, 0.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto AgentTransform = utils_transform::Add(
            LocalHandle,
            FTransform(
                FRotator::ZeroRotator,
                FVector(-50.0, 0.0, 0.0),
                FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        TArray<FCk_PathNetwork_RibbonPoint> Points;
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-50.0, 0.0, 0.0), 100.0));
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(450.0, 0.0, 0.0), 100.0));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        _Network = utils_path_network::Add(
            LocalHandle,
            FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        AgentParams.Set_MaxSpeed(1.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, AgentParams);
        utils_velocity::Add(
            LocalHandle,
            FCk_Fragment_Velocity_ParamsData(
                ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(
            LocalHandle,
            FCk_Fragment_Acceleration_ParamsData(
                ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(LocalHandle);

        auto Params = FCk_Fragment_PathNetworkFollower_ParamsData();
        Params.Set_Network(_Network);
        Params.Set_SideKeepingFraction(0.0f);
        Params.Set_CorridorWaypointSpacing(200.0f);
        _Follower = utils_path_network_follower::Add(LocalHandle, Params);

        utils_path_network_follower::BindTo_OnRouteReady(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(this, n"OnRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_path_network_follower::BindTo_OnRouteFailed(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(
                this, n"OnUnexpectedRouteFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(
            _Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(
                this, n"OnUnexpectedGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // The next hop asserts Get_IsBuilt — wait on exactly that rather than on a frame.
        WaitUntil(n"Check_NetworkBuilt", n"OnNetworkReady");
    }

    UFUNCTION()
    private void Check_NetworkBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_path_network::Get_IsBuilt(_Network));
    }

    // The Crowd bridge installs the follower's route as a nav path a pass after
    // OnRouteReady fires. Both installs are waited on by their own observable: the first
    // by the path reaching Ready, the second by the waypoint count switching from the
    // 200cm corridor to the denser 50cm one (the assertions require those to differ, so
    // neither predicate can be satisfied by the state it starts in).
    UFUNCTION()
    private void Check_FirstRouteInstalled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Handle AgentEntity = _Agent;
        auto Res = OutResult;
        Res.Set(utils_nav::Get_PathResult(AgentEntity).Get_Status() == ECk_Nav_PathStatus::Ready);
    }

    UFUNCTION()
    private void Check_SecondRouteInstalled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Handle AgentEntity = _Agent;
        const auto Installed = utils_nav::Get_PathResult(AgentEntity);
        auto Res = OutResult;
        Res.Set(Installed.Get_Status() == ECk_Nav_PathStatus::Ready &&
                Installed.Get_Waypoints().Num() == _SecondExpectedWaypoints.Num());
    }

    UFUNCTION()
    private void OnNetworkReady(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(
            utils_path_network::Get_IsBuilt(_Network),
            "network must be built before the first route request");
        utils_crowd_agent::Request_MoveTo(
            _Agent,
            FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void OnRouteReady(
        FCk_Handle_PathNetworkFollower InFollower,
        FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        _ReadyCount++;
        if (_ReadyCount == 1)
        {
            _NetworkEpoch = utils_path_network::Get_BuildEpoch(_Network);
            _FirstRevision = InResult.Get_TuningRevision();
            _FirstWaypointCount = InResult.Get_CompiledWaypoints().Num();
            WaitUntil(n"Check_FirstRouteInstalled", n"OnFirstRouteInstalled");
            return;
        }

        Assert_Equals_Int(
            utils_path_network::Get_BuildEpoch(_Network),
            _NetworkEpoch,
            "live tuning must not rebuild or change the network epoch");
        Assert_True(
            InResult.Get_TuningRevision() > _FirstRevision,
            f"second route revision {InResult.Get_TuningRevision()} must exceed first {_FirstRevision}");

        const auto Waypoints = InResult.Get_CompiledWaypoints();
        Assert_True(
            Waypoints.Num() > _FirstWaypointCount,
            f"50cm spacing should produce more waypoints than 200cm spacing ({Waypoints.Num()} vs {_FirstWaypointCount})");

        auto MaxLateralOffset = 0.0;
        for (auto Waypoint : Waypoints)
        {
            MaxLateralOffset = Math::Max(
                MaxLateralOffset,
                Math::Abs(Waypoint.Y));
        }
        Assert_True(
            MaxLateralOffset >= 50.0,
            f"retuned side-keeping should offset an intermediate waypoint by at least 50cm; got {MaxLateralOffset}");
        Assert_True(
            (Waypoints[Waypoints.Num() - 1] - Goal).Size() <= 1.0,
            "same-goal replan must retain the exact final goal");

        _SecondExpectedWaypoints = Waypoints;
        WaitUntil(n"Check_SecondRouteInstalled", n"OnSecondRouteInstalled");
    }

    UFUNCTION()
    private void OnFirstRouteInstalled(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        FCk_Handle AgentEntity = _Agent;
        const auto Installed = utils_nav::Get_PathResult(AgentEntity);
        Assert_True(
            Installed.Get_Status() == ECk_Nav_PathStatus::Ready,
            "the Crowd bridge must install the first follower route as a nav path");
        Assert_Equals_Int(
            Installed.Get_Waypoints().Num(),
            _FirstWaypointCount,
            "the first installed nav path must match the first corridor");

        auto Tuning = FCk_PathNetworkFollower_Tuning();
        Tuning.Set_OffPathCostMultiplier(6.0f);
        Tuning.Set_SideKeepingFraction(0.8f);
        Tuning.Set_CorridorWaypointSpacing(50.0f);
        utils_path_network_follower::Request_UpdateTuningAndReplan(
            _Follower, Tuning);
    }

    UFUNCTION()
    private void OnSecondRouteInstalled(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        FCk_Handle AgentEntity = _Agent;
        const auto Installed = utils_nav::Get_PathResult(AgentEntity);
        const auto InstalledWaypoints = Installed.Get_Waypoints();
        Assert_True(
            Installed.Get_Status() == ECk_Nav_PathStatus::Ready,
            "same-goal live tuning must leave the Crowd agent with a Ready nav path");
        Assert_Equals_Int(
            InstalledWaypoints.Num(),
            _SecondExpectedWaypoints.Num(),
            "the Crowd bridge must replace the old same-goal path with the retuned corridor");

        auto MaxInstalledLateralOffset = 0.0;
        for (auto Waypoint : InstalledWaypoints)
        {
            MaxInstalledLateralOffset = Math::Max(
                MaxInstalledLateralOffset,
                Math::Abs(Waypoint.Y));
        }
        Assert_True(
            MaxInstalledLateralOffset >= 50.0,
            f"the installed retuned nav path must contain the new side offset; got {MaxInstalledLateralOffset}");

        for (int32 Index = 0;
             Index < InstalledWaypoints.Num()
                 && Index < _SecondExpectedWaypoints.Num();
             ++Index)
        {
            Assert_True(
                (InstalledWaypoints[Index] - _SecondExpectedWaypoints[Index]).Size() <= 1.0,
                f"installed waypoint {Index} must match the retuned corridor");
        }

        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedRouteFailed(
        FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }
        const auto Result =
            utils_path_network_follower::Get_RouteResult(_Follower);
        FinishFailure(
            f"route unexpectedly failed with reason {Result.Get_FailReason()}");
    }

    UFUNCTION()
    private void OnUnexpectedGoalFailed(
        FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        FinishFailure("CrowdAgent goal failed while verifying live route replacement");
    }
}
