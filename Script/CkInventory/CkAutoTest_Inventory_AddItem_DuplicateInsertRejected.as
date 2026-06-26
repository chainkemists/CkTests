// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: ADD ITEM — DUPLICATE INSERT REJECTED
//============================================================================
//
// Pins the documented hard-failure contract: an item that already belongs to
// an inventory cannot be re-added to the same inventory via Request_AddItem.
// The expected result enum is ECk_Inventory_OperationResult_Add::
// Failed_ItemAlreadyInInventory.
//
// Procedure:
//   1. Create a 3x3 Spatial inventory.
//   2. Add a Sword (3x1, bare-trait) via Request_AddItemByDefinition. Capture
//      the resulting item handle and the inventory's item count (= 1).
//   3. Call utils_inventory::Request_AddItem with that same item handle.
//   4. On result: Failed_ItemAlreadyInInventory.
//   5. Item count is still 1 (no duplication, no removal).
//
// Sword sidesteps the Stackable framework warning bug.
//============================================================================

class UCk_AutoTest_Inventory_AddItem_DuplicateInsertRejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Inventory_Spatial _Inventory;
    private FCk_Handle_Item _Sword;
    private bool _SeedComplete = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_DupInsert"),
            FIntPoint(3, 3),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Inventory = utils_inventory_spatial::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(AddRequest,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnInitialAddResult"));
    }

    UFUNCTION()
    private void OnInitialAddResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        if (_SeedComplete) { return; }

        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded ||
            InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Setup: failed to seed Sword into source inventory (result={InResult})");
            return;
        }
        _SeedComplete = true;
        _Sword = InItemsCreated[0];

        // Now try to add the already-contained item to the SAME inventory.
        auto DupRequest = FCk_Request_Inventory_AddItem(_Sword);
        FCk_Handle_Inventory InvAsBase = _Inventory;
        utils_inventory::Request_AddItem(InvAsBase, DupRequest,
            FCk_Delegate_Inventory_OnOperationResult_Add(this, n"OnDuplicateAddResult"));
    }

    UFUNCTION()
    private void OnDuplicateAddResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        ECk_Inventory_OperationResult_Add InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Add::Failed_ItemAlreadyInInventory,
            f"Re-adding an already-contained item must report Failed_ItemAlreadyInInventory (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 1,
            "Inventory should still hold exactly 1 item after a rejected duplicate add");

        FinishSuccess();
    }
}
