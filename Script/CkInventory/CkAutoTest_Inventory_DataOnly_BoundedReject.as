// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: BOUNDED REJECTION
//============================================================================
//
// Verifies that a bounded data-only inventory rejects adds that would
// exceed its capacity:
//   1. Create a bounded(2) inventory.
//   2. Add Potion → Success (count=1).
//   3. Add Potion → Success (count=2, at capacity).
//   4. Add Potion → result is NOT Succeeded; Get_NumItems remains 2.
//
// Step-machine pattern: each add is queued only after the previous result
// is observed (request coalescing would silently drop intermediate adds
// otherwise).
//
// NOTE — GAP IN GYM COVERAGE (potential gym addition):
//   The bounded gym (CkInventoryGym_DataOnly_Bounded) auto-step description
//   says "Overfill (expect reject)" but never asserts the rejection — the
//   gym only displays Last result text visually. A regression where over-
//   capacity adds silently succeed (or where the result enum gets renamed
//   without the gym noticing) would not be caught visually. This test
//   pins down the actual rejection contract.
//
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_BoundedReject : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private int32 _AddsObserved = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Bounded"),
            2,
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

        if (_AddsObserved == 1 || _AddsObserved == 2)
        {
            Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
                f"Add #{_AddsObserved} below capacity should succeed (got {InResult})");
            QueueAdd();
            return;
        }

        // Third add — should be rejected with NoSpaceAvailable.
        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Failed_NoSpaceAvailable,
            f"Add #3 over bounded(2) capacity should fail with Failed_NoSpaceAvailable (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 2,
            "Inventory should remain at 2 items after a rejected add");

        FinishSuccess();
    }
}
