// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: REQUIRE-CONNECTED POSITIVE / TRIVIAL EDGES
//============================================================================
//
// CkAutoTest_Grid_RequireConnectedFootprint already pins the NEGATIVE branch:
// a 3x1 footprint whose MIDDLE cell is disabled by a blocker splits into two
// 4-connected components, so RequireConnected returns CanPlace==false with the
// far cell (7,5) reported in FailedCells.
//
// That test never exercises the cases where RequireConnected should PASS. This
// adds only the genuinely-missing positive/trivial edges of the same branch:
//
//   (a) Trivial single-cell: a 1x1 footprint under RequireConnected -> true.
//       In Get_CanPlace the connectivity flood is gated on Cells.Num() > 1, so a
//       1x1 footprint skips the BFS entirely and is trivially connected.
//
//   (b) Positive multi-cell: a 3x1 footprint on all-open cells under
//       RequireConnected -> true, with no FailedCells. The 4-neighbour BFS from
//       the anchor reaches every footprint cell (none are walls), so the
//       footprint forms a single connected component.
//
//   (c) Sanity: the SAME 3x1 object under connectivity Ignore is also true on
//       open cells (pins that RequireConnected is not stricter than Ignore when
//       the footprint is genuinely connected).
//
// Get_CanPlace is side-effect free and these fixtures use no blockers, so the
// whole test runs synchronously in DoBeginPlay.
//============================================================================

class UCk_AutoTest_Grid_ConnectivityEdges : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto GridOwner  = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        // ---- (a) Trivial single-cell under RequireConnected. ----
        auto SingleEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto SingleObj = utils_2d_grid_object::Add(
            SingleEntity, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        auto SingleConnected = utils_2d_grid_placement::Get_CanPlace(
            Grid, SingleObj, FIntPoint(5, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::RequireConnected);
        Assert_True(SingleConnected.Get_CanPlace() == true,
            "1x1 @ (5,5) RequireConnected: a single-cell footprint is trivially connected -> allowed");
        Assert_Equals_Int(SingleConnected.Get_FailedCells().Num(), 0,
            "1x1 @ (5,5) RequireConnected: no failing cells on an open single-cell footprint");

        // ---- (b) Positive multi-cell under RequireConnected on open cells. ----
        auto RectEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto RectObj = utils_2d_grid_object::Add(
            RectEntity, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(3, 1)));

        auto RectConnected = utils_2d_grid_placement::Get_CanPlace(
            Grid, RectObj, FIntPoint(5, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::RequireConnected);
        Assert_True(RectConnected.Get_CanPlace() == true,
            "3x1 @ (5,5) RequireConnected on open cells: footprint forms one connected component -> allowed");
        Assert_Equals_Int(RectConnected.Get_FailedCells().Num(), 0,
            "3x1 @ (5,5) RequireConnected: a fully-open footprint reports no failing cells");

        // ---- (c) Sanity: same object/anchor under Ignore is also allowed. ----
        auto RectIgnore = utils_2d_grid_placement::Get_CanPlace(
            Grid, RectObj, FIntPoint(5, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(RectIgnore.Get_CanPlace() == true,
            "3x1 @ (5,5) Ignore: open footprint is allowed (RequireConnected is no stricter when connected)");

        FinishSuccess();
    }
}
