// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: GRID OBJECT FOOTPRINT RESOLUTION
//============================================================================
//
// Pins the GridObject feature's footprint resolution:
//   1. A 2x1 anchored object resolves to the two cells (anchor, anchor+X).
//   2. The same object rotated a Quarter turn resolves to a vertical pair,
//      normalized to non-negative offsets, anchored at the same coordinate.
//   3. A 1x1 object resolves to a single cell under rotation (identity-safe).
//
// All operations resolve synchronously in DoBeginPlay.
//============================================================================

class UCk_AutoTest_Grid_ObjectFootprintResolves : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto P = FCk_Fragment_2dGridObject_ParamsData(FIntPoint(2, 1));
        auto Obj = utils_2d_grid_object::Add(Owner, P);

        auto C0 = utils_2d_grid_object::Get_ResolvedCells(Obj, FIntPoint(5, 5), ECk_CardinalRotation::None);
        Assert_Equals_Int(C0.Num(), 2, "2x1 covers 2 cells");
        Assert_True(C0.Contains(FIntPoint(5,5)) && C0.Contains(FIntPoint(6,5)), "2x1 @ (5,5) None -> (5,5),(6,5)");

        auto C90 = utils_2d_grid_object::Get_ResolvedCells(Obj, FIntPoint(5, 5), ECk_CardinalRotation::Quarter);
        Assert_Equals_Int(C90.Num(), 2, "rotated 2x1 still 2 cells");
        Assert_True(C90.Contains(FIntPoint(5,5)) && C90.Contains(FIntPoint(5,6)), "2x1 @ (5,5) Quarter -> (5,5),(5,6)");

        auto P1 = FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1));
        auto Obj1 = utils_2d_grid_object::Add(utils_entity_lifetime::Request_CreateEntity(InHandle), P1);
        auto C1 = utils_2d_grid_object::Get_ResolvedCells(Obj1, FIntPoint(3, 3), ECk_CardinalRotation::Quarter);
        Assert_Equals_Int(C1.Num(), 1, "1x1 covers 1 cell");
        Assert_True(C1.Contains(FIntPoint(3,3)), "1x1 @ (3,3) Quarter -> (3,3) (identity-safe)");

        // Center mode must survive rotation: the object spins in place around the anchor.
        auto Pc = FCk_Fragment_2dGridObject_ParamsData(FIntPoint(3, 1));
        Pc.Set_Centering(ECk_GridObject_Centering::Center);
        auto ObjC = utils_2d_grid_object::Add(utils_entity_lifetime::Request_CreateEntity(InHandle), Pc);

        auto CcN = utils_2d_grid_object::Get_ResolvedCells(ObjC, FIntPoint(5, 5), ECk_CardinalRotation::None);
        Assert_Equals_Int(CcN.Num(), 3, "center 3x1 covers 3 cells");
        Assert_True(CcN.Contains(FIntPoint(4,5)) && CcN.Contains(FIntPoint(5,5)) && CcN.Contains(FIntPoint(6,5)),
            "center 3x1 @ (5,5) None -> (4,5),(5,5),(6,5) (anchor is the middle)");

        auto CcQ = utils_2d_grid_object::Get_ResolvedCells(ObjC, FIntPoint(5, 5), ECk_CardinalRotation::Quarter);
        Assert_Equals_Int(CcQ.Num(), 3, "rotated center 3x1 still 3 cells");
        Assert_True(CcQ.Contains(FIntPoint(5,4)) && CcQ.Contains(FIntPoint(5,5)) && CcQ.Contains(FIntPoint(5,6)),
            "center 3x1 @ (5,5) Quarter -> (5,4),(5,5),(5,6) (still centered; spins in place)");

        FinishSuccess();
    }
}
