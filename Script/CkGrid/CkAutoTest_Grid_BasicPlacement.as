// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: BASIC PLACEMENT (UNIFIED PLACEMENT LAYER)
//============================================================================
//
// Exercises the unifying placement layer (validate -> stamp -> signal):
//
//   1. Build a 10x10 enabled grid and bind OnObjectPlaced.
//   2. Add a 1x1 GridObject occupant and Request_Place it at (5,5).
//      -> the OnObjectPlaced signal fires synchronously inside Request_Place,
//         carrying exactly 1 cell.
//   3. Poll until occupancy is queryable (deferred ~1 reconcile tick): assert
//      Get_OccupantAt((5,5)) == occupant, assert the signal fired exactly once,
//      then FinishSuccess.
//============================================================================

class UCk_AutoTest_Grid_BasicPlacement : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _Occupant;
    private FCk_Handle_2dGridPlacement _Placement;

    private int32 _PlacedFireCount = 0;
    private int32 _PlacedCellCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto GridOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        _Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        _Grid.BindTo_OnObjectPlaced(
            FCk_Delegate_2dGridPlacement_ObjectPlaced(this, n"OnObjectPlaced"));

        _Occupant = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_Occupant, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        _Placement = utils_2d_grid_placement::Request_Place(
            _Grid, _Occupant, FIntPoint(5, 5), ECk_CardinalRotation::None);

        // The signal fires synchronously inside Request_Place.
        Assert_Equals_Int(_PlacedFireCount, 1,
            "OnObjectPlaced should fire exactly once, synchronously, during Request_Place");
        Assert_Equals_Int(_PlacedCellCount, 1,
            "OnObjectPlaced for a 1x1 object should carry exactly 1 cell");

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnObjectPlaced(FCk_Handle_2dGridSystem InGrid, FCk_Handle InOccupant, const TArray<FIntPoint>&in InCells)
    {
        _PlacedFireCount += 1;
        _PlacedCellCount = InCells.Num();
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto OccupantAt = utils_2d_grid_placement::Get_OccupantAt(_Grid, FIntPoint(5, 5));
        if (OccupantAt == _Occupant)
        {
            Assert_Equals_Int(_PlacedFireCount, 1,
                "OnObjectPlaced should have fired exactly once for the single placement");
            FinishSuccess();
        }
    }
}
