// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: GRID DESTRUCTION WITH ACTIVE PLACEMENTS
//============================================================================
//
// Lifecycle/ordering hardening: destroying the grid (its owner entity) while it
// still has active placements must not crash, and the occupancy query utils must
// fail safe (return invalid/false) once the grid handle goes invalid.
//
//   1. Place object A (1x1) at (5,5); tick until (5,5) is Occupied.
//   2. Request_DestroyEntity(grid owner entity). Placement entities are owned by
//      the grid (die with it) and the grid's cells are children too.
//   3. Tick a few times. Once the grid is torn down, assert:
//        - no crash
//        - Get_IsOccupied(grid,(5,5)) == false   (guarded by ck::Is_NOT_Valid grid)
//        - Get_OccupantAt(grid,(5,5)) is an invalid handle
//      FinishSuccess.
//============================================================================

class UCk_AutoTest_Grid_GridDestructionWithActivePlacements : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _GridOwner;
    private FCk_Handle _ObjectA;
    private FCk_Handle_2dGridPlacement _PlacementA;
    private int32 _Step = 0;
    private int32 _TicksAfterDestroy = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // Keep the base owner handle so we can destroy the grid entity itself.
        _GridOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            _GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        _Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        _ObjectA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_ObjectA, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

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
            if (utils_2d_grid_occupancy::Get_IsOccupied(_Grid, FIntPoint(5, 5)))
            {
                // Destroy the grid (its owner entity). This must take the cells +
                // grid-owned placement entities with it without crashing.
                utils_entity_lifetime::Request_DestroyEntity(_GridOwner);
                _Step = 1;
            }
            return;
        }

        if (_Step == 1)
        {
            _TicksAfterDestroy += 1;

            // These queries must be safe to call on a now-invalid grid (the utils guard
            // ck::Is_NOT_Valid(InGrid)). They must never crash.
            auto IsOccupied = utils_2d_grid_occupancy::Get_IsOccupied(_Grid, FIntPoint(5, 5));
            auto OccupantAt = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(5, 5));

            // Once the grid has fully torn down, occupancy reads false and the occupant
            // query returns an invalid handle. Give it a few ticks for destruction to
            // advance past Initiate -> Teardown.
            if (!IsOccupied && ck::Is_NOT_Valid(OccupantAt))
            {
                Assert_True(!IsOccupied,
                    "Get_IsOccupied on a destroyed grid must return false (guarded)");
                Assert_True(ck::Is_NOT_Valid(OccupantAt),
                    "Get_OccupantAt on a destroyed grid must return an invalid handle (guarded)");
                FinishSuccess();
                return;
            }

            // Safety net: if it somehow never resolves, fail loudly rather than time out
            // silently after a long wait.
            if (_TicksAfterDestroy > 600)
            {
                FinishFailure("Grid destruction did not settle to a safe (free, invalid-occupant) state");
            }
            return;
        }
    }
}
