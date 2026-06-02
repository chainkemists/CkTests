// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: OCCUPANCY RAW STAMP
//============================================================================
//
// Exercises the raw occupancy layer (no validation): adding a placement stamps
// its cells Occupied via the reconcile processor, and removing the placement
// un-stamps them.
//
//   1. Add a placement covering (5,5) and (6,5) for an occupant entity.
//      -> wait until (5,5) is Occupied; assert (6,5) Occupied too; assert the
//         occupant at (5,5) is our occupant entity; then remove the placement.
//   2. -> wait until (5,5) is NOT Occupied; assert (6,5) freed; FinishSuccess.
//
// Stamping is processor-driven (deferred), so we poll on a recurring tick and
// advance a small step-machine.
//============================================================================

class UCk_AutoTest_Grid_OccupancyRawStamp : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _Occupant;
    private FCk_Handle_2dGridPlacement _Placement;
    private int32 _Step = 0;

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

        _Occupant = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Cells = TArray<FIntPoint>();
        Cells.Add(FIntPoint(5, 5));
        Cells.Add(FIntPoint(6, 5));

        _Placement = utils_2d_grid_occupancy::Request_AddPlacement(
            _Grid, _Occupant, FIntPoint(5, 5), ECk_CardinalRotation::None, Cells);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
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
            if (IsOccupied(FIntPoint(5, 5)))
            {
                Assert_True(IsOccupied(FIntPoint(6, 5)),
                    "Second cell (6,5) of the placement should also be Occupied");

                auto OccupantAt = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(5, 5));
                Assert_True(OccupantAt == _Occupant,
                    "Occupant reported at (5,5) should be the placement's occupant");

                utils_2d_grid_occupancy::Request_RemovePlacement(_Placement);
                _Step = 1;
            }
            return;
        }

        if (_Step == 1)
        {
            if (!IsOccupied(FIntPoint(5, 5)))
            {
                Assert_True(!IsOccupied(FIntPoint(6, 5)),
                    "Second cell (6,5) should be freed after the placement is removed");
                FinishSuccess();
            }
            return;
        }
    }
}
