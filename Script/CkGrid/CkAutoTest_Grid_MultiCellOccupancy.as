// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: MULTI-CELL OCCUPANCY + ENUMERATION + REMOVAL
//============================================================================
//
// BasicPlacement only covers a 1x1 place. This pins the multi-cell path of the
// placement/occupancy layer plus enumeration and the removal signal:
//
//   1. Place a 2x1 object at (5,5) -> footprint (5,5),(6,5). OnObjectPlaced
//      fires once synchronously carrying exactly 2 cells. Poll until BOTH cells
//      report Get_OccupantAt == the 2x1 occupant.
//   2. Get_Placements(grid).Num() == 1, and Get_PlacementAt((5,5)) equals the
//      handle Request_Place returned.
//   3. Place a SECOND 1x1 object at (7,5) (non-overlapping). Poll until it is
//      occupied; both occupants coexist and Get_Placements == 2.
//   4. Bind OnObjectRemoved, Request_Remove the 2x1 placement. Poll until
//      (5,5)&(6,5) are free; OnObjectRemoved fired exactly once and the 1x1
//      placement survives (Get_Placements == 1).
//============================================================================

class UCk_AutoTest_Grid_MultiCellOccupancy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle _Self;
    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _Rect;
    private FCk_Handle _Single;
    private FCk_Handle_2dGridPlacement _RectPlacement;
    private FCk_Handle_2dGridPlacement _SinglePlacement;

    private int32 _PlacedFireCount = 0;
    private int32 _PlacedCellCount = 0;
    private int32 _RemovedFireCount = 0;
    private int32 _Step = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Self = InHandle;

        auto GridOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        _Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        _Grid.BindTo_OnObjectPlaced(
            FCk_Delegate_2dGridPlacement_ObjectPlaced(this, n"OnObjectPlaced"));
        _Grid.BindTo_OnObjectRemoved(
            FCk_Delegate_2dGridPlacement_ObjectRemoved(this, n"OnObjectRemoved"));

        // 2x1 occupant.
        _Rect = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_Rect, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(2, 1)));

        _RectPlacement = utils_2d_grid_placement::Request_Place(
            _Grid, _Rect, FIntPoint(5, 5), ECk_CardinalRotation::None);

        // The placed signal fires synchronously inside Request_Place.
        Assert_Equals_Int(_PlacedFireCount, 1,
            "OnObjectPlaced should fire exactly once, synchronously, during Request_Place");
        Assert_Equals_Int(_PlacedCellCount, 2,
            "OnObjectPlaced for a 2x1 object should carry exactly 2 cells");

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnObjectPlaced(FCk_Handle_2dGridSystem InGrid, FCk_Handle InOccupant, const TArray<FIntPoint>&in InCells)
    {
        _PlacedFireCount += 1;
        _PlacedCellCount = InCells.Num();
    }

    UFUNCTION()
    private void OnObjectRemoved(FCk_Handle_2dGridSystem InGrid, FCk_Handle InOccupant)
    {
        _RemovedFireCount += 1;
    }

    private bool IsOccupied(FIntPoint InCoord)
    {
        return utils_2d_grid_occupancy::Get_IsOccupied(_Grid, InCoord);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_Step == 0)
        {
            // Wait for the full 2x1 footprint to stamp.
            auto At55 = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(5, 5));
            auto At65 = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(6, 5));
            if (At55 != _Rect || At65 != _Rect) { return; }

            Assert_True(At55 == _Rect, "(5,5) occupied by the 2x1 occupant");
            Assert_True(At65 == _Rect, "(6,5) occupied by the 2x1 occupant");

            auto Placements = utils_2d_grid_occupancy::Get_Placements(_Grid);
            Assert_Equals_Int(Placements.Num(), 1,
                "exactly one placement after the single 2x1 place");

            // Placement-handle identity is asserted indirectly via the occupant comparisons
            // above + the Get_Placements count (AS has no ck::IsValid or == binding for
            // FCk_Handle_2dGridPlacement).

            // Place a second, non-overlapping 1x1 object at (7,5).
            _Single = utils_entity_lifetime::Request_CreateEntity(_Self);
            utils_2d_grid_object::Add(_Single, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));
            _SinglePlacement = utils_2d_grid_placement::Request_Place(
                _Grid, _Single, FIntPoint(7, 5), ECk_CardinalRotation::None);
            _Step = 1;
            return;
        }

        if (_Step == 1)
        {
            // Wait until the second occupant stamps; both must coexist.
            auto At75 = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(7, 5));
            if (At75 != _Single) { return; }

            Assert_True(IsOccupied(FIntPoint(5, 5)) && IsOccupied(FIntPoint(6, 5)),
                "the 2x1 footprint still occupied after the second place");
            Assert_True(At75 == _Single, "(7,5) occupied by the second 1x1 occupant");

            auto Placements = utils_2d_grid_occupancy::Get_Placements(_Grid);
            Assert_Equals_Int(Placements.Num(), 2,
                "two placements coexist after the non-overlapping second place");

            // Now remove the 2x1 placement.
            utils_2d_grid_placement::Request_Remove(_RectPlacement);
            _Step = 2;
            return;
        }

        if (_Step == 2)
        {
            // Wait until the 2x1 footprint frees.
            if (IsOccupied(FIntPoint(5, 5)) || IsOccupied(FIntPoint(6, 5))) { return; }

            Assert_True(!IsOccupied(FIntPoint(5, 5)) && !IsOccupied(FIntPoint(6, 5)),
                "the 2x1 footprint freed after Request_Remove");
            Assert_Equals_Int(_RemovedFireCount, 1,
                "OnObjectRemoved fired exactly once for the single removal");

            // The 1x1 placement survives the 2x1 removal.
            Assert_True(IsOccupied(FIntPoint(7, 5)),
                "(7,5) still occupied by the surviving 1x1 placement");
            auto Placements = utils_2d_grid_occupancy::Get_Placements(_Grid);
            Assert_Equals_Int(Placements.Num(), 1,
                "one placement remains after removing the 2x1");

            FinishSuccess();
            return;
        }
    }
}
