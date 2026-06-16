// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: TRANSFER-ALL REPORTS SUCCESS (NOT PARTIAL)
//============================================================================
//
// A transfer-all (Count == -1) that moves every requested unit must report
// Success, never Success_Partial. Regression guard for the result-count math
// in DoTransfer: deriving the requested total from the post-move source count
// + moved count double-counted and misreported a full transfer as Partial.
//============================================================================

class UCk_AutoTest_Inventory_Transfer_FullMoveReportsSuccess : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _Target;
    private bool _SourceItemSeen = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_FullMove_Source"), 5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto TargetParams = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_FullMove_Target"), 5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_data_only::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Source.Request_AddItemByDefinition(AddRequest,
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
        if (_SourceItemSeen) { return; }

        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded ||
            InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Setup: failed to seed source inventory (result={InResult})");
            return;
        }
        _SourceItemSeen = true;

        // Default Count (-1) = transfer the whole source stack.
        auto Request = FCk_Request_Inventory_TransferItem_ToDataOnly(InItemsCreated[0], _Target);
        _Source.Request_TransferItem_ToDataOnly(Request,
            FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransferResult"));
    }

    UFUNCTION()
    private void OnTransferResult(
        FCk_Handle_Inventory InSource,
        FCk_Handle_Item InSourceItem,
        FCk_Handle_Inventory InTarget,
        int InAmountTransferred,
        FCk_Handle_Item InTargetItem,
        ECk_Inventory_OperationResult_Transfer InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Transfer::Success,
            f"A fully-moved transfer-all must report Success, not Success_Partial (got {InResult})");
        Assert_Equals_Int(InAmountTransferred, 1, "Exactly 1 unit should transfer");
        Assert_Equals_Int(_Source.Get_NumItems(), 0, "Source should be empty");
        Assert_Equals_Int(_Target.Get_NumItems(), 1, "Target should hold the moved item");

        FinishSuccess();
    }
}
