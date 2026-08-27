// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: CELLS RESPECT DefaultCellState
//============================================================================
//
// Verifies the DefaultCellState param is honored at construction time:
//   1. Create a 3x3 grid with DefaultCellState=Enable.
//   2. Every cell reports Get_IsDisabled == false.
//
// Then create a second grid with DefaultCellState=Disable:
//   3. Every cell reports Get_IsDisabled == true.
//
// Pins down the contract that grid cells take on the default state at
// add time rather than always defaulting to Enabled.
//============================================================================

class UCk_AutoTest_Grid_CellsAreEnabledByDefault : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Enabled grid
        auto EnabledOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto EnabledTransform = utils_transform::Add(
            EnabledOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto EnabledParams = FCk_Fragment_2dGridSystem_ParamsData(
            FIntPoint(3, 3), FVector2D(100.0f, 100.0f));
        EnabledParams.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto EnabledGrid = utils_2d_grid_system::Add(EnabledTransform, EnabledParams);

        auto EnabledCells = utils_2d_grid_system::ForEach_Cell(
            EnabledGrid, ECk_2dGridSystem_CellFilter::NoFilter);
        Assert_Equals_Int(EnabledCells.Num(), 9, "3x3 grid should yield 9 cells");

        for (auto Cell : EnabledCells)
        {
            Assert_True(!utils_2d_grid_cell::Get_IsDisabled(Cell),
                "Cells in a grid with DefaultCellState=Enable should report IsDisabled=false");
        }

        // Disabled grid
        auto DisabledOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto DisabledTransform = utils_transform::Add(
            DisabledOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto DisabledParams = FCk_Fragment_2dGridSystem_ParamsData(
            FIntPoint(3, 3), FVector2D(100.0f, 100.0f));
        DisabledParams.Set_DefaultCellState(ECk_EnableDisable::Disable);
        auto DisabledGrid = utils_2d_grid_system::Add(DisabledTransform, DisabledParams);

        auto DisabledCells = utils_2d_grid_system::ForEach_Cell(
            DisabledGrid, ECk_2dGridSystem_CellFilter::NoFilter);

        for (auto Cell : DisabledCells)
        {
            Assert_True(utils_2d_grid_cell::Get_IsDisabled(Cell),
                "Cells in a grid with DefaultCellState=Disable should report IsDisabled=true");
        }

        FinishSuccess();
    }
}
