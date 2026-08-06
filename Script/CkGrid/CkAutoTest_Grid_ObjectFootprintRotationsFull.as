// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: OBJECT FOOTPRINT ROTATIONS (FULL COVERAGE)
//============================================================================
//
// Extends ObjectFootprintResolves to pin the rest of Get_ResolvedCells:
//
//   1. Rectangle symmetry: a 2x1's Half rotation resolves to the SAME cell set
//      as None, and its ThreeQuarter resolves to the SAME set as Quarter
//      (a 2x1 is 180-symmetric, so {None,Half} and {Quarter,ThreeQuarter} pair).
//   2. Anchor offset shifts the whole footprint by the offset vector (applied
//      uniformly in rotated/world space, AFTER rotation+normalize) — pinned at
//      rotation None and composed with a Quarter rotation.
//   3. Even-extent centering: a 2x2 with Center centering, None rotation,
//      pins the integer-truncation center offset (RotatedExtent/2 = (1,1)).
//
// Get_ResolvedCells is side-effect free and immediate, so the whole test runs
// synchronously in DoBeginPlay.
//============================================================================

class UCk_AutoTest_Grid_ObjectFootprintRotationsFull : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // ---- 1. Rectangle 180-symmetry of a 2x1. ----
        auto RectParams = FCk_2dGridObject_Spec(FIntPoint(2, 1));
        auto Rect = utils_2d_grid_object::Add(
            utils_entity_lifetime::Request_CreateEntity(LocalHandle), RectParams);

        auto RNone = utils_2d_grid_object::Get_ResolvedCells(Rect, FIntPoint(5, 5), ECk_CardinalRotation::None);
        auto RHalf = utils_2d_grid_object::Get_ResolvedCells(Rect, FIntPoint(5, 5), ECk_CardinalRotation::Half);
        Assert_Equals_Int(RNone.Num(), 2, "2x1 None covers 2 cells");
        Assert_Equals_Int(RHalf.Num(), 2, "2x1 Half covers 2 cells");
        Assert_True(RNone.Contains(FIntPoint(5,5)) && RNone.Contains(FIntPoint(6,5)),
            "2x1 @ (5,5) None -> (5,5),(6,5)");
        Assert_True(RHalf.Contains(FIntPoint(5,5)) && RHalf.Contains(FIntPoint(6,5)),
            "2x1 @ (5,5) Half -> (5,5),(6,5) (SAME cell set as None; rectangle is 180-symmetric)");

        auto RQuarter = utils_2d_grid_object::Get_ResolvedCells(Rect, FIntPoint(5, 5), ECk_CardinalRotation::Quarter);
        auto RThreeQ  = utils_2d_grid_object::Get_ResolvedCells(Rect, FIntPoint(5, 5), ECk_CardinalRotation::ThreeQuarter);
        Assert_Equals_Int(RQuarter.Num(), 2, "2x1 Quarter covers 2 cells");
        Assert_Equals_Int(RThreeQ.Num(), 2, "2x1 ThreeQuarter covers 2 cells");
        Assert_True(RQuarter.Contains(FIntPoint(5,5)) && RQuarter.Contains(FIntPoint(5,6)),
            "2x1 @ (5,5) Quarter -> (5,5),(5,6)");
        Assert_True(RThreeQ.Contains(FIntPoint(5,5)) && RThreeQ.Contains(FIntPoint(5,6)),
            "2x1 @ (5,5) ThreeQuarter -> (5,5),(5,6) (SAME cell set as Quarter; 180-symmetric)");

        // ---- 2. Anchor offset shifts the footprint (breaks the symmetry). ----
        auto OffsetParams = FCk_2dGridObject_Spec(FIntPoint(2, 1));
        OffsetParams.Set_AnchorOffset(FIntPoint(1, 0));
        auto OffsetObj = utils_2d_grid_object::Add(
            utils_entity_lifetime::Request_CreateEntity(LocalHandle), OffsetParams);

        // None: raw {(0,0),(1,0)} + anchor(5,5) + offset(1,0) -> {(6,5),(7,5)}.
        auto ONone = utils_2d_grid_object::Get_ResolvedCells(OffsetObj, FIntPoint(5, 5), ECk_CardinalRotation::None);
        Assert_Equals_Int(ONone.Num(), 2, "offset 2x1 None covers 2 cells");
        Assert_True(ONone.Contains(FIntPoint(6,5)) && ONone.Contains(FIntPoint(7,5)),
            "offset (1,0) 2x1 @ (5,5) None -> (6,5),(7,5) (footprint shifted by the offset)");

        // Quarter: rotated {(0,0),(0,1)} + anchor(5,5) + offset(1,0) -> {(6,5),(6,6)}.
        auto OQuarter = utils_2d_grid_object::Get_ResolvedCells(OffsetObj, FIntPoint(5, 5), ECk_CardinalRotation::Quarter);
        Assert_Equals_Int(OQuarter.Num(), 2, "offset 2x1 Quarter covers 2 cells");
        Assert_True(OQuarter.Contains(FIntPoint(6,5)) && OQuarter.Contains(FIntPoint(6,6)),
            "offset (1,0) 2x1 @ (5,5) Quarter -> (6,5),(6,6) (offset added uniformly in rotated space)");

        // ---- 3. Even-extent centering: 2x2 Center, None. ----
        // RotatedExtent (2,2) -> CenterOffset (1,1). cells = anchor + raw - (1,1).
        auto SquareParams = FCk_2dGridObject_Spec(FIntPoint(2, 2));
        SquareParams.Set_Centering(ECk_GridObject_Centering::Center);
        auto Square = utils_2d_grid_object::Add(
            utils_entity_lifetime::Request_CreateEntity(LocalHandle), SquareParams);

        auto SNone = utils_2d_grid_object::Get_ResolvedCells(Square, FIntPoint(5, 5), ECk_CardinalRotation::None);
        Assert_Equals_Int(SNone.Num(), 4, "center 2x2 covers 4 cells");
        Assert_True(
            SNone.Contains(FIntPoint(4,4)) && SNone.Contains(FIntPoint(5,4)) &&
            SNone.Contains(FIntPoint(4,5)) && SNone.Contains(FIntPoint(5,5)),
            "center 2x2 @ (5,5) None -> (4,4),(5,4),(4,5),(5,5) (CenterOffset (1,1) by integer truncation)");

        FinishSuccess();
    }
}
