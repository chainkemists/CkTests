// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: DATA-ONLY UNBOUNDED
//============================================================================
//
// Verifies that an unbounded data-only inventory accepts adds without ever
// reporting Failed_NoSpaceAvailable. Adds three items in sequence and
// confirms each one returns Success_AllAdded.
//
// Mirrors the unbounded variant of the bounded gym, exercising the
// Make_InventoryParams_DataOnly factory (no max-size argument).
//
// EXPECTED FAILURE — FRAMEWORK BUG: see CkAutoTest_Inventory_DataOnly_AddItem.as
// for the canonical explanation. This test fails at the framework level
// (warnings on item creation) until the trait-application regression is fixed.
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_Unbounded : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory _Inventory;
    private int32 _AddsObserved = 0;
    private const int32 _ExpectedAdds = 3;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory::Make_InventoryParams_DataOnly(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Unbounded"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        QueueAdd();
    }

    private void QueueAdd()
    {
        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        utils_inventory::Request_AddItemByDefinition(
            _Inventory,
            Request,
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

        Assert_Equals_Int(utils_inventory::Get_NumItems(_Inventory), _ExpectedAdds,
            "Unbounded inventory should hold all 3 items");
        FinishSuccess();
    }
}
