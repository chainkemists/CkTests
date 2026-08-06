// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: INTERSECTION CARDINALITY (EXACT COUNT)
//============================================================================
//
// Existing OverlappingIntersection asserts only `Intersections.Num() > 0`,
// which would silently pass even if the spatial query collapsed to "any
// intersection at all = 1 cell". This test pins the exact cardinality of
// the result for two perfectly co-located 3x3 grids: every cell of A
// matches the corresponding cell of B, so the intersecting-cell count
// must be exactly 9.
//
// Catches: regressions where a stride/index off-by-one drops cells, or
// where a duplicate-merging step over-collapses unique pairs.
//============================================================================

class UCk_AutoTest_Grid_IntersectionCardinality : UCk_AutoTest_Base
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
        Assert_Equals_Int(Intersections.Num(), 9,
            f"Two perfectly co-located 3x3 grids should produce exactly 9 intersecting cells (got {Intersections.Num()})");

        FinishSuccess();
    }
}
