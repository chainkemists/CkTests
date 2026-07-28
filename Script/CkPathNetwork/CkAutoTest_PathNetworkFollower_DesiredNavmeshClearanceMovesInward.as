// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: DESIRED NAVMESH CLEARANCE MOVES INWARD
//============================================================================
//
// The test discovers the AutoTests level's north Recast boundary, then places a
// wide straight ribbon just inside it. The first route disables comfort
// clearance; the second changes only DesiredNavmeshClearance and must move
// internal waypoints toward -Y.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_DesiredNavmeshClearanceMovesInward
    : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle _Context;
    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private FVector _Start = FVector::ZeroVector;
    private FVector _Goal = FVector::ZeroVector;
    private float64 _CenterlineY = 0.0;
    private int32 _ReadyCount = 0;
    private int32 _NetworkEpoch = 0;
    private int32 _BaselineRevision = 0;
    private int32 _BaselineWaypointCount = 0;
    private float64 _BaselineBoundarywardY = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Context = InHandle;
        auto LocalHandle = InHandle;

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);
        WaitOneFrame(n"OnNavmeshReady");
    }

    UFUNCTION()
    private void OnNavmeshReady(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto HighestNavmeshY = -1.0;
        for (float64 CandidateY = 0.0; CandidateY <= 5000.0; CandidateY += 50.0)
        {
            FVector Projected;
            auto LocalHandle = _Context;
            const auto Projects = utils_nav::Try_ProjectOntoNavmesh(
                LocalHandle,
                FVector(0.0, CandidateY, 0.0),
                5.0f,
                Projected,
                300.0f);
            if (!Projects ||
                (Projected - FVector(0.0, CandidateY, 0.0)).Size() > 2.0f)
            { break; }
            HighestNavmeshY = CandidateY;
        }

        Assert_True(
            HighestNavmeshY >= 300.0,
            f"clearance fixture requires a north navmesh boundary, highest projected Y={HighestNavmeshY}");
        if (HighestNavmeshY < 300.0)
        {
            FinishFailure("failed to discover the AutoTests navmesh boundary");
            return;
        }

        _CenterlineY = HighestNavmeshY - 50.0;
        _Start = FVector(-300.0, _CenterlineY, 0.0);
        _Goal = FVector(300.0, _CenterlineY, 0.0);

        FVector ProjectedLane;
        auto LaneHandle = _Context;
        const auto LaneProjects = utils_nav::Try_ProjectOntoNavmesh(
            LaneHandle,
            FVector(0.0, _CenterlineY, 0.0),
            10.0f,
            ProjectedLane,
            300.0f);
        Assert_True(
            LaneProjects &&
                (ProjectedLane - FVector(0.0, _CenterlineY, 0.0)).Size() <= 2.0f,
            "discovered baseline lane must lie on the AutoTests navmesh");

        FVector ProjectedInward;
        auto InwardHandle = _Context;
        const auto InwardProjects = utils_nav::Try_ProjectOntoNavmesh(
            InwardHandle,
            FVector(0.0, _CenterlineY - 150.0, 0.0),
            10.0f,
            ProjectedInward,
            300.0f);
        Assert_True(
            InwardProjects &&
                (ProjectedInward - FVector(0.0, _CenterlineY - 150.0, 0.0)).Size() <= 2.0f,
            "the ribbon must have navmesh room inward from the discovered boundary");

        FVector ProjectedOutside;
        auto OutsideHandle = _Context;
        const auto OutsideProjects = utils_nav::Try_ProjectOntoNavmesh(
            OutsideHandle,
            FVector(0.0, HighestNavmeshY + 100.0, 0.0),
            10.0f,
            ProjectedOutside,
            300.0f);
        Assert_True(
            OutsideProjects == false,
            "the discovered clearance lane must have a navmesh boundary on its north side");

        if (!LaneProjects || !InwardProjects || OutsideProjects)
        {
            FinishFailure("AutoTests navmesh does not support the clearance fixture");
            return;
        }

        auto LocalHandle = _Context;
        utils_transform::Add(
            LocalHandle,
            FTransform(FRotator::ZeroRotator, _Start, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        TArray<FCk_PathNetwork_RibbonPoint> Points;
        Points.Add(FCk_PathNetwork_RibbonPoint(_Start, 200.0f));
        Points.Add(FCk_PathNetwork_RibbonPoint(_Goal, 200.0f));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        _Network = utils_path_network::Add(
            LocalHandle,
            FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        auto Params = FCk_Fragment_PathNetworkFollower_ParamsData();
        Params.Set_Network(_Network);
        Params.Set_OffPathCostMultiplier(3.0f);
        Params.Set_SideKeepingFraction(0.0f);
        Params.Set_CorridorWaypointSpacing(100.0f);
        Params.Set_CornerSmoothingDistance(0.0f);
        Params.Set_DesiredNavmeshClearance(0.0f);
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

        WaitOneFrame(n"OnNetworkReady");
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
            "network must be built before the baseline route");

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

        _ReadyCount++;
        const auto Waypoints = InResult.Get_CompiledWaypoints();
        Assert_True(
            Waypoints.Num() >= 4,
            f"600cm corridor should compile at least four movement targets, got {Waypoints.Num()}");

        if (Waypoints.Num() < 2)
        {
            FinishFailure("clearance route did not produce internal waypoints");
            return;
        }

        auto BoundarywardY = -1.0e9;
        auto FoundInternalPoint = false;
        // Route assembly can retain seam endpoints around the on-ribbon run.
        // Compare geometric interior points, which are the points clearance is
        // allowed to move regardless of the surrounding leg layout.
        for (int32 Index = 0; Index < Waypoints.Num(); ++Index)
        {
            if (Waypoints[Index].X <= _Start.X + 50.0 ||
                Waypoints[Index].X >= _Goal.X - 50.0)
            { continue; }
            FoundInternalPoint = true;
            BoundarywardY = Math::Max(BoundarywardY, Waypoints[Index].Y);
        }
        Assert_True(
            FoundInternalPoint,
            "clearance fixture must compile geometric interior waypoints");
        if (!FoundInternalPoint) { return; }

        Assert_True(
            (Waypoints[Waypoints.Num() - 1] - _Goal).Size() <= 1.0f,
            "clearance replan must preserve the exact logical goal");

        if (_ReadyCount == 1)
        {
            _NetworkEpoch = utils_path_network::Get_BuildEpoch(_Network);
            _BaselineRevision = InResult.Get_TuningRevision();
            _BaselineWaypointCount = Waypoints.Num();
            _BaselineBoundarywardY = BoundarywardY;
            Assert_True(
                Math::Abs(_BaselineBoundarywardY - _CenterlineY) <= 2.0f,
                f"zero-clearance baseline should remain on the ribbon centerline, got Y={_BaselineBoundarywardY}");
            WaitOneFrame(n"OnBaselineCaptured");
            return;
        }

        Assert_Equals_Int(
            utils_path_network::Get_BuildEpoch(_Network),
            _NetworkEpoch,
            "clearance tuning must not rebuild the network");
        Assert_True(
            InResult.Get_TuningRevision() > _BaselineRevision,
            "clearance tuning must advance the route revision");
        Assert_Equals_Int(
            Waypoints.Num(),
            _BaselineWaypointCount,
            "changing only desired clearance must preserve waypoint density");
        Assert_True(
            _BaselineBoundarywardY - BoundarywardY >= 25.0f,
            f"desired clearance should move internal points inward by at least 25cm " +
            f"(baseline Y={_BaselineBoundarywardY}, retuned Y={BoundarywardY})");

        for (int32 Index = 0; Index < Waypoints.Num(); ++Index)
        {
            FVector ProjectedWaypoint;
            const auto Projects = utils_nav::Try_ProjectOntoNavmesh(
                FCk_Handle(InFollower),
                Waypoints[Index],
                25.0f,
                ProjectedWaypoint,
                300.0f);
            Assert_True(
                Projects &&
                    (ProjectedWaypoint - Waypoints[Index]).Size() <= 2.0f,
                f"clearance waypoint {Index} must remain on navmesh: {Waypoints[Index]}");
        }

        FinishSuccess();
    }

    UFUNCTION()
    private void OnBaselineCaptured(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Tuning = FCk_PathNetworkFollower_Tuning();
        Tuning.Set_OffPathCostMultiplier(3.0f);
        Tuning.Set_SideKeepingFraction(0.0f);
        Tuning.Set_CorridorWaypointSpacing(100.0f);
        Tuning.Set_CornerSmoothingDistance(0.0f);
        Tuning.Set_DesiredNavmeshClearance(150.0f);
        utils_path_network_follower::Request_UpdateTuningAndReplan(
            _Follower,
            Tuning);
    }

    UFUNCTION()
    private void OnUnexpectedRouteFailed(
        FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }
        const auto Result =
            utils_path_network_follower::Get_RouteResult(_Follower);
        FinishFailure(
            f"clearance route unexpectedly failed with {Result.Get_FailReason()}");
    }
}
