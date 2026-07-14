// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: REBUILD REPLANS EXISTING ROUTES
//============================================================================
//
// The runtime-rebuild promise: replacing the network's ribbons bumps the
// build epoch, and FProcessor_PathNetworkFollower_InvalidateOnRebuild
// re-plans every corridor planned against the older epoch — WITHOUT the
// caller re-issuing FindRoute.
//
//   1. Route across an L network (same geometry as RoutePrefersNetwork);
//      first OnRouteReady arrives.
//   2. Request_Rebuild with a single diagonal ribbon.
//   3. A SECOND OnRouteReady must arrive unprompted (the invalidation
//      replan), the epoch must have advanced, and the new route must hug
//      the diagonal (no waypoint near the old corner).
//============================================================================

class UCk_AutoTest_PathNetworkFollower_RebuildReplansRoute : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private int32 _ReadyCount = 0;
    private int32 _EpochAtFirstReady = 0;
    private const FVector Goal = FVector(450.0, 450.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(-50.0, 25.0, 0.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        TArray<FCk_PathNetwork_RibbonPoint> PointsA;
        PointsA.Add(FCk_PathNetwork_RibbonPoint(FVector(0.0, 0.0, 0.0), 100.0));
        PointsA.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 0.0, 0.0), 100.0));

        TArray<FCk_PathNetwork_RibbonPoint> PointsB;
        PointsB.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 0.0, 0.0), 100.0));
        PointsB.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 400.0, 0.0), 100.0));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(PointsA));
        Ribbons.Add(FCk_PathNetwork_Ribbon(PointsB));

        _Network = utils_path_network::Add(LocalHandle, FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_CorridorWaypointSpacing(100.0);
        _Follower = utils_path_network_follower::Add(LocalHandle, FollowerParams);

        utils_path_network_follower::BindTo_OnRouteReady(_Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(this, n"OnRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_path_network_follower::BindTo_OnRouteFailed(_Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(this, n"OnUnexpectedRouteFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        WaitOneFrame(n"OnNetworkReadyToRoute");
    }

    UFUNCTION()
    private void OnNetworkReadyToRoute(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        utils_path_network_follower::Request_FindRoute(_Follower,
            FCk_Request_PathNetworkFollower_FindRoute(Goal));
    }

    UFUNCTION()
    private void OnRouteReady(FCk_Handle_PathNetworkFollower InFollower, FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        _ReadyCount++;

        if (_ReadyCount == 1)
        {
            _EpochAtFirstReady = utils_path_network::Get_BuildEpoch(_Network);

            // Swap the L for a straight diagonal — the invalidation processor must replan the
            // existing corridor without a second FindRoute from us.
            TArray<FCk_PathNetwork_RibbonPoint> DiagonalPoints;
            DiagonalPoints.Add(FCk_PathNetwork_RibbonPoint(FVector(-50.0, 25.0, 0.0), 100.0));
            DiagonalPoints.Add(FCk_PathNetwork_RibbonPoint(FVector(450.0, 450.0, 0.0), 100.0));

            TArray<FCk_PathNetwork_Ribbon> NewRibbons;
            NewRibbons.Add(FCk_PathNetwork_Ribbon(DiagonalPoints));

            utils_path_network::Request_Rebuild(_Network, FCk_Request_PathNetwork_Rebuild(NewRibbons));
            return;
        }

        // Second Ready = the unprompted invalidation replan.
        Assert_True(utils_path_network::Get_BuildEpoch(_Network) > _EpochAtFirstReady,
            f"build epoch must advance across a rebuild (was {_EpochAtFirstReady}, now {utils_path_network::Get_BuildEpoch(_Network)})");

        Assert_True(InResult.Get_Status() == ECk_PathNetwork_RouteStatus::Ready,
            f"replanned route must be Ready, got {InResult.Get_Status()}");

        // The replanned route follows the diagonal — nothing should pass near the OLD corner.
        const auto OldCorner = FVector(400.0, 0.0, 0.0);
        const auto Waypoints = InResult.Get_CompiledWaypoints();
        auto ClosestToOldCorner = 1.0e9;

        for (int32 i = 0; i < Waypoints.Num(); ++i)
        {
            const auto Dist = (Waypoints[i] - OldCorner).Size();
            if (Dist < ClosestToOldCorner) { ClosestToOldCorner = Dist; }
        }

        Assert_True(ClosestToOldCorner > 200.0,
            f"replanned route should follow the new diagonal, but a waypoint passed within {ClosestToOldCorner}cm of the OLD corner");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedRouteFailed(FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_path_network_follower::Get_RouteResult(_Follower);
        FinishFailure(f"route unexpectedly failed with reason {Result.Get_FailReason()} (ready-count at failure: {_ReadyCount})");
    }
}
