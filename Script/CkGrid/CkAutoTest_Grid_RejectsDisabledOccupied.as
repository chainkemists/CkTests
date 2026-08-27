// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: PLACEMENT REJECTS DISABLED + OCCUPIED CELLS
//============================================================================
//
// Pins the validation half of the unifying placement layer (Get_CanPlace):
//
//   1. Build a 10x10 enabled grid with (7,7) flipped disabled via
//      ExceptionCoordinates. Get_CanPlace for a 1x1 object at (7,7) is FALSE
//      (cell is disabled).
//   2. Request_Place object A at (5,5); poll until occupancy is queryable.
//   3. Get_CanPlace for a 1x1 object B at (5,5) is FALSE (cell is occupied).
//      Then FinishSuccess.
//============================================================================

class UCk_AutoTest_Grid_RejectsDisabledOccupied : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _ObjectA;
    private FCk_Handle _ObjectB;
    private FCk_Handle_2dGridPlacement _PlacementA;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto GridOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto Exceptions = TArray<FIntPoint>();
        Exceptions.Add(FIntPoint(7, 7));
        GP.Set_ExceptionCoordinates(Exceptions);
        _Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        _ObjectA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_ObjectA, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        _ObjectB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_ObjectB, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        // (7,7) is disabled -> placement rejected.
        auto CanPlaceDisabled = utils_2d_grid_placement::Get_CanPlace(
            _Grid, _ObjectA.As_2dGridObject(), FIntPoint(7, 7),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(CanPlaceDisabled.Get_CanPlace() == false,
            "Get_CanPlace on a disabled cell (7,7) must be false");

        _PlacementA = utils_2d_grid_placement::Request_Place(
            _Grid, _ObjectA, FIntPoint(5, 5), ECk_CardinalRotation::None);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto OccupantAt = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(5, 5));
        if (OccupantAt == _ObjectA)
        {
            auto CanPlaceOccupied = utils_2d_grid_placement::Get_CanPlace(
                _Grid, _ObjectB.As_2dGridObject(), FIntPoint(5, 5),
                ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
            Assert_True(CanPlaceOccupied.Get_CanPlace() == false,
                "Get_CanPlace on an occupied cell (5,5) must be false");
            FinishSuccess();
        }
    }
}
