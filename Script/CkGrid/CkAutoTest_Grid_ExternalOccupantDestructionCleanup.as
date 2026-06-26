// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: EXTERNAL OCCUPANT DESTRUCTION CLEANUP
//============================================================================
//
// Lifecycle/ordering hardening: destroying the OCCUPANT entity directly (not
// via Request_Remove) must free its grid cells. The occupant death-watch
// (OnOccupantBeginDestroy) destroys the placement it owns, and the reconcile
// then un-stamps the cells.
//
//   1. Place object A (1x1) at (5,5); tick until (5,5) is Occupied.
//   2. Request_DestroyEntity(occupantA).
//   3. Tick until (5,5) is NOT Occupied; assert freed. FinishSuccess.
//============================================================================

class UCk_AutoTest_Grid_ExternalOccupantDestructionCleanup : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _ObjectA;
    private FCk_Handle_2dGridPlacement _PlacementA;
    private int32 _Step = 0;

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
        _Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        _ObjectA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_ObjectA, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        _PlacementA = utils_2d_grid_placement::Request_Place(
            _Grid, _ObjectA, FIntPoint(5, 5), ECk_CardinalRotation::None);

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
                // Destroy the occupant directly — NOT via Request_Remove. The occupant's
                // death-watch should destroy the placement it owns.
                utils_entity_lifetime::Request_DestroyEntity(_ObjectA);
                _Step = 1;
            }
            return;
        }

        if (_Step == 1)
        {
            if (!IsOccupied(FIntPoint(5, 5)))
            {
                Assert_True(!IsOccupied(FIntPoint(5, 5)),
                    "After the occupant is destroyed, its death-watch must free (5,5) via the reconcile");
                FinishSuccess();
            }
            return;
        }
    }
}
