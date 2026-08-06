// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: BLOCKER LIFECYCLE
//============================================================================
//
// Drives a single GridBlocker through its full state machine and asserts the
// counted Disabled tag on the covered cell tracks each transition:
//
//   1. Active blocker on spawn          -> cell (2,2) becomes Disabled.
//   2. Request_SetActive(false)         -> cell (2,2) becomes Enabled.
//   3. Request_SetActive(true)          -> cell (2,2) becomes Disabled again.
//   4. Request_DestroyEntity(blocker)   -> death-watch un-stamps; cell Enabled.
//
// All transitions are deferred (processor-driven), so we poll via a recurring
// tick and advance a small step-machine, waiting for each expected cell state
// before issuing the next request.
//============================================================================

class UCk_AutoTest_Grid_BlockerLifecycle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _BlockerEntity;
    private int32 _Step = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto GridOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_2dGridSystem_Spec(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        _Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        _BlockerEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto BP = FCk_2dGridBlocker_Spec(_Grid, FIntPoint(2, 2), FIntPoint(2, 2));
        utils_2d_grid_blocker::Add(_BlockerEntity, BP);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private bool IsCellDisabled(FIntPoint InCoord)
    {
        auto Cell = utils_2d_grid_system::Get_CellAt(_Grid, InCoord);
        return ck::IsValid(Cell) ? utils_2d_grid_cell::Get_IsDisabled(Cell) : false;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Coord = FIntPoint(2, 2);

        if (_Step == 0)
        {
            // Wait for the active blocker to stamp the cell.
            if (IsCellDisabled(Coord))
            {
                Assert_True(true, "Active blocker disables covered cell (2,2)");
                utils_2d_grid_blocker::Request_SetActive(_BlockerEntity.As_2dGridBlocker(), false);
                _Step = 1;
            }
            return;
        }

        if (_Step == 1)
        {
            // Wait for deactivation to release the cell.
            if (!IsCellDisabled(Coord))
            {
                Assert_True(true, "Deactivated blocker re-enables covered cell (2,2)");
                utils_2d_grid_blocker::Request_SetActive(_BlockerEntity.As_2dGridBlocker(), true);
                _Step = 2;
            }
            return;
        }

        if (_Step == 2)
        {
            // Wait for reactivation to disable the cell again.
            if (IsCellDisabled(Coord))
            {
                Assert_True(true, "Reactivated blocker disables covered cell (2,2) again");
                utils_entity_lifetime::Request_DestroyEntity(_BlockerEntity);
                _Step = 3;
            }
            return;
        }

        if (_Step == 3)
        {
            // Wait for the death-watch un-stamp on destruction.
            if (!IsCellDisabled(Coord))
            {
                Assert_True(true, "Destroying the blocker un-stamps covered cell (2,2)");
                FinishSuccess();
            }
            return;
        }
    }
}
