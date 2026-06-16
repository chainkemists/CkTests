// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: QUEUED REQUEST CANCELLED ON DESTROY
//============================================================================
//
// A request enqueued on an inventory that is then destroyed before it can be
// processed must complete with Failed_OperationCancelled (the EndPlay teardown
// drain), so a caller awaiting completion terminates instead of hanging.
// HandleRequests skips the pending-kill inventory, so the request survives to
// EndPlay where it is cancelled.
//============================================================================

class UCk_AutoTest_Inventory_RequestCancelledOnDestroy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_CancelOnDestroy"), 5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        auto Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        Inventory.Request_AddItemByDefinition(AddRequest,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnResult"));

        FCk_Handle InventoryEntity = Inventory;
        utils_entity_lifetime::Request_DestroyEntity(InventoryEntity);
    }

    UFUNCTION()
    private void OnResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Failed_OperationCancelled,
            f"A request whose inventory is destroyed before draining must complete with Failed_OperationCancelled (got {InResult})");

        FinishSuccess();
    }
}
