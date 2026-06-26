// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: DISJOINT GRIDS HAVE NO INTERSECTIONS
//============================================================================
//
// Verifies that two grids placed far apart return zero intersecting cells:
//   1. GridA: 3x3 cells of 100x100, located at world (0, 0, 0).
//   2. GridB: 3x3 cells of 100x100, located at world (10000, 0, 0).
//   3. Get_IntersectingCells(A, B) returns an empty array.
//
// Catches the regression where the spatial query returns false-positive
// intersections — game code that drives placement off this query (e.g.
// inventory snap, tile-based placement validation) would otherwise let
// disjoint grids look like they overlap.
//
// Pairs with the existing Grid_AddAndDimensions / CellsAreEnabledByDefault
// / CellCoordinatesAreUnique tests on the structural side; this test
// covers the spatial-query side.
//============================================================================

class UCk_AutoTest_Grid_DisjointIntersection : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // GridA at origin
        auto OwnerA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto TransformA = utils_transform::Add(
            OwnerA, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto ParamsA = FCk_Fragment_2dGridSystem_ParamsData(
            FIntPoint(3, 3), FVector2D(100.0f, 100.0f));
        ParamsA.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto GridA = utils_2d_grid_system::Add(TransformA, ParamsA);

        // GridB located 10000 units away on the X axis
        auto OwnerB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto FarTransform = FTransform(
            FRotator::ZeroRotator,
            FVector(10000.0f, 0.0f, 0.0f),
            FVector::OneVector);
        auto TransformB = utils_transform::Add(
            OwnerB, FarTransform, ECk_Replication::DoesNotReplicate);
        auto ParamsB = FCk_Fragment_2dGridSystem_ParamsData(
            FIntPoint(3, 3), FVector2D(100.0f, 100.0f));
        ParamsB.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto GridB = utils_2d_grid_system::Add(TransformB, ParamsB);

        auto Intersections = utils_2d_grid_system::Get_IntersectingCells(GridA, GridB);
        Assert_Equals_Int(Intersections.Num(), 0,
            "Get_IntersectingCells should return 0 for grids placed 10000 units apart");

        FinishSuccess();
    }
}
