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
    private FCk_Handle_PathNetwork _Network;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        TArray<FCk_PathNetwork_RibbonPoint> PointsA;
        PointsA.Add(FCk_PathNetwork_RibbonPoint(FVector(0.0, 0.0, 0.0), 100.0));
        PointsA.Add(FCk_PathNetwork_RibbonPoint(FVector(1000.0, 0.0, 0.0), 100.0));

        TArray<FCk_PathNetwork_RibbonPoint> PointsB;
        PointsB.Add(FCk_PathNetwork_RibbonPoint(FVector(1000.0, 0.0, 0.0), 100.0));
        PointsB.Add(FCk_PathNetwork_RibbonPoint(FVector(1000.0, 1000.0, 0.0), 100.0));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(PointsA));
        Ribbons.Add(FCk_PathNetwork_Ribbon(PointsB));

        _Network = utils_path_network::Add(LocalHandle, FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        Assert_True(ck::IsValid(_Network), "Add() must return a valid network handle");
        Assert_True(utils_path_network::Has(FCk_Handle(_Network)), "network entity must carry the feature");

        // Build happens on the setup processor's next tick.
        WaitOneFrame(n"OnNetworkBuilt");
    }

    UFUNCTION()
    private void OnNetworkBuilt(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_path_network::Get_IsBuilt(_Network),
            "network must be built one frame after Add()");

        // Two ribbons sharing endpoint (1000,0,0): fusion yields 3 nodes, 2 edges.
        Assert_Equals_Int(utils_path_network::Get_NumNodes(_Network), 3,
            "endpoint fusion should produce 3 nodes from the L");
        Assert_Equals_Int(utils_path_network::Get_NumEdges(_Network), 2,
            "the L should produce 2 edges");

        Assert_True(utils_path_network::Get_BuildEpoch(_Network) >= 1,
            f"build epoch should have advanced, got {utils_path_network::Get_BuildEpoch(_Network)}");

        // Closest-point projection: (500, 120, 0) projects onto ribbon A's centerline at (500, 0, 0).
        FVector ClosestPoint;
        const auto Found = utils_path_network::TryGet_ClosestPointOnNetwork(
            _Network, FVector(500.0, 120.0, 0.0), 500.0, ClosestPoint);

        Assert_True(Found, "closest-point query within 500cm of the centerline must succeed");
        Assert_True((ClosestPoint - FVector(500.0, 0.0, 0.0)).Size() <= 10.0,
            f"projection should land at (500,0,0), got {ClosestPoint}");

        FinishSuccess();
    }
}
