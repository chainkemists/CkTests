// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: DATA-ONLY UNBOUNDED
//============================================================================
//
// Verifies that an unbounded data-only inventory accepts adds without ever
// reporting Failed_NoSpaceAvailable. Adds three items in sequence and
// confirms each one returns Success_AllAdded.
//
// Mirrors the unbounded variant of the bounded gym, exercising the
// utils_inventory_dataonly::Make_Params factory (no max-size argument).
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_Unbounded : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private int32 _AddsObserved = 0;
    private const int32 _ExpectedAdds = 3;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Unbounded"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        QueueAdd();
    }

    private void QueueAdd()
    {
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
        _AddsObserved++;

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
            f"Add #{_AddsObserved} on unbounded inventory should succeed (got {InResult})");

        if (_AddsObserved < _ExpectedAdds)
        {
            QueueAdd();
            return;
        }

        Assert_Equals_Int(_Inventory.Get_NumItems(), _ExpectedAdds,
            "Unbounded inventory should hold all 3 items");
        FinishSuccess();
    }
}
