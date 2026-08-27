// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: CELL COORDINATES ARE UNIQUE AND IN-RANGE
//============================================================================
//
// Verifies the per-cell coordinate query:
//   1. Create a 3x4 grid (12 cells).
//   2. ForEach_Cell, collect each cell's coordinate via
//      utils_2d_grid_cell::Get_Coordinate.
//   3. Every coordinate's X is in [0, 3), Y is in [0, 4).
//   4. All 12 coordinates are distinct (no duplicates).
//
// Catches regressions where cells get duplicate coordinates or coordinates
// fall outside the configured grid dimensions.
//============================================================================

class UCk_AutoTest_Grid_CellCoordinatesAreUnique : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto GridOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto OwnerTransform = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_2dGridSystem_ParamsData(
            FIntPoint(3, 4), FVector2D(100.0f, 100.0f));
        Params.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto Grid = utils_2d_grid_system::Add(OwnerTransform, Params);

        auto Cells = utils_2d_grid_system::ForEach_Cell(Grid, ECk_2dGridSystem_CellFilter::NoFilter);
        Assert_Equals_Int(Cells.Num(), 12, "3x4 grid should produce 12 cells");

        // Track which (X,Y) pairs we've seen - pack into a single int for set membership
        // (X * 100 + Y is unique within the small dimensions used here).
        auto SeenKeys = TSet<int32>();
        auto AllInRange = true;

        for (auto Cell : Cells)
        {
            auto Coord = utils_2d_grid_cell::Get_Coordinate(
                Cell, ECk_2dGridSystem_CoordinateType::Rotated);
            if (Coord.X < 0 || Coord.X >= 3 || Coord.Y < 0 || Coord.Y >= 4)
            {
                AllInRange = false;
            }
            SeenKeys.Add(Coord.X * 100 + Coord.Y);
        }

        Assert_True(AllInRange,
            "Every cell coordinate should fall within the grid dimensions [0,3)x[0,4)");
        Assert_Equals_Int(SeenKeys.Num(), 12,
            "All 12 cell coordinates should be distinct");

        FinishSuccess();
    }
}
