// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: PROJECTS NEAR RIBBON WAYPOINT
//============================================================================
//
// The AutoTests navmesh's north edge supplies a deterministic Recast boundary.
// This fixture places a wide, straight sidewalk 40cm beyond that edge, with
// short diagonal ramps from start/goal on the mesh. The centerline therefore
// cannot project in a 25cm box but can snap back into the authored ribbon in a
// 50cm box. It protects the narrow on-ribbon normalization tolerance without
// permitting a distant sidewalk to become an airborne path.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_ProjectsRibbonWaypointWithinNavQueryExtent
    : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private const float32 TightProjectionExtentCm = 25.0f;
    private const float32 RibbonProjectionExtentCm = 50.0f;
    private const float64 CenterlineOutsideNavmeshCm = 40.0;
    private const float64 RibbonHalfWidthCm = 100.0;
    private const float64 RibbonContainmentToleranceCm = 2.0;

    private FCk_Handle _Context;
    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private FVector _Start = FVector::ZeroVector;
    private FVector _Goal = FVector::ZeroVector;
    private FVector _OutsideCenterlinePoint = FVector::ZeroVector;
    private TArray<FVector> _RibbonControls;

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
                (Projected - FVector(0.0, CandidateY, 0.0)).Size2D() > 2.0f)
            { break; }
            HighestNavmeshY = CandidateY;
        }

        if (HighestNavmeshY < 300.0)
        {
            Complete(false,
                f"fixture requires a north AutoTests navmesh boundary, highest Y={HighestNavmeshY}");
            return;
        }

        const auto BoundaryY = HighestNavmeshY;
        _Start = FVector(-300.0, BoundaryY, 0.0);
        _Goal = FVector(300.0, BoundaryY, 0.0);

        // The 50cm sweep above only BRACKETS the navmesh edge — its last on-mesh sample can sit
        // anywhere up to a full step short of the true Recast boundary, and where it lands is a
        // property of the host project's navmesh generation settings, not of this fixture. The
        // sidewalk below is placed a fixed offset BEYOND the edge and the whole test rests on
        // that offset landing in the 25-50cm projection band, so it has to be measured from the
        // real edge. Off a grid-quantized proxy the sidewalk can come out on-navmesh instead
        // (observed here: delta=2cm, tight=true) and the fixture disqualifies itself.
        auto NavmeshEdgeY = BoundaryY;
        for (float64 Probe = BoundaryY; Probe <= BoundaryY + 50.0; Probe += 2.0)
        {
            FVector Projected;
            auto ProbeHandle = _Context;
            const auto Projects = utils_nav::Try_ProjectOntoNavmesh(
                ProbeHandle,
                FVector(0.0, Probe, 0.0),
                5.0f,
                Projected,
                300.0f);
            if (!Projects ||
                (Projected - FVector(0.0, Probe, 0.0)).Size2D() > 2.0f)
            { break; }
            NavmeshEdgeY = Probe;
        }

        _OutsideCenterlinePoint = FVector(0.0, NavmeshEdgeY + CenterlineOutsideNavmeshCm, 0.0);

        FVector TightProjection;
        auto TightHandle = _Context;
        const auto ProjectsWithTightExtent = utils_nav::Try_ProjectOntoNavmesh(
            TightHandle,
            _OutsideCenterlinePoint,
            TightProjectionExtentCm,
            TightProjection,
            300.0f);

        FVector RibbonProjection;
        auto RibbonHandle = _Context;
        const auto ProjectsWithRibbonExtent = utils_nav::Try_ProjectOntoNavmesh(
            RibbonHandle,
            _OutsideCenterlinePoint,
            RibbonProjectionExtentCm,
            RibbonProjection,
            300.0f);
        const auto RibbonProjectionDelta =
            (_OutsideCenterlinePoint - RibbonProjection).Size2D();

        if (ProjectsWithTightExtent ||
            !ProjectsWithRibbonExtent ||
            RibbonProjectionDelta <= TightProjectionExtentCm ||
            RibbonProjectionDelta > RibbonProjectionExtentCm)
        {
            Complete(false,
                f"fixture must require a 25-50cm ribbon projection " +
                f"(tight={ProjectsWithTightExtent}, broad={ProjectsWithRibbonExtent}, " +
                f"delta={RibbonProjectionDelta}cm)");
            return;
        }

        _RibbonControls.Empty();
        _RibbonControls.Add(_Start);
        _RibbonControls.Add(FVector(-200.0, NavmeshEdgeY + CenterlineOutsideNavmeshCm, 0.0));
        _RibbonControls.Add(FVector(200.0, NavmeshEdgeY + CenterlineOutsideNavmeshCm, 0.0));
        _RibbonControls.Add(_Goal);

        auto LocalHandle = _Context;
        utils_transform::Add(
            LocalHandle,
            FTransform(FRotator::ZeroRotator, _Start, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        TArray<FCk_PathNetwork_RibbonPoint> Points;
        for (int32 Index = 0; Index < _RibbonControls.Num(); ++Index)
        { Points.Add(FCk_PathNetwork_RibbonPoint(_RibbonControls[Index], RibbonHalfWidthCm)); }

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        _Network = utils_path_network::Add(
            LocalHandle,
            FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        auto Params = FCk_Fragment_PathNetworkFollower_ParamsData();
        Params.Set_Network(_Network);
        Params.Set_OffPathCostMultiplier(100.0f);
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
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(this, n"OnRouteFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // The next hop FAILS the test when Get_IsBuilt is false ("did not build before
        // routing") — that is a timing race with a failure message attached. Waiting on
        // the build itself removes the failure mode rather than reporting it.
        WaitUntil(n"Check_NetworkBuilt", n"OnNetworkReadyToRoute");
    }

    UFUNCTION()
    private void Check_NetworkBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_path_network::Get_IsBuilt(_Network));
    }

    UFUNCTION()
    private void OnNetworkReadyToRoute(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!utils_path_network::Get_IsBuilt(_Network))
        {
            Complete(false, "near-boundary ribbon network did not build before routing");
            return;
        }

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
        if (Waypoints.Num() < 4)
        {
            Complete(false,
                f"near-boundary ribbon route must publish internal waypoints, got {Waypoints.Num()}");
            return;
        }

        for (int32 Index = 0; Index < Waypoints.Num(); ++Index)
        {
            FVector ProjectedWaypoint;
            const auto Projects = utils_nav::Try_ProjectOntoNavmesh(
                FCk_Handle(InFollower),
                Waypoints[Index],
                TightProjectionExtentCm,
                ProjectedWaypoint,
                300.0f);
            if (!Projects || (ProjectedWaypoint - Waypoints[Index]).Size() > 2.0f)
            {
                Complete(false,
                    f"published waypoint {Index} must lie on navmesh, got {Waypoints[Index]}");
                return;
            }

            if (!IsInsideAuthoredRibbon(Waypoints[Index]))
            {
                Complete(false,
                    f"published waypoint {Index} escaped the authored ribbon: {Waypoints[Index]}");
                return;
            }

            if (Index > 0 && !IsSegmentInsideAuthoredRibbon(
                    Waypoints[Index - 1],
                    Waypoints[Index]))
            {
                Complete(false,
                    f"published segment {Index - 1}->{Index} escaped the authored ribbon");
                return;
            }
        }

        Complete(true, "");
    }

    UFUNCTION()
    private void OnRouteFailed(FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }
        const auto Result = utils_path_network_follower::Get_RouteResult(InFollower);
        Complete(false,
            f"near-boundary ribbon inside the 50cm projection extent was rejected: {Result.Get_FailReason()}");
    }

    private bool IsInsideAuthoredRibbon(const FVector&in Point) const
    {
        for (int32 Index = 0; Index < _RibbonControls.Num() - 1; ++Index)
        {
            const auto A = _RibbonControls[Index];
            const auto B = _RibbonControls[Index + 1];
            const auto AB = B - A;
            const auto LengthSquared = AB.SizeSquared();
            if (LengthSquared <= 0.001) { continue; }

            auto T = (Point - A).DotProduct(AB) / LengthSquared;
            T = Math::Clamp(T, 0.0, 1.0);
            const auto Closest = A + AB * T;
            if ((Point - Closest).Size2D() <= RibbonHalfWidthCm + RibbonContainmentToleranceCm)
            { return true; }
        }

        return false;
    }

    private bool IsSegmentInsideAuthoredRibbon(
        const FVector&in From,
        const FVector&in To) const
    {
        const auto Steps = Math::Max(1, int32((To - From).Size() / 10.0) + 1);
        for (int32 Index = 0; Index <= Steps; ++Index)
        {
            const auto Alpha = float64(Index) / float64(Steps);
            if (!IsInsideAuthoredRibbon(From + (To - From) * Alpha))
            { return false; }
        }

        return true;
    }

    private void Complete(bool InSuccess, const FString&in InReason)
    {
        if (IsFinished()) { return; }
        if (InSuccess)
        { FinishSuccess(); }
        else
        { FinishFailure(InReason); }
    }
}
