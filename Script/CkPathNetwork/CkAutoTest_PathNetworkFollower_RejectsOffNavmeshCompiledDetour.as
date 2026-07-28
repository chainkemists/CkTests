// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: REJECTS OFF-NAVMESH COMPILED DETOUR
//============================================================================
//
// The terminal ramps are deliberately short and live on the AutoTests level's
// baked +/-500cm navmesh. A very high off-path multiplier nevertheless makes
// the route graph choose the long contiguous sidewalk detour:
//
//    start (-450,0) -> (-425,0) -> (-425,5000) -> (425,5000) -> (425,0) -> goal (450,0)
//
// Its middle is outside the navmesh. It must not be published as an airborne
// path merely because the start/goal projections and both ramps are valid.
// The route therefore fails with NoRouteFound; Ready is an immediate failure.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_RejectsOffNavmeshCompiledDetour
    : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private const FVector Start = FVector(-450.0f, 0.0f, 0.0f);
    private const FVector Goal = FVector(450.0f, 0.0f, 0.0f);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(
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

        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_OffPathCostMultiplier(100.0f);
        FollowerParams.Set_CorridorWaypointSpacing(100.0f);
        _Follower = utils_path_network_follower::Add(LocalHandle, FollowerParams);

        utils_path_network_follower::BindTo_OnRouteFailed(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(this, n"OnRouteFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_path_network_follower::BindTo_OnRouteReady(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(this, n"OnUnexpectedRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        WaitOneFrame(n"OnNetworkReadyToRoute");
    }

    UFUNCTION()
    private void OnNetworkReadyToRoute(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_path_network::Get_IsBuilt(_Network),
            "detour network must build before route request");

        // The fixtures prove the terminal conditions independently of the desired failure:
        // both endpoints are on mesh, and each 25cm ramp endpoint is also on mesh. Only the
        // contiguous ribbon's far-away middle is invalid.
        FVector Projected;
        Assert_True(utils_nav::Try_ProjectOntoNavmesh(FCk_Handle(_Follower), Start, 25.0f, Projected, 300.0f),
            "start must be on the baked navmesh");
        Assert_True(utils_nav::Try_ProjectOntoNavmesh(FCk_Handle(_Follower), Goal, 25.0f, Projected, 300.0f),
            "goal must be on the baked navmesh");
        Assert_True(utils_nav::Try_ProjectOntoNavmesh(FCk_Handle(_Follower), FVector(-425.0f, 0.0f, 0.0f), 25.0f, Projected, 300.0f),
            "network entry / short start ramp endpoint must be on navmesh");
        Assert_True(utils_nav::Try_ProjectOntoNavmesh(FCk_Handle(_Follower), FVector(425.0f, 0.0f, 0.0f), 25.0f, Projected, 300.0f),
            "network exit / short goal ramp endpoint must be on navmesh");

        utils_path_network_follower::Request_FindRoute(
            _Follower,
            FCk_Request_PathNetworkFollower_FindRoute(Goal));
    }

    UFUNCTION()
    private void OnRouteFailed(FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_path_network_follower::Get_RouteResult(InFollower);
        Assert_True(Result.Get_Status() == ECk_PathNetwork_RouteStatus::Failed,
            f"off-navmesh compiled detour must leave the follower Failed, got {Result.Get_Status()}");
        Assert_True(Result.Get_FailReason() == ECk_PathNetwork_RouteFailReason::NoRouteFound,
            f"off-navmesh compiled detour must be rejected as NoRouteFound, got {Result.Get_FailReason()}");
        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedRouteReady(
        FCk_Handle_PathNetworkFollower InFollower,
        FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        FinishFailure(
            f"off-navmesh detour was incorrectly published Ready with {InResult.Get_CompiledWaypoints().Num()} waypoints (cost {InResult.Get_TotalCost()})");
    }
}
