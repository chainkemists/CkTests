// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: RE-PLACE SAME OCCUPANT AT A DIFFERENT ROTATION
//============================================================================
//
// Lifecycle/ordering hardening: re-placing the SAME occupant at a new rotation
// must auto-replace its previous placement (Task 7a) so the old footprint frees
// and the new footprint stamps cleanly.
//
//   1. Create a 2x1 object. Request_Place at (5,5) rotation None
//      -> footprint (5,5),(6,5). Tick until BOTH occupied.
//   2. Request_Place the SAME occupant at (5,5) rotation Quarter
//      -> footprint (5,5),(5,6). Get_CanPlace passes because (5,5) is occupied by
//         the occupant itself (SelfOccupant), and the auto-replace then frees the
//         old (6,5).
//   3. Tick until (6,5) freed AND (5,6) occupied AND (5,5) still occupied; assert.
//      FinishSuccess.
//============================================================================

class UCk_AutoTest_Grid_RePlaceDifferentRotation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _Object;
    private FCk_Handle_2dGridPlacement _Placement1;
    private FCk_Handle_2dGridPlacement _Placement2;
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

        // 2x1 footprint.
        _Object = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_Object, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(2, 1)));

        _Placement1 = utils_2d_grid_placement::Request_Place(
            _Grid, _Object, FIntPoint(5, 5), ECk_CardinalRotation::None);

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
            // Wait for the None footprint (5,5),(6,5) to fully stamp.
            if (IsOccupied(FIntPoint(5, 5)) && IsOccupied(FIntPoint(6, 5)))
            {
                // Re-place the SAME occupant rotated a Quarter turn -> (5,5),(5,6).
                // Task 7a auto-replaces the previous placement.
                _Placement2 = utils_2d_grid_placement::Request_Place(
                    _Grid, _Object, FIntPoint(5, 5), ECk_CardinalRotation::Quarter);
                _Step = 1;
            }
            return;
        }

        if (_Step == 1)
        {
            // Wait until the reconcile has freed the old cell and stamped the new one.
            if (!IsOccupied(FIntPoint(6, 5)) && IsOccupied(FIntPoint(5, 6)) && IsOccupied(FIntPoint(5, 5)))
            {
                Assert_True(!IsOccupied(FIntPoint(6, 5)),
                    "Old footprint cell (6,5) should be freed after the rotated re-place (auto-replace)");
                Assert_True(IsOccupied(FIntPoint(5, 6)),
                    "New footprint cell (5,6) should be occupied after the Quarter-rotation re-place");
                Assert_True(IsOccupied(FIntPoint(5, 5)),
                    "Shared anchor cell (5,5) should remain occupied across the re-place");

                auto OccupantAt5_6 = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(5, 6));
                Assert_True(OccupantAt5_6 == _Object,
                    "(5,6) should now be occupied by the same re-placed occupant");
                FinishSuccess();
            }
            return;
        }
    }
}
