// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: PROJECTS ENDPOINT WITH NAV QUERY EXTENT
//============================================================================
//
// The AutoTests navmesh ends near X=500. The raw goal is deliberately farther
// than the PathNetwork corridor-normalization tolerance, but within the normal
// CkNavigation query extent. The network exit is on the same reachable navmesh
// island as the projected goal.
//
// PathNetwork must therefore use the navigation endpoint-query contract for
// the terminal connector while retaining strict normalization for authored
// sidewalk waypoints.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_ProjectsEndpointWithNavQueryExtent
    : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private FVector _Goal = FVector::ZeroVector;
    private FVector _ProjectedGoal = FVector::ZeroVector;

    private const FVector Start = FVector(-450.0f, 0.0f, 0.0f);
    private const FVector NetworkEntry = FVector(-400.0f, 0.0f, 0.0f);
    private const FVector NetworkExit = FVector(450.0f, 0.0f, 0.0f);

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

        TArray<FCk_PathNetwork_RibbonPoint> Points;
        Points.Add(FCk_PathNetwork_RibbonPoint(NetworkEntry, 100.0f));
        Points.Add(FCk_PathNetwork_RibbonPoint(NetworkExit, 100.0f));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        _Network = utils_path_network::Add(
            LocalHandle,
            FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_OffPathCostMultiplier(3.0f);
        FollowerParams.Set_CorridorWaypointSpacing(100.0f);
        _Follower = utils_path_network_follower::Add(LocalHandle, FollowerParams);

        utils_path_network_follower::BindTo_OnRouteReady(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(this, n"OnRouteReady"));
        utils_path_network_follower::BindTo_OnRouteFailed(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(this, n"OnUnexpectedRouteFailed"));

        WaitOneFrame(n"OnNetworkReadyToRoute");
    }

    UFUNCTION()
    private void OnNetworkReadyToRoute(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(
            utils_path_network::Get_IsBuilt(_Network),
            "network must build before the endpoint-projection route request");

        auto FoundFixture = false;
        for (auto X = 600.0f; X <= 3000.0f; X += 100.0f)
        {
            const auto Candidate = FVector(X, 0.0f, 0.0f);
            FVector TightProjection;
            const auto ProjectsWithTightExtent = utils_nav::Try_ProjectOntoNavmesh(
                FCk_Handle(_Follower),
                Candidate,
                25.0f,
                TightProjection,
                100.0f);
            FVector BroadProjection;
            const auto ProjectsWithNavQueryExtent = utils_nav::Try_ProjectOntoNavmesh(
                FCk_Handle(_Follower),
                Candidate,
                500.0f,
                BroadProjection,
                500.0f);
            if (!ProjectsWithTightExtent && ProjectsWithNavQueryExtent)
            {
                _Goal = Candidate;
                _ProjectedGoal = BroadProjection;
                FoundFixture = true;
                break;
            }
        }
        Assert_True(
            FoundFixture,
            "fixture must expose a goal outside 25cm normalization but inside the normal CkNavigation query extent");
        if (!FoundFixture) { return; }

        Assert_True(
            (_ProjectedGoal - _Goal).Size2D() > 25.0f,
            f"fixture projection delta must exceed 25cm, got {(_ProjectedGoal - _Goal).Size2D()}cm");

        utils_path_network_follower::Request_FindRoute(
            _Follower,
            FCk_Request_PathNetworkFollower_FindRoute(_Goal));
    }

    UFUNCTION()
    private void OnRouteReady(
        FCk_Handle_PathNetworkFollower InFollower,
        FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        const auto Waypoints = InResult.Get_CompiledWaypoints();
        Assert_True(
            Waypoints.Num() >= 2,
            f"projected-endpoint route must publish at least two waypoints, got {Waypoints.Num()}");
        if (Waypoints.Num() == 0) { return; }

        Assert_True(
            (Waypoints.Last() - _ProjectedGoal).Size() <= 2.0f,
            f"route terminal must equal the normal navigation projection {_ProjectedGoal}, got {Waypoints.Last()}");
        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedRouteFailed(FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_path_network_follower::Get_RouteResult(InFollower);
        FinishFailure(
            f"endpoint inside normal nav-query extent was rejected: {Result.Get_FailReason()}");
    }
}
