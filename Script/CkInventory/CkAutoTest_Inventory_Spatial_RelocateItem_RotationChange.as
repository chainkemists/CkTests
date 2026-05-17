// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: SPATIAL RELOCATE ITEM — ROTATION CHANGE
//============================================================================
//
// Pins that Request_RelocateItem updates an item's rotation when the new
// FCk_SpatialPlacement carries a different ECk_CardinalRotation, and that
// the item's active cells are recomputed under the new rotation.
//
// Setup on a 5x5 spatial inventory (large enough that a 3x1 Sword fits in
// either orientation):
//   1. Add Sword via Request_AddItemByDefinition (3x1, auto-placed at the
//      first available cell with the default rotation).
//   2. Capture its starting rotation.
//   3. Relocate to (0,0) with ECk_CardinalRotation::Quarter (90°). A 3x1
//      sword rotated 90° occupies 3 vertical cells at (0,0)-(0,2); fits
//      in a 5x5 grid.
//   4. Assert Result::Success and that Get_ItemPlacementRotation == Quarter.
//
// Uses Sword (Dimensions=3x1, Tags-only) — non-Stackable, sidesteps the
// Stackable framework warning.
//============================================================================

class UCk_AutoTest_Inventory_Spatial_RelocateItem_RotationChange : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_Spatial _Inventory;
    private FCk_Handle_Item _Sword;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_RelocateRotate"),
            FIntPoint(5, 5),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_spatial::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(Request,
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
            FinishFailure("Setup: failed to add Sword to 5x5 spatial inventory");
            return;
        }

        _Sword = InItemsCreated[0];

        auto NewPlacement = FCk_SpatialPlacement();
        NewPlacement.Set_Coordinate(FIntPoint(0, 0));
        NewPlacement.Set_Rotation(ECk_CardinalRotation::Quarter);
        auto RelocateRequest = FCk_Request_Inventory_Spatial_RelocateItem(_Sword, NewPlacement);
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

        Assert_True(InResult == ECk_Inventory_OperationResult_Relocate::Success,
            f"Relocate with rotation change should succeed in a 5x5 grid (got {InResult})");

        // Get_ItemPlacementRotation reads from the item's Transform yaw. The
        // PlaceItemOnGrid call inside Relocate updates the Transform via a
        // deferred Request, so the new yaw isn't visible until a frame later.
        WaitOneFrame(n"OnSettled_AfterRelocate");
    }

    UFUNCTION()
    private void OnSettled_AfterRelocate(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto NowRotation = utils_inventory_spatial::Get_ItemPlacementRotation(_Sword);
        Assert_True(NowRotation == ECk_CardinalRotation::Quarter,
            f"Get_ItemPlacementRotation should reflect the new rotation Quarter (got {NowRotation})");

        FinishSuccess();
    }
}
