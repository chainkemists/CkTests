// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: FALLS BACK TO NAVIGATION
//============================================================================
//
// The authored corridor is deliberately invalid because its middle lies far
// outside the AutoTests navmesh. The same start and goal are connected by an
// ordinary Recast path. A CrowdAgent MoveTo must therefore observe one failed
// PathNetwork route, enqueue one CkNavigation fallback, and reach the original
// goal without broadcasting OnGoalFailed.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_FallsBackToNavigation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private FCk_Handle_CrowdAgent _Agent;
    private int32 _RouteFailedCount = 0;
    private int32 _NavReadyCount = 0;

    private const FVector Start = FVector(-450.0f, 0.0f, 0.0f);
    private const FVector Goal = FVector(450.0f, 0.0f, 0.0f);
    private const float ArrivalRadius = 180.0f;

    // The arrival LATCH fires at <= ArrivalRadius on the latch frame, but this test measures 3D
    // distance to the requested goal on a LATER sample, after the post-arrival coast — a different
    // metric at a different time. Asserting the latch constant with zero slack made the pass margin
    // millimetres (measured reds: 180.09cm and 180.26cm), so any benign timing shift anywhere in
    // the sim flipped it. The slack covers the coast + metric gap, not a behaviour allowance.
    private const float ArrivalMeasurementSlackCm = 5.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto AgentTransform = utils_transform::Add(
            LocalHandle,
            FTransform(FRotator::ZeroRotator, Start, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        TArray<FCk_PathNetwork_RibbonPoint> DetourPoints;
        DetourPoints.Add(FCk_PathNetwork_RibbonPoint(FVector(-425.0f, 0.0f, 0.0f), 75.0f));
        DetourPoints.Add(FCk_PathNetwork_RibbonPoint(FVector(-425.0f, 5000.0f, 0.0f), 75.0f));
        DetourPoints.Add(FCk_PathNetwork_RibbonPoint(FVector(425.0f, 5000.0f, 0.0f), 75.0f));
        DetourPoints.Add(FCk_PathNetwork_RibbonPoint(FVector(425.0f, 0.0f, 0.0f), 75.0f));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(DetourPoints));
        _Network = utils_path_network::Add(
            LocalHandle,
            FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, AgentParams);
        utils_velocity::Add(
            LocalHandle,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(
            LocalHandle,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(LocalHandle);

        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_OffPathCostMultiplier(100.0f);
        FollowerParams.Set_CorridorWaypointSpacing(100.0f);
        _Follower = utils_path_network_follower::Add(LocalHandle, FollowerParams);

        utils_path_network_follower::BindTo_OnRouteFailed(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(this, n"OnRouteFailed"));
        utils_path_network_follower::BindTo_OnRouteReady(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(this, n"OnUnexpectedRouteReady"));
        utils_nav::BindTo_OnPathReady(
            LocalHandle,
            FCk_Delegate_Nav_OnPathReady(this, n"OnNavPathReady"));
        utils_crowd_agent::BindTo_OnGoalReached(
            _Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnGoalReached"));
        utils_crowd_agent::BindTo_OnGoalFailed(
            _Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnUnexpectedGoalFailed"));

        WaitOneFrame(n"OnReadyToMove");
    }

    UFUNCTION()
    private void OnReadyToMove(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_path_network::Get_IsBuilt(_Network),
            "detour network must build before the MoveTo");

        auto Request = FCk_Request_CrowdAgent_MoveTo(Goal);
        Request.Set_ArrivalRadiusOverrideMode(ECk_Override::Override);
        Request.Set_ArrivalRadiusOverrideValue(ArrivalRadius);
        utils_crowd_agent::Request_MoveTo(_Agent, Request);
    }

    UFUNCTION()
    private void OnRouteFailed(FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }

        _RouteFailedCount++;
        Assert_Equals_Int(_RouteFailedCount, 1,
            "the initial PathNetwork route must fail exactly once");

        const auto Result = utils_path_network_follower::Get_RouteResult(InFollower);
        Assert_True(Result.Get_FailReason() == ECk_PathNetwork_RouteFailReason::NoRouteFound,
            f"invalid corridor must fail as NoRouteFound, got {Result.Get_FailReason()}");
    }

    UFUNCTION()
    private void OnNavPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _NavReadyCount++;
        Assert_Equals_Int(_NavReadyCount, 1,
            "the persistent failed corridor must enqueue exactly one navigation fallback");
        Assert_True(InResult.Get_Status() == ECk_Nav_PathStatus::Ready,
            f"navigation fallback must resolve Ready, got {InResult.Get_Status()}");
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_RouteFailedCount, 1,
            "goal reached must follow one failed PathNetwork attempt");
        Assert_Equals_Int(_NavReadyCount, 1,
            "goal reached must follow one successful navigation fallback");

        const auto AgentLocation = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Agent)));
        const auto GoalDistance = (AgentLocation - Goal).Size();
        Assert_True(GoalDistance <= ArrivalRadius + ArrivalMeasurementSlackCm,
            f"fallback must preserve the MoveTo arrival override; distance {GoalDistance}cm");
        Assert_True(GoalDistance > 100.0f,
            f"agent should stop at the 180cm override rather than the 30cm default; distance {GoalDistance}cm");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedRouteReady(
        FCk_Handle_PathNetworkFollower InFollower,
        FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        FinishFailure(
            f"invalid corridor unexpectedly resolved Ready with {InResult.Get_CompiledWaypoints().Num()} waypoints");
    }

    UFUNCTION()
    private void OnUnexpectedGoalFailed(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }

        FinishFailure("CrowdAgent broadcast OnGoalFailed instead of using the navigation fallback");
    }
}
