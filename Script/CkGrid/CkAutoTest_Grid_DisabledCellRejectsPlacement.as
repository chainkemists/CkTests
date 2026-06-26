// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: DISABLED CELL REJECTS SHAPE PLACEMENT
//============================================================================
//
// Builds a 3x3 grid with DefaultCellState=Disable, then asserts:
//
//   1. Get_AllCells(OnlyActiveCells)   returns 0 cells (none active)
//   2. Get_AllCells(OnlyDisabledCells) returns 9 cells (all disabled)
//   3. Each cell reports Get_IsDisabled() == true
//   4. Get_CanFitShapeAt for a single-cell shape at any coordinate returns
//      false — placement is rejected because the cell is disabled.
//
// Counterpart 3x3 grid with DefaultCellState=Enable verifies that the
// rejection path is specific to disabled state, not a blanket "no placement".
//============================================================================

class UCk_AutoTest_Grid_DisabledCellRejectsPlacement : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Disabled-by-default grid.
        auto DisabledOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto DisabledTransform = utils_transform::Add(
            DisabledOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto DisabledParams = FCk_Fragment_2dGridSystem_ParamsData(
            FIntPoint(3, 3), FVector2D(100.0f, 100.0f));
        DisabledParams.Set_DefaultCellState(ECk_EnableDisable::Disable);
        auto DisabledGrid = utils_2d_grid_system::Add(DisabledTransform, DisabledParams);

        auto Active = utils_2d_grid_system::Get_AllCells(
            DisabledGrid, ECk_2dGridSystem_CellFilter::OnlyActiveCells);
        Assert_Equals_Int(Active.Num(), 0,
            "DisabledGrid: Get_AllCells(OnlyActiveCells) should return 0 — every cell starts disabled");

        auto Disabled = utils_2d_grid_system::Get_AllCells(
            DisabledGrid, ECk_2dGridSystem_CellFilter::OnlyDisabledCells);
        Assert_Equals_Int(Disabled.Num(), 9,
            f"DisabledGrid: Get_AllCells(OnlyDisabledCells) should return all 9 cells (got {Disabled.Num()})");

        for (auto Cell : Disabled)
        {
            Assert_True(utils_2d_grid_cell::Get_IsDisabled(Cell),
                "Each cell in a disabled-by-default grid must report Get_IsDisabled=true");
        }

        // Single-cell shape at coordinate (0,0) — placement must be rejected.
        auto SingleCellShape = TArray<FIntPoint>();
        SingleCellShape.Add(FIntPoint(0, 0));
        auto CanFitDisabled = utils_2d_grid_system::Get_CanFitShapeAt(
            DisabledGrid, SingleCellShape, FIntPoint(0, 0));
        Assert_True(CanFitDisabled == false,
            "Get_CanFitShapeAt on a disabled cell must return false (placement rejected)");

        // Counter-fixture: an enabled-by-default grid accepts the same shape.
        auto EnabledOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto EnabledTransform = utils_transform::Add(
            EnabledOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto EnabledParams = FCk_Fragment_2dGridSystem_ParamsData(
            FIntPoint(3, 3), FVector2D(100.0f, 100.0f));
        EnabledParams.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto EnabledGrid = utils_2d_grid_system::Add(EnabledTransform, EnabledParams);

        auto CanFitEnabled = utils_2d_grid_system::Get_CanFitShapeAt(
            EnabledGrid, SingleCellShape, FIntPoint(0, 0));
        Assert_True(CanFitEnabled,
            "Get_CanFitShapeAt on an enabled cell must return true — proves the rejection above is cell-state-specific, not blanket");

        FinishSuccess();
    }
}
