// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: FOLLOWER ROUTE PREFERS THE NETWORK
//============================================================================
//
// The core promise of the feature: with the default 3x off-path multiplier,
// a follower whose goal sits past an L-shaped sidewalk routes ALONG the L
// (entry ramp → both edges → exit ramp) instead of cutting the diagonal.
//
//   network:  (0,0) ──► (400,0) ──► (400,400)     start (-50, 25)
//                                                  goal  (450, 450)
//
// The diagonal costs ~656cm x 3; the network path costs ~800cm x 1 plus two
// short ramps — the network wins by construction. Verified by:
//   - OnRouteReady fires with Status Ready and >= 4 compiled waypoints
//   - some compiled waypoint passes near the L's corner (400, 0) — the
//     giveaway that the route walked the network rather than the diagonal
//   - the compiled polyline is meaningfully LONGER than the straight line
//     (a shortcut would be ~straight)
//
// GEOMETRY NOTE: everything sits inside the AutoTests level's baked navmesh
// (±500cm around origin) so plan-time off-path validation resolves honestly
// — off-mesh legs get demoted to a huge uniform price, which would let the
// direct edge tie the network route and invalidate this assertion.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_RoutePrefersNetwork : UCk_AutoTest_Base
{
    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private const FVector Goal = FVector(450.0, 450.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(-50.0, 25.0, 0.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the lazy navmesh bake so plan-time off-path validation has data.
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

        Assert_True(ck::IsValid(_Follower), "follower Add() must return a valid handle");
        Assert_True(utils_path_network_follower::Has(FCk_Handle(_Follower)),
            "test entity must carry the follower feature");

        utils_path_network_follower::BindTo_OnRouteReady(_Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(this, n"OnRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_path_network_follower::BindTo_OnRouteFailed(_Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(this, n"OnUnexpectedRouteFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Let the setup processor build the graph before planning against it.
        WaitOneFrame(n"OnNetworkReadyToRoute");
    }

    UFUNCTION()
    private void OnNetworkReadyToRoute(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_path_network::Get_IsBuilt(_Network),
            "network must be built one frame after Add()");

        utils_path_network_follower::Request_FindRoute(_Follower,
            FCk_Request_PathNetworkFollower_FindRoute(Goal));

        Assert_True(utils_path_network_follower::Get_RouteStatus(_Follower) == ECk_PathNetwork_RouteStatus::Pending,
            "route status must park at Pending as soon as the request is enqueued");
    }

    UFUNCTION()
    private void OnRouteReady(FCk_Handle_PathNetworkFollower InFollower, FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult.Get_Status() == ECk_PathNetwork_RouteStatus::Ready,
            f"expected status Ready, got {InResult.Get_Status()}");

        const auto Waypoints = InResult.Get_CompiledWaypoints();
        Assert_True(Waypoints.Num() >= 4,
            f"an L-route with 100cm spacing should compile >= 4 waypoints, got {Waypoints.Num()}");

        // The route must pass near the L's corner — the proof it walked the network.
        // Corner samples carry at most ~50cm side-keeping offset + 100cm spacing slack.
        const auto Corner = FVector(400.0, 0.0, 0.0);
        auto ClosestToCorner = 1.0e9;
        auto PolylineLength = 0.0;

        for (int32 i = 0; i < Waypoints.Num(); ++i)
        {
            const auto DistToCorner = (Waypoints[i] - Corner).Size();
            if (DistToCorner < ClosestToCorner) { ClosestToCorner = DistToCorner; }

            if (i > 0)
            { PolylineLength += (Waypoints[i] - Waypoints[i - 1]).Size(); }
        }

        Assert_True(ClosestToCorner <= 200.0,
            f"route should pass near the L corner (400,0,0); closest waypoint was {ClosestToCorner}cm away — did it shortcut the diagonal?");

        const auto StraightLine = (Goal - FVector(-50.0, 25.0, 0.0)).Size();
        Assert_True(PolylineLength > StraightLine * 1.15,
            f"network route should be meaningfully longer than the diagonal (polyline {PolylineLength}cm vs straight {StraightLine}cm)");

        Assert_True(InResult.Get_TotalCost() > 0.0,
            "route cost must be positive");

        // The last compiled waypoint is the exact goal.
        Assert_True((Waypoints[Waypoints.Num() - 1] - Goal).Size() <= 1.0,
            f"final waypoint must be the exact goal, got {Waypoints[Waypoints.Num() - 1]}");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedRouteFailed(FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_path_network_follower::Get_RouteResult(_Follower);
        FinishFailure(f"route to reachable goal unexpectedly failed with reason {Result.Get_FailReason()}");
    }
}
