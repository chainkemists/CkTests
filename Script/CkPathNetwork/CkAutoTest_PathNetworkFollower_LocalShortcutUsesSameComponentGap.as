// Language=angelscript

//============================================================================
// CK PATH NETWORK — LOCAL SHORTCUT USES SAME-COMPONENT GAP
//============================================================================
//
// A connected U sits entirely on the AutoTests navmesh. Its two lower
// endpoints are 850cm apart, while the authored sidewalk travels 1650cm around
// the U. The opted-in local shortcut must cross the lower gap through navmesh
// instead of following the U or publishing the whole-trip direct fallback:
//
//        +=======================+
//        |                       |
// start  A  - - local gap - -  A  goal
//
// The fixture pins direct-route minimum savings to 100% so navmesh repricing
// cannot let the whole-trip direct fallback mask the behavior under test. The
// route-leg assertion proves the selected network alternative contains the
// exact network-to-network gap.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_LocalShortcutUsesSameComponentGap
    : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private const FVector _Start = FVector(-450.0f, 0.0f, 0.0f);
    private const FVector _Goal = FVector(450.0f, 0.0f, 0.0f);
    private const FVector _LeftGapNode = FVector(-425.0f, 0.0f, 0.0f);
    private const FVector _RightGapNode = FVector(425.0f, 0.0f, 0.0f);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(
            LocalHandle,
            FTransform(
                FRotator::ZeroRotator,
                _Start,
                FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        TArray<FCk_PathNetwork_RibbonPoint> LeftSide;
        LeftSide.Add(
            FCk_PathNetwork_RibbonPoint(
                _LeftGapNode,
                75.0f));
        LeftSide.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(-425.0f, 400.0f, 0.0f),
                75.0f));

        TArray<FCk_PathNetwork_RibbonPoint> TopSide;
        TopSide.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(-425.0f, 400.0f, 0.0f),
                75.0f));
        TopSide.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(425.0f, 400.0f, 0.0f),
                75.0f));

        TArray<FCk_PathNetwork_RibbonPoint> RightSide;
        RightSide.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(425.0f, 400.0f, 0.0f),
                75.0f));
        RightSide.Add(
            FCk_PathNetwork_RibbonPoint(
                _RightGapNode,
                75.0f));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(LeftSide));
        Ribbons.Add(FCk_PathNetwork_Ribbon(TopSide));
        Ribbons.Add(FCk_PathNetwork_Ribbon(RightSide));
        _Network = utils_path_network::Add(
            LocalHandle,
            FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        auto FollowerParams =
            FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_OffPathCostMultiplier(1.5f);
        FollowerParams.Set_NearEndpointCostMultiplier(1.5f);
        FollowerParams.Set_EndpointJoinMaxDistance(100.0f);
        FollowerParams.Set_LocalNetworkShortcutMaxDistance(900.0f);
        FollowerParams.Set_DirectRouteMinimumSavingsFraction(1.0f);
        FollowerParams.Set_DirectTripGraceDistance(0.0f);
        FollowerParams.Set_CorridorWaypointSpacing(75.0f);
        _Follower =
            utils_path_network_follower::Add(
                LocalHandle,
                FollowerParams);

        Assert_True(
            ck::IsValid(_Follower),
            "local-shortcut fixture must create a valid follower");

        utils_path_network_follower::BindTo_OnRouteReady(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(
                this,
                n"OnRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_path_network_follower::BindTo_OnRouteFailed(
            _Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(
                this,
                n"OnUnexpectedRouteFailed"),
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

        Assert_True(
            utils_path_network::Get_IsBuilt(_Network),
            "connected U network must build before route request");

        FVector Projected;
        Assert_True(
            utils_nav::Try_ProjectOntoNavmesh(
                FCk_Handle(_Follower),
                _Start,
                25.0f,
                Projected,
                300.0f),
            "local-shortcut start must be on the AutoTests navmesh");
        Assert_True(
            utils_nav::Try_ProjectOntoNavmesh(
                FCk_Handle(_Follower),
                _Goal,
                25.0f,
                Projected,
                300.0f),
            "local-shortcut goal must be on the AutoTests navmesh");
        Assert_True(
            utils_nav::Try_ProjectOntoNavmesh(
                FCk_Handle(_Follower),
                _LeftGapNode,
                25.0f,
                Projected,
                300.0f),
            "left local-gap node must be on the AutoTests navmesh");
        Assert_True(
            utils_nav::Try_ProjectOntoNavmesh(
                FCk_Handle(_Follower),
                _RightGapNode,
                25.0f,
                Projected,
                300.0f),
            "right local-gap node must be on the AutoTests navmesh");

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

        Assert_True(
            InResult.Get_Status()
                == ECk_PathNetwork_RouteStatus::Ready,
            f"local-shortcut route must be Ready, got {InResult.Get_Status()}");

        auto HasExpectedLocalGap = false;
        auto OffPathLegCount = 0;
        for (const auto& Leg : InResult.Get_Legs())
        {
            if (Leg.Get_LegType()
                != ECk_PathNetwork_CorridorLegType::OffPath)
            { continue; }

            ++OffPathLegCount;
            const auto Waypoints = Leg.Get_Waypoints();
            if (Waypoints.Num() < 2)
            { continue; }

            const auto First = Waypoints[0];
            const auto Last = Waypoints[Waypoints.Num() - 1];
            const bool ForwardGap =
                (First - _LeftGapNode).Size() <= 1.0f
                && (Last - _RightGapNode).Size() <= 1.0f;
            const bool ReverseGap =
                (First - _RightGapNode).Size() <= 1.0f
                && (Last - _LeftGapNode).Size() <= 1.0f;
            HasExpectedLocalGap =
                HasExpectedLocalGap
                || ForwardGap
                || ReverseGap;
        }

        Assert_True(
            OffPathLegCount >= 3,
            f"route must contain start, local-gap, and goal off-path legs, got {OffPathLegCount}");
        Assert_True(
            HasExpectedLocalGap,
            "route must contain the exact 850cm network-to-network local gap, not a whole-trip direct fallback");
        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedRouteFailed(
        FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }

        const auto Result =
            utils_path_network_follower::Get_RouteResult(
                InFollower);
        FinishFailure(
            f"navmesh-valid local shortcut unexpectedly failed with {Result.Get_FailReason()}");
    }
}
