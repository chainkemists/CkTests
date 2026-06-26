// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: DATA-ONLY REMOVE ITEM
//============================================================================
//
// Verifies the remove-item flow:
//   1. Add a Potion to a bounded(5) inventory.
//   2. Once the add completes, take the created item handle and Request_RemoveItem.
//   3. Remove delegate fires with Result=Success.
//   4. Get_NumItems(Inventory) == 0.
//
// Step-machine pattern: removal is queued only after the add result has
// been observed, so the request handlers don't race or coalesce.
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_RemoveItem : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Bounded"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
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
            FinishFailure("Add did not produce any item to remove");
            return;
        }

        auto Item = InItemsCreated[0];
        _Inventory.Request_RemoveItem(FCk_Request_Inventory_RemoveItem(Item),
            FCk_Delegate_Inventory_OnOperationResult_Remove(this, n"OnRemoveResult"));
    }

    UFUNCTION()
    private void OnRemoveResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        ECk_Inventory_OperationResult_Remove InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Remove::Success,
            f"Remove result should be Success (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 0,
            "Inventory should report 0 items after a successful remove");

        FinishSuccess();
    }
}
