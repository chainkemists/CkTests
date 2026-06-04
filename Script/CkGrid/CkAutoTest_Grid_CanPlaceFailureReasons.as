// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: GET_CANPLACE FAILURE REASONS + OUT-OF-BOUNDS
//============================================================================
//
// RejectsDisabledOccupied checks that disabled/occupied cells fail, but never
// inspects the FCk_2dGridPlacement_Result struct or the out-of-bounds path.
// This pins the result struct (Reason + FailedCells) across failure modes:
//
//   1. Out-of-bounds, single cell: a 1x1 at (10,10) on a 10x10 grid (valid
//      coords 0..9) -> CanPlace false, Reason == OutOfBounds, FailedCells = {(10,10)}.
//   2. Out-of-bounds, straddling the right edge: a 2x1 anchored at (9,5) (None
//      -> cells (9,5),(10,5)) -> false, OutOfBounds, FailedCells contains (10,5)
//      ONLY (the in-bounds (9,5) is fine, so only the oob cell is recorded).
//   3. Disabled-cell reason: disable (3,3) and place a 1x1 there -> false,
//      Reason == Disabled, FailedCells = {(3,3)}.
//
// Get_CanPlace is side-effect free and Request_EnableDisable is an immediate tag
// flip, so the whole test runs synchronously in DoBeginPlay.
//============================================================================

class UCk_AutoTest_Grid_CanPlaceFailureReasons : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto GridOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        // ---- 1. Out-of-bounds, single 1x1 at (10,10). ----
        auto SingleEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto SingleObj = utils_2d_grid_object::Add(
            SingleEntity, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        auto Oob = utils_2d_grid_placement::Get_CanPlace(
            Grid, SingleObj, FIntPoint(10, 10),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(Oob.Get_CanPlace() == false,
            "1x1 @ (10,10) on a 10x10 grid is out of bounds -> rejected");
        Assert_True(Oob.Get_Reason() == ECk_2dGridPlacement_Failure::OutOfBounds,
            "1x1 @ (10,10): failure reason must be OutOfBounds");
        Assert_True(Oob.Get_FailedCells().Contains(FIntPoint(10, 10)),
            "1x1 @ (10,10): FailedCells must contain the out-of-bounds coord (10,10)");
        Assert_Equals_Int(Oob.Get_FailedCells().Num(), 1,
            "1x1 @ (10,10): exactly one failing cell");

        // ---- 2. 2x1 straddling the right edge: (9,5),(10,5). ----
        auto RectEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto RectObj = utils_2d_grid_object::Add(
            RectEntity, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(2, 1)));

        auto Straddle = utils_2d_grid_placement::Get_CanPlace(
            Grid, RectObj, FIntPoint(9, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(Straddle.Get_CanPlace() == false,
            "2x1 @ (9,5) None spans (9,5),(10,5) -> (10,5) is out of bounds -> rejected");
        Assert_True(Straddle.Get_Reason() == ECk_2dGridPlacement_Failure::OutOfBounds,
            "2x1 @ (9,5): failure reason must be OutOfBounds");
        Assert_True(Straddle.Get_FailedCells().Contains(FIntPoint(10, 5)),
            "2x1 @ (9,5): FailedCells must contain the out-of-bounds cell (10,5)");
        Assert_True(!Straddle.Get_FailedCells().Contains(FIntPoint(9, 5)),
            "2x1 @ (9,5): the in-bounds anchor cell (9,5) must NOT be recorded as failed");
        Assert_Equals_Int(Straddle.Get_FailedCells().Num(), 1,
            "2x1 @ (9,5): only the single out-of-bounds cell fails");

        // ---- 3. Disabled-cell reason: disable (3,3), place a 1x1 there. ----
        auto Cell33 = utils_2d_grid_system::Get_CellAt(Grid, FIntPoint(3, 3));
        Assert_True(ck::IsValid(Cell33), "Cell (3,3) must resolve to a valid handle");
        utils_2d_grid_cell::Request_EnableDisable(Cell33, ECk_EnableDisable::Disable);
        Assert_True(utils_2d_grid_cell::Get_IsDisabled(Cell33),
            "Cell (3,3) must report disabled after Request_EnableDisable(Disable)");

        auto Disabled = utils_2d_grid_placement::Get_CanPlace(
            Grid, SingleObj, FIntPoint(3, 3),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(Disabled.Get_CanPlace() == false,
            "1x1 @ (3,3) (disabled) -> rejected");
        Assert_True(Disabled.Get_Reason() == ECk_2dGridPlacement_Failure::Disabled,
            "1x1 @ (3,3): failure reason must be Disabled");
        Assert_True(Disabled.Get_FailedCells().Contains(FIntPoint(3, 3)),
            "1x1 @ (3,3): FailedCells must contain the disabled cell (3,3)");

        FinishSuccess();
    }
}
