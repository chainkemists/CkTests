// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: ADD AND CELL COUNT
//============================================================================
//
// Smoke test for the 2D grid system add path:
//   1. Create a transient owner with a transform.
//   2. Add a 4x3 grid (12 cells, 100x100 each).
//   3. ForEach_Cell with NoFilter returns 12 cells.
//   4. Each returned cell responds to Get_Coordinate with an in-range value
//      (functional check that doesn't require Cell.H() - which needs a
//      mutable cell ref the for-loop's `auto Cell` doesn't provide).
//
// All operations resolve in DoBeginPlay.
//============================================================================

class UCk_AutoTest_Grid_AddAndDimensions : UCk_AutoTest_Base
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
            FIntPoint(4, 3), FVector2D(100.0f, 100.0f));
        Params.Set_DefaultCellState(ECk_EnableDisable::Enable);

        auto Grid = utils_2d_grid_system::Add(OwnerTransform, Params);
        Assert_True(ck::IsValid(Grid),
            "utils_2d_grid_system::Add should return a valid grid handle");

        auto Cells = utils_2d_grid_system::ForEach_Cell(Grid, ECk_2dGridSystem_CellFilter::NoFilter);
        Assert_Equals_Int(Cells.Num(), 12,
            "A 4x3 grid should yield 12 cells under NoFilter");

        for (auto Cell : Cells)
        {
            auto Coord = utils_2d_grid_cell::Get_Coordinate(
                Cell, ECk_2dGridSystem_CoordinateType::Rotated);
            Assert_True(Coord.X >= 0 && Coord.Y >= 0,
                f"Cell coordinate should be in-range (got {Coord.X},{Coord.Y})");
        }

        FinishSuccess();
    }
}
