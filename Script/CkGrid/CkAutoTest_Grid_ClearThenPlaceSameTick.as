// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: CLEAR THEN PLACE SAME TICK
//============================================================================
//
// Lifecycle/ordering hardening: a same-tick Request_Remove(A) + Request_Place(B)
// on the SAME cell must reconcile to B holding the cell (not stay stuck on A's
// stale stamp, and not end up empty).
//
//   1. Place object A (1x1) at (5,5); tick until (5,5) occupant == A.
//   2. In ONE tick: Request_Remove(placementA) AND Request_Place(grid, B, (5,5)).
//      Request_Remove tags A's placement entity pending-destroy synchronously.
//      Get_OccupantAt/Get_CanPlace now skip a pending-destroy placement (see the
//      Get_PlacementAt hardening), so the cell reads FREE in the same tick and B's
//      Request_Place succeeds even though the cell's Occupied tag has not yet been
//      un-stamped by the deferred reconcile.
//   3. Tick until (5,5) occupant == B; the reconcile prunes A and re-stamps B.
//      Assert occupant == B. FinishSuccess.
//============================================================================

class UCk_AutoTest_Grid_ClearThenPlaceSameTick : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _ObjectA;
    private FCk_Handle _ObjectB;
    private FCk_Handle_2dGridPlacement _PlacementA;
    private FCk_Handle_2dGridPlacement _PlacementB;
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

        _ObjectB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_ObjectB, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        _PlacementA = utils_2d_grid_placement::Request_Place(
            _Grid, _ObjectA, FIntPoint(5, 5), ECk_CardinalRotation::None);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_Step == 0)
        {
            auto OccupantAt = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(5, 5));
            if (OccupantAt == _ObjectA)
            {
                // Same tick: remove A's placement, then place B on the same cell.
                utils_2d_grid_placement::Request_Remove(_PlacementA);
                _PlacementB = utils_2d_grid_placement::Request_Place(
                    _Grid, _ObjectB, FIntPoint(5, 5), ECk_CardinalRotation::None);
                _Step = 1;
            }
            return;
        }

        if (_Step == 1)
        {
            auto OccupantAt = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(5, 5));
            if (OccupantAt == _ObjectB)
            {
                Assert_True(OccupantAt == _ObjectB,
                    "After same-tick remove(A) + place(B), (5,5) must reconcile to B holding the cell");
                FinishSuccess();
            }
            return;
        }
    }
}
