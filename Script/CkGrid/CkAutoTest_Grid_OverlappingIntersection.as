// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: OVERLAPPING GRIDS HAVE INTERSECTIONS
//============================================================================
//
// Companion to Grid_DisjointIntersection — verifies the positive case:
//   1. GridA: 3x3 cells of 100x100, located at world (0, 0, 0).
//   2. GridB: 3x3 cells of 100x100, ALSO at (0, 0, 0) (perfectly co-located).
//   3. Get_IntersectingCells(A, B) returns at least one intersection.
//
// Together with the disjoint test, this brackets the spatial-query
// contract: same-location -> matches, far-apart -> no matches. Catches
// regressions where the query always returns 0, or where the threshold
// metric inverts.
//============================================================================

class UCk_AutoTest_Grid_OverlappingIntersection : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto OwnerA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto TransformA = utils_transform::Add(
            OwnerA, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto ParamsA = FCk_2dGridSystem_Spec(
            FIntPoint(3, 3), FVector2D(100.0f, 100.0f));
        ParamsA.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto GridA = utils_2d_grid_system::Add(TransformA, ParamsA);

        auto OwnerB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto TransformB = utils_transform::Add(
            OwnerB, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto ParamsB = FCk_2dGridSystem_Spec(
            FIntPoint(3, 3), FVector2D(100.0f, 100.0f));
        ParamsB.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto GridB = utils_2d_grid_system::Add(TransformB, ParamsB);

        auto Intersections = utils_2d_grid_system::Get_IntersectingCells(GridA, GridB);
        Assert_True(Intersections.Num() > 0,
            f"Co-located grids should produce > 0 intersecting cells (got {Intersections.Num()})");

        FinishSuccess();
    }
}
