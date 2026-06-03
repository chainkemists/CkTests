// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: RE-ENTRANT PLACE DURING OnObjectPlaced BROADCAST
//============================================================================
//
// Lifecycle/ordering hardening: calling Request_Place re-entrantly from inside
// the OnObjectPlaced handler must be safe, and occupancy must stay deferred
// (the re-entrant placement's cell is NOT stamped synchronously).
//
//   1. Bind OnObjectPlaced. Request_Place object A (1x1) at (5,5).
//   2. The handler fires synchronously for A. The FIRST time it fires, it
//      re-entrantly Request_Place object B (1x1) at (6,5), and asserts that
//      INSIDE the handler Get_OccupantAt(grid,(6,5)) is NOT yet B (occupancy is
//      deferred — the re-entrant placement's cell isn't stamped synchronously).
//   3. On a later tick, assert BOTH A@(5,5) and B@(6,5) are occupied.
//      FinishSuccess.
//============================================================================

class UCk_AutoTest_Grid_ReentrancyDuringBroadcast : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle _ObjectA;
    private FCk_Handle _ObjectB;
    private FCk_Handle_2dGridPlacement _PlacementA;
    private FCk_Handle_2dGridPlacement _PlacementB;

    private int32 _PlacedFireCount = 0;
    private bool _ReentrantPlaced = false;
    private bool _DeferredAssertPassed = false;

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

        _Grid.BindTo_OnObjectPlaced(
            FCk_Delegate_2dGridPlacement_ObjectPlaced(this, n"OnObjectPlaced"));

        _ObjectA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_ObjectA, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        _ObjectB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_2d_grid_object::Add(_ObjectB, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        _PlacementA = utils_2d_grid_placement::Request_Place(
            _Grid, _ObjectA, FIntPoint(5, 5), ECk_CardinalRotation::None);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnObjectPlaced(FCk_Handle_2dGridSystem InGrid, FCk_Handle InOccupant, const TArray<FIntPoint>&in InCells)
    {
        _PlacedFireCount += 1;

        // Only re-enter once, for A's placement broadcast.
        if (_ReentrantPlaced) { return; }
        if (InOccupant != _ObjectA) { return; }

        _ReentrantPlaced = true;

        _PlacementB = utils_2d_grid_placement::Request_Place(
            _Grid, _ObjectB, FIntPoint(6, 5), ECk_CardinalRotation::None);

        // Occupancy is deferred: even though B's placement was just added (and B's
        // broadcast nested under A's), the (6,5) cell is NOT stamped synchronously.
        auto OccupantAt6_5 = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(6, 5));
        Assert_True(OccupantAt6_5 != _ObjectB,
            "Inside the OnObjectPlaced handler, Get_OccupantAt((6,5)) must NOT yet be B (occupancy is deferred to the reconcile tick)");
        _DeferredAssertPassed = true;
    }

    private bool IsOccupied(FIntPoint InCoord)
    {
        return utils_2d_grid_occupancy::Get_IsOccupied(_Grid, InCoord);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (IsOccupied(FIntPoint(5, 5)) && IsOccupied(FIntPoint(6, 5)))
        {
            Assert_True(_DeferredAssertPassed,
                "The re-entrant deferred-occupancy assertion should have run inside the broadcast");

            auto OccupantA = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(5, 5));
            auto OccupantB = utils_2d_grid_occupancy::Get_OccupantAt(_Grid, FIntPoint(6, 5));
            Assert_True(OccupantA == _ObjectA,
                "After reconcile, (5,5) should be occupied by A");
            Assert_True(OccupantB == _ObjectB,
                "After reconcile, (6,5) should be occupied by the re-entrantly-placed B");
            FinishSuccess();
        }
    }
}
