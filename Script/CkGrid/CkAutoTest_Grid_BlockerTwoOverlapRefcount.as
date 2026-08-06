// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: TWO OVERLAPPING BLOCKERS (REFCOUNT)
//============================================================================
//
// Verifies the counted Disabled tag composes across blockers:
//
//   Blocker A covers (3,3) and (3,4).
//   Blocker B covers (3,3) and (4,3).
//   (3,3) is stamped by BOTH -> Disabled count == 2.
//
// After both stamp:
//   - assert (3,3) Disabled.
// Destroy A:
//   - (3,4) was only stamped by A           -> becomes Enabled.
//   - (3,3) is still stamped by B (refcount) -> STAYS Disabled.
//============================================================================

class UCk_AutoTest_Grid_BlockerTwoOverlapRefcount : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _BlockerA;
    private FCk_Handle _BlockerB;
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

        // A covers (3,3)-(3,4): the column x=3, y in [3,4].
        _BlockerA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto AP = FCk_2dGridBlocker_Spec(_Grid, FIntPoint(3, 3), FIntPoint(3, 4));
        utils_2d_grid_blocker::Add(_BlockerA, AP);

        // B covers (3,3)-(4,3): the row y=3, x in [3,4].
        _BlockerB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto BP = FCk_2dGridBlocker_Spec(_Grid, FIntPoint(3, 3), FIntPoint(4, 3));
        utils_2d_grid_blocker::Add(_BlockerB, BP);

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

        if (_Step == 0)
        {
            // Wait until both blockers have stamped the shared cell.
            if (IsCellDisabled(FIntPoint(3, 3)) &&
                IsCellDisabled(FIntPoint(3, 4)) &&
                IsCellDisabled(FIntPoint(4, 3)))
            {
                Assert_True(true, "Shared cell (3,3) is disabled while both blockers active");
                utils_entity_lifetime::Request_DestroyEntity(_BlockerA);
                _Step = 1;
            }
            return;
        }

        if (_Step == 1)
        {
            // Wait until A's sole-owned cell (3,4) is released.
            if (!IsCellDisabled(FIntPoint(3, 4)))
            {
                Assert_True(!IsCellDisabled(FIntPoint(3, 4)),
                    "A-only cell (3,4) is enabled after destroying A");
                Assert_True(IsCellDisabled(FIntPoint(3, 3)),
                    "Shared cell (3,3) STAYS disabled after destroying A (refcount held by B)");
                FinishSuccess();
            }
            return;
        }
    }
}
