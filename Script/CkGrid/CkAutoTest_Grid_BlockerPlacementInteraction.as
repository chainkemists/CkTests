// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: BLOCKER <-> PLACEMENT + SHAPE/BLOCKER REFCOUNT
//============================================================================
//
// BlockerLifecycle/NamedToggle drive a blocker's state machine against the
// cell's IsDisabled flag, but never cross-check the PLACEMENT layer, and never
// stack a blocker on top of a shape-disabled cell. This pins both:
//
//   Part A - blocker gates placement, and toggling re-opens it:
//     Grid 10x10, DefaultCellState=Enable, ExceptionCoordinates={(2,2)} (a
//     shape-disabled cell). A blocker covers (5,5).
//       - poll until (5,5) disabled: CanPlace(1x1 @ (5,5)) == false (Disabled).
//       - Request_SetActive(blocker,false): poll until (5,5) IsDisabled==false
//         AND CanPlace @ (5,5) == true; Request_Place there succeeds (valid
//         placement handle + occupancy stamps).
//       - Request_SetActive(blocker,true): poll until (5,5) disabled again.
//         (placement was removed below before re-blocking so the re-block is
//          observable on a freed cell.)
//
//   Part B - shape-disable + blocker-disable share ONE counted Disabled tag:
//     A second blocker covers the shape-disabled (2,2). The shape contributed a
//     counted Disabled stamp at construction; the blocker adds a second. When
//     that blocker deactivates it releases ITS stamp only - (2,2) STAYS disabled
//     because the shape's stamp still holds. This pins that the two sources hit
//     the same refcounted tag and the blocker release does not underflow it.
//============================================================================

