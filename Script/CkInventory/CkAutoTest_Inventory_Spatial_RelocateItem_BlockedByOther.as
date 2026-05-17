// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: SPATIAL RELOCATE ITEM — BLOCKED BY OTHER
//============================================================================
//
// Pins the rejection contract for Request_RelocateItem when the destination
// coordinate is already occupied by a different item:
//   1. Build a 4x4 spatial inventory.
//   2. Add Shield A and Shield B (both 1x1) — auto-placed into two distinct
//      cells (CoordA and CoordB).
//   3. Attempt to relocate Shield A to CoordB.
//   4. Assert: ECk_Inventory_OperationResult_Relocate is NOT Success, and
//      Shield A's coordinate is unchanged (still CoordA).
//
// Uses Shields (Dimensions=1x1, Tags-only) to keep occupancy deterministic
// without involving the Stackable warning path.
//============================================================================

class UCk_AutoTest_Inventory_Spatial_RelocateItem_BlockedByOther : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_Spatial _Inventory;
    private FCk_Handle_Item _ShieldA;
    private FCk_Handle_Item _ShieldB;
    private FIntPoint _CoordA;
    private FIntPoint _CoordB;
    private int32 _AddsObserved = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_RelocateBlocked"),
            FIntPoint(4, 4),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_spatial::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request1 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Shield(), 1);
        Request1.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(Request1,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));

        auto Request2 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Shield(), 1);
        Request2.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(Request2,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
    }

    UFUNCTION()
    private void OnAddResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        if (InItemsCreated.Num() == 0)
        {
            FinishFailure("Setup: failed to add Shield to spatial inventory");
            return;
        }

        _AddsObserved += 1;
        if (_AddsObserved == 1)
        {
            _ShieldA = InItemsCreated[0];
            _CoordA = utils_inventory_spatial::Get_ItemPlacementCoordinate(_Inventory, _ShieldA);
            return;
        }

        _ShieldB = InItemsCreated[0];
        _CoordB = utils_inventory_spatial::Get_ItemPlacementCoordinate(_Inventory, _ShieldB);

        if (_CoordA == _CoordB)
        {
            FinishFailure("Setup: both shields landed in the same cell — auto-place expected to choose distinct cells");
            return;
        }

        // Attempt to relocate Shield A onto Shield B's coordinate.
        auto NewPlacement = FCk_SpatialPlacement();
        NewPlacement.Set_Coordinate(_CoordB);
        NewPlacement.Set_Rotation(ECk_CardinalRotation::None);
        auto RelocateRequest = FCk_Request_Inventory_Spatial_RelocateItem(_ShieldA, NewPlacement);
        _Inventory.Request_RelocateItem(RelocateRequest,
            FCk_Delegate_Inventory_OnOperationResult_Relocate(this, n"OnRelocateResult"));
    }

    UFUNCTION()
    private void OnRelocateResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        FIntPoint InNewCoord,
        ECk_Inventory_OperationResult_Relocate InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult != ECk_Inventory_OperationResult_Relocate::Success,
            f"Relocate onto an occupied cell must NOT succeed (got {InResult})");

        auto NowCoordA = utils_inventory_spatial::Get_ItemPlacementCoordinate(_Inventory, _ShieldA);
        Assert_True(NowCoordA == _CoordA,
            f"Shield A's coordinate should remain at the original {_CoordA} after a rejected relocate (got {NowCoordA})");

        auto NowCoordB = utils_inventory_spatial::Get_ItemPlacementCoordinate(_Inventory, _ShieldB);
        Assert_True(NowCoordB == _CoordB,
            f"Shield B's coordinate should remain at the original {_CoordB} (untouched by the rejected relocate)");

        FinishSuccess();
    }
}
