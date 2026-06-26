// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: CUSTOM CAN-ACCEPT-ITEM REJECTS
//============================================================================
//
// Verifies that the FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic
// delegate provided at inventory construction is invoked during
// Request_AddItemByDefinition AND that returning false rejects the add
// with Failed_RejectedByCustomAcceptanceLogic.
//
// Procedure:
//   1. Create a bounded data-only inventory whose CustomCanAcceptItem
//      delegate returns false.
//   2. Issue Request_AddItemByDefinition for a Sword (Tags+Dimensions
//      only — no Stackable, to avoid any lingering Stackable-trait
//      framework issues).
//   3. Assert: result enum is Failed_RejectedByCustomAcceptanceLogic,
//      AmountAdded == 0, ItemsCreated empty, Get_NumItems == 0.
//   4. Assert: the predicate WAS invoked (proving the rejection went
//      through the user delegate, not a short-circuit elsewhere).
//

class UCk_AutoTest_Inventory_CustomCanAcceptItem : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private bool _PredicateInvoked = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto AcceptDelegate = FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(this, n"OnCanAcceptItem");
        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_CustomReject"),
            5,
            AcceptDelegate,
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto SwordDef = inv_gym_items::Sword();
        auto Request = FCk_Request_Inventory_AddItemByDefinition(SwordDef, 1);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
    }

    UFUNCTION()
    private void OnCanAcceptItem(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        bool& OutCanAccept)
    {
        _PredicateInvoked = true;
        OutCanAccept = false;
    }

    UFUNCTION()
    private void OnAddResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        Assert_True(_PredicateInvoked,
            "CustomCanAcceptItem predicate must be invoked during Request_AddItemByDefinition");
        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Failed_RejectedByCustomAcceptanceLogic,
            f"When predicate returns false, result must be Failed_RejectedByCustomAcceptanceLogic (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 0, "AmountAdded must be 0 when rejected by custom predicate");
        Assert_Equals_Int(InItemsCreated.Num(), 0, "ItemsCreated must be empty when rejected by custom predicate");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 0,
            "Inventory must remain empty after a custom-rejected add");

        FinishSuccess();
    }
}
