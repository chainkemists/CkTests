// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: BUILDS FROM RIBBONS
//============================================================================
//
// Verifies the network build pipeline end-to-end through the public API:
//   1. Add a path network (two authored ribbons forming an L, sharing an
//      endpoint) as a child of the test entity.
//   2. Wait one frame — FProcessor_PathNetwork_Setup consumes the NeedsBuild
//      tag on its next tick.
//   3. Assert the graph built: endpoint fusion produced 3 nodes / 2 edges,
//      the build epoch advanced, and closest-point projection lands on the
//      centerline.
//
// No navmesh required — building never consults navigation.
//============================================================================

class UCk_AutoTest_PathNetwork_BuildsFromRibbons : UCk_AutoTest_Base
{
    private FCk_Handle _WorldHandle;
    private FCk_Handle_PathNetwork _Network;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _WorldHandle = LocalHandle;

        const auto Start = FVector(12345.0, -6789.0, 0.0);
        const auto Corner = FVector(13345.0, -6789.0, 0.0);
        const auto End = FVector(13345.0, -5789.0, 0.0);

        TArray<FCk_PathNetwork_RibbonPoint> PointsA;
        PointsA.Add(FCk_PathNetwork_RibbonPoint(Start, 100.0));
        PointsA.Add(FCk_PathNetwork_RibbonPoint(Corner, 100.0));

        TArray<FCk_PathNetwork_RibbonPoint> PointsB;
        PointsB.Add(FCk_PathNetwork_RibbonPoint(Corner, 100.0));
        PointsB.Add(FCk_PathNetwork_RibbonPoint(End, 100.0));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(PointsA));
        Ribbons.Add(FCk_PathNetwork_Ribbon(PointsB));

        _Network = utils_path_network::Add(LocalHandle, FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        Assert_True(ck::IsValid(_Network), "Add() must return a valid network handle");
        Assert_True(utils_path_network::Has(FCk_Handle(_Network)), "network entity must carry the feature");

        const auto WorldRibbons = utils_path_network::Get_AllRibbonsInWorld(LocalHandle);
        Assert_True(ContainsRibbon(WorldRibbons, Start, Corner, 100.0),
            "world ribbon query must include the direct-ECS network's horizontal ribbon");
        Assert_True(ContainsRibbon(WorldRibbons, Corner, End, 100.0),
            "world ribbon query must include the direct-ECS network's vertical ribbon");
        Assert_Equals_Int(utils_path_network::Get_AllRibbonsInWorld(FCk_Handle()).Num(), 0,
            "world ribbon query must fail closed for an invalid handle");

        // Build happens on the setup processor's next tick.
        WaitUntil(n"Check_NetworkBuilt", n"OnNetworkBuilt");
    }

    UFUNCTION()
    private void Check_NetworkBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_path_network::Get_IsBuilt(_Network));
    }

    UFUNCTION()
    private void OnNetworkBuilt(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(utils_path_network::Get_IsBuilt(_Network),
            "network must be built one frame after Add()");

        // Two ribbons sharing an endpoint: fusion yields 3 nodes, 2 edges.
        Assert_Equals_Int(utils_path_network::Get_NumNodes(_Network), 3,
            "endpoint fusion should produce 3 nodes from the L");
        Assert_Equals_Int(utils_path_network::Get_NumEdges(_Network), 2,
            "the L should produce 2 edges");

        Assert_True(utils_path_network::Get_BuildEpoch(_Network) >= 1,
            f"build epoch should have advanced, got {utils_path_network::Get_BuildEpoch(_Network)}");

        // Closest-point projection onto ribbon A's centerline.
        FVector ClosestPoint;
        const auto Found = utils_path_network::TryGet_ClosestPointOnNetwork(
            _Network, FVector(12845.0, -6669.0, 0.0), 500.0, ClosestPoint);

        Assert_True(Found, "closest-point query within 500cm of the centerline must succeed");
        Assert_True((ClosestPoint - FVector(12845.0, -6789.0, 0.0)).Size() <= 10.0,
            f"projection should land on the horizontal ribbon, got {ClosestPoint}");

        FCk_Handle NetworkEntity = _Network;
        utils_entity_lifetime::Request_DestroyEntity(NetworkEntity);
        WaitOneFrame(n"OnNetworkDestroySettled");
    }

    UFUNCTION()
    private void OnNetworkDestroySettled(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        const auto WorldRibbons = utils_path_network::Get_AllRibbonsInWorld(_WorldHandle);
        const auto DestroyedRibbonIsStillVisible = ContainsRibbon(
            WorldRibbons,
            FVector(12345.0, -6789.0, 0.0),
            FVector(13345.0, -6789.0, 0.0),
            100.0);
        Assert_False(DestroyedRibbonIsStillVisible,
            "world ribbon query must exclude a network after destruction begins");

        FinishSuccess();
    }

    private bool ContainsRibbon(
        const TArray<FCk_PathNetwork_Ribbon>& InRibbons,
        FVector InStart,
        FVector InEnd,
        float InHalfWidth)
    {
        for (const auto& Ribbon : InRibbons)
        {
            const auto Points = Ribbon.Get_Points();
            if (Points.Num() != 2)
            { continue; }

            const auto WidthsMatch =
                Math::Abs(Points[0].Get_HalfWidth() - InHalfWidth) <= 0.01 &&
                Math::Abs(Points[1].Get_HalfWidth() - InHalfWidth) <= 0.01;
            const auto ForwardMatch =
                (Points[0].Get_Location() - InStart).Size() <= 0.01 &&
                (Points[1].Get_Location() - InEnd).Size() <= 0.01;
            const auto ReverseMatch =
                (Points[0].Get_Location() - InEnd).Size() <= 0.01 &&
                (Points[1].Get_Location() - InStart).Size() <= 0.01;
            if (WidthsMatch && (ForwardMatch || ReverseMatch))
            { return true; }
        }
        return false;
    }
}
