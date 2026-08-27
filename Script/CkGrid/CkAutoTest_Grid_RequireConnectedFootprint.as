// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: REQUIRE-CONNECTED FOOTPRINT VALIDATION
//============================================================================
//
// Pins the ECk_GridConnectivity::RequireConnected branch of Get_CanPlace.
//
// A 3x1 GridObject anchored at (5,5) resolves to cells (5,5),(6,5),(7,5). A
// blocker disables the MIDDLE cell (6,5), splitting the footprint into two
// pieces: {(5,5)} (the anchor / BFS start) and {(7,5)} (cut off behind the
// wall). The disabled cell is a wall - impassable - so the 4-neighbour BFS
// from the anchor can never reach (7,5).
//
// Expected: Get_CanPlace(... RequireConnected) returns CanPlace==false with
// (7,5) reported in FailedCells (the disconnected far cell).
//
// The blocker stamp is processor-driven, so we poll a recurring tick until
// (6,5) is observed disabled before issuing the placement query.
//============================================================================

class UCk_AutoTest_Grid_RequireConnectedFootprint : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle             _Object;
    private FCk_Handle             _BlockerEntity;

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

        // 3x1 object: anchored at (5,5) -> cells (5,5),(6,5),(7,5).
        _Object = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_Object, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(3, 1)));

        // Blocker disables ONLY the middle cell (6,5) of the footprint.
        _BlockerEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto BP = FCk_Fragment_2dGridBlocker_ParamsData(_Grid, FIntPoint(6, 5), FIntPoint(6, 5));
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

        // Wait for the blocker to stamp (6,5) disabled before querying placement.
        if (!IsCellDisabled(FIntPoint(6, 5))) { return; }

        auto R = utils_2d_grid_placement::Get_CanPlace(
            _Grid, _Object.As_2dGridObject(), FIntPoint(5, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::RequireConnected);

        Assert_True(R.Get_CanPlace() == false,
            "RequireConnected: a footprint split by a disabled wall cell must fail placement");

        Assert_True(R.Get_FailedCells().Contains(FIntPoint(7, 5)),
            "RequireConnected: the far cell (7,5) cut off behind the wall must be reported as failed");

        FinishSuccess();
    }
}