class UCk_AutoTest_Grid_BlockerPlacementInteraction : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem  _Grid;
    private FCk_Handle               _Object;
    private FCk_Handle               _BlockerAt55Entity;
    private FCk_Handle_2dGridBlocker _BlockerAt55;
    private FCk_Handle               _BlockerAt22Entity;
    private FCk_Handle_2dGridBlocker _BlockerAt22;
    private FCk_Handle_2dGridPlacement _Placement;
    private int32 _Step = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto GridOwner  = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto Exceptions = TArray<FIntPoint>();
        Exceptions.Add(FIntPoint(2, 2));
        GP.Set_ExceptionCoordinates(Exceptions);
        _Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        // 1x1 object used for placement probes.
        _Object = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_Object, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        // Blocker over (5,5).
        _BlockerAt55Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto BP55 = FCk_Fragment_2dGridBlocker_ParamsData(_Grid, FIntPoint(5, 5), FIntPoint(5, 5));
        _BlockerAt55 = utils_2d_grid_blocker::Add(_BlockerAt55Entity, BP55);

        // Blocker covering the shape-disabled (2,2) AND an open neighbour (2,3).
        // (2,2) gets a SECOND counted Disabled stamp (shape + blocker); (2,3) gets
        // its only stamp from this blocker. When the blocker deactivates, (2,3)
        // re-enables (our "deactivation processed" signal) while (2,2) must stay
        // disabled (the shape stamp still holds the refcount).
        _BlockerAt22Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto BP22 = FCk_Fragment_2dGridBlocker_ParamsData(_Grid, FIntPoint(2, 2), FIntPoint(2, 3));
        _BlockerAt22 = utils_2d_grid_blocker::Add(_BlockerAt22Entity, BP22);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private bool IsCellDisabled(FIntPoint InCoord)
    {
        auto Cell = utils_2d_grid_system::Get_CellAt(_Grid, InCoord);
        return ck::IsValid(Cell) ? utils_2d_grid_cell::Get_IsDisabled(Cell) : false;
    }

    private bool CanPlaceAt(FIntPoint InCoord)
    {
        auto R = utils_2d_grid_placement::Get_CanPlace(
            _Grid, _Object.As_2dGridObject(), InCoord,
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        return R.Get_CanPlace();
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_Step == 0)
        {
            // Wait until BOTH blockers have stamped their cells.
            if (IsCellDisabled(FIntPoint(5, 5)) &&
                IsCellDisabled(FIntPoint(2, 2)) &&
                IsCellDisabled(FIntPoint(2, 3)))
            {
                Assert_True(CanPlaceAt(FIntPoint(5, 5)) == false,
                    "1x1 @ (5,5): active blocker disables the cell -> CanPlace false");

                // Deactivate the (5,5) blocker; expect the cell to re-open.
                utils_2d_grid_blocker::Request_SetActive(_BlockerAt55, false);
                _Step = 1;
            }
            return;
        }

        if (_Step == 1)
        {
            // Wait until the deactivation has freed (5,5) AND placement reflects it.
            if (!IsCellDisabled(FIntPoint(5, 5)) && CanPlaceAt(FIntPoint(5, 5)))
            {
                Assert_True(!IsCellDisabled(FIntPoint(5, 5)),
                    "Deactivating the (5,5) blocker re-enables the cell");
                Assert_True(CanPlaceAt(FIntPoint(5, 5)),
                    "1x1 @ (5,5): with the blocker off, CanPlace becomes true");

                _Placement = utils_2d_grid_placement::Request_Place(
                    _Grid, _Object, FIntPoint(5, 5), ECk_CardinalRotation::None);
                // Placement success is verified via the occupancy stamp in step 2 (AS has no
                // ck::IsValid binding for FCk_Handle_2dGridPlacement).
                _Step = 2;
            }
            return;
        }

        if (_Step == 2)
        {
            // Wait until the placement occupancy has stamped (5,5).
            if (utils_2d_grid_occupancy::Get_IsOccupied(_Grid, FIntPoint(5, 5)))
            {
                Assert_True(utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(5, 5)) == _Object,
                    "(5,5) must be occupied by the placed object");

                // Free the cell again so the re-block is observable on an open cell
                // (a blocker re-activating under a live occupant would still disable,
                //  but we want to isolate the blocker's effect here).
                utils_2d_grid_placement::Request_Remove(_Placement);
                _Step = 3;
            }
            return;
        }

        if (_Step == 3)
        {
            // Wait until the placement has been fully removed (cell free).
            if (!utils_2d_grid_occupancy::Get_IsOccupied(_Grid, FIntPoint(5, 5)))
            {
                // Re-activate the (5,5) blocker -> cell disables again.
                utils_2d_grid_blocker::Request_SetActive(_BlockerAt55, true);
                _Step = 4;
            }
            return;
        }

        if (_Step == 4)
        {
            // Wait for the re-activation to disable (5,5) again.
            if (IsCellDisabled(FIntPoint(5, 5)))
            {
                Assert_True(IsCellDisabled(FIntPoint(5, 5)),
                    "Re-activating the (5,5) blocker disables the cell again");
                Assert_True(CanPlaceAt(FIntPoint(5, 5)) == false,
                    "1x1 @ (5,5): with the blocker back on, CanPlace is false again");

                // ---- Part B: double-refcount on the shape-disabled (2,2). ----
                // (2,2) currently holds TWO counted Disabled stamps (shape + blocker).
                // Release the blocker's stamp; the shape's stamp must keep it disabled.
                utils_2d_grid_blocker::Request_SetActive(_BlockerAt22, false);
                _Step = 5;
            }
            return;
        }

        if (_Step == 5)
        {
            // Sync on the blocker's OPEN cell (2,3): once it re-enables, the
            // deactivation has been processed. The shape-disabled (2,2) shared the
            // same blocker stamp but must STAY disabled - the ExceptionCoordinate's
            // counted Disabled tag still holds it (one refcounted tag, no underflow).
            if (!IsCellDisabled(FIntPoint(2, 3)))
            {
                Assert_True(!IsCellDisabled(FIntPoint(2, 3)),
                    "Blocker's open cell (2,3) re-enables when the blocker deactivates");
                Assert_True(IsCellDisabled(FIntPoint(2, 2)),
                    "Shape-disabled (2,2) STAYS disabled after its overlapping blocker releases (shape + blocker share one refcounted Disabled tag; release must not underflow)");
                Assert_True(CanPlaceAt(FIntPoint(2, 2)) == false,
                    "1x1 @ (2,2): still rejected after the blocker release (shape-disable holds)");
                FinishSuccess();
            }
            return;
        }
    }
}
