// Language=angelscript

//============================================================================
// CK PATH NETWORK — COMPONENT TRANSFER USES DISCONNECTED ISLANDS
//============================================================================
//
// Two sidewalk ribbons are deliberately farther apart than the build snap
// radius, so they remain separate graph components. An enabled 150cm component
// transfer must bridge their 100cm gap through navmesh while charging the
// long-trip off-network multiplier:
//
//   start  A================A  --gap--  B================B  goal
//   -450  -425             -50         50              425  450
//
// With the transfer disabled, graph topology cannot traverse both ribbons.
// This fixture opts in and verifies the published route contains both on-ribbon
// islands plus the explicit off-network transfer between them.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_ComponentTransferUsesDisconnectedIslands
    : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private const FVector _Start = FVector(-450.0f, 0.0f, 0.0f);
    private const FVector _Goal = FVector(450.0f, 0.0f, 0.0f);

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

        TArray<FCk_PathNetwork_RibbonPoint> IslandA;
        IslandA.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(-425.0f, 0.0f, 0.0f),
                75.0f));
        IslandA.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(-50.0f, 0.0f, 0.0f),
                75.0f));

        TArray<FCk_PathNetwork_RibbonPoint> IslandB;
        IslandB.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(50.0f, 0.0f, 0.0f),
                75.0f));
        IslandB.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(425.0f, 0.0f, 0.0f),
                75.0f));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(IslandA));
        Ribbons.Add(FCk_PathNetwork_Ribbon(IslandB));

        auto BuildParams = FCk_PathNetwork_BuildParams();
        BuildParams.Set_NodeSnapRadius(25.0f);
        auto NetworkParams =
            FCk_PathNetwork_Spec(Ribbons);
        NetworkParams.Set_BuildParams(BuildParams);
        _Network =
            utils_path_network::Add(
                LocalHandle,
                NetworkParams);

        auto FollowerParams =
            FCk_PathNetworkFollower_Spec();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_OffPathCostMultiplier(8.0f);
        FollowerParams.Set_NearEndpointCostMultiplier(1.5f);
        FollowerParams.Set_EndpointJoinMaxDistance(100.0f);
        FollowerParams.Set_ComponentTransferMaxDistance(150.0f);
        FollowerParams.Set_DirectTripGraceDistance(0.0f);
        FollowerParams.Set_CorridorWaypointSpacing(75.0f);
        _Follower =
            utils_path_network_follower::Add(
                LocalHandle,
                FollowerParams);

        Assert_True(
            ck::IsValid(_Follower),
            "component-transfer fixture must create a valid follower");

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
            "disconnected-island network must build before route request");
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
            f"component-transfer route must be Ready, got {InResult.Get_Status()}");

        auto OnRibbonLegCount = 0;
        auto OffPathLegCount = 0;
        for (const auto& Leg : InResult.Get_Legs())
        {
            if (Leg.Get_LegType()
                == ECk_PathNetwork_CorridorLegType::OnRibbon)
            {
                ++OnRibbonLegCount;
            }
            else if (Leg.Get_LegType()
                == ECk_PathNetwork_CorridorLegType::OffPath)
            {
                ++OffPathLegCount;
            }
        }

        Assert_True(
            OnRibbonLegCount >= 2,
            f"route must use both disconnected sidewalk islands, got {OnRibbonLegCount} on-ribbon legs");
        Assert_True(
            OffPathLegCount >= 3,
            f"route must include start, component-transfer, and goal connectors, got {OffPathLegCount} off-path legs");

        const auto Waypoints = InResult.Get_CompiledWaypoints();
        Assert_True(
            Waypoints.Num() >= 4,
            f"component-transfer route must compile a multi-leg path, got {Waypoints.Num()} waypoints");
        if (Waypoints.Num() > 0)
        {
            Assert_True(
                (Waypoints[Waypoints.Num() - 1] - _Goal).Size2D()
                    <= 1.0f,
                f"component-transfer route must terminate at the exact goal, got {Waypoints[Waypoints.Num() - 1]}");
        }

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
            f"navmesh-valid component transfer unexpectedly failed with {Result.Get_FailReason()}");
    }
}
