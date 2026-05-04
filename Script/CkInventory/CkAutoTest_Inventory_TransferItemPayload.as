// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: TRANSFER-ITEM RESULT PAYLOAD
//============================================================================
//
// Pins the result payload of Request_TransferItem between two data-only
// inventories. Existing inventory tests cover Add/Remove on a single
// inventory; transfer is a distinct operation with a 6-arg result delegate
// (source inventory, source item, target inventory, amount, target item,
// result enum) that nothing else asserts.
//
// Procedure:
//   1. Create two bounded(5) data-only inventories on the test entity.
//   2. Add a Sword to the source inventory (Tags+Dimensions item, no
//      Stackable trait — keeps the test robust against any lingering
//      Stackable-construction issues).
//   3. Request_TransferItem(source item, target inventory).
//   4. Assert in the result delegate: result == Success_FullyTransferred
//      (or another Success_* enum), the source inventory now reports 0
//      items, the target inventory reports 1 item.
//============================================================================

class UCk_AutoTest_Inventory_TransferItemPayload : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Inventory _Source;
    private FCk_Handle_Inventory _Target;
    private bool _SourceItemSeen = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory::Make_InventoryParams_DataOnly_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_TransferSource"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto TargetParams = utils_inventory::Make_InventoryParams_DataOnly_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_TransferTarget"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto SwordDef = inv_gym_items::Sword();
        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(SwordDef, 1);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        utils_inventory::Request_AddItemByDefinition(
            _Source,
            AddRequest,
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
            FinishFailure(f"Pre-transfer setup: failed to seed source inventory (result={InResult}, items={InItemsCreated.Num()})");
            return;
        }
        _SourceItemSeen = true;

        auto SourceItem = InItemsCreated[0];
        auto Request = FCk_Request_Inventory_TransferItem(SourceItem, _Target);
        // _Count default is -1 ("all"); for a single non-stackable item, that's fine.
        utils_inventory::Request_TransferItem(
            _Source,
            Request,
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

        // Result must indicate success (Success or Success_Partial).
        auto IsSuccess =
            InResult == ECk_Inventory_OperationResult_Transfer::Success ||
            InResult == ECk_Inventory_OperationResult_Transfer::Success_Partial;
        Assert_True(IsSuccess,
            f"Transfer of a single Sword between two empty bounded inventories should succeed (got {InResult})");
        Assert_True(InAmountTransferred >= 1,
            f"AmountTransferred should be >= 1 for a successful single-item transfer (got {InAmountTransferred})");

        Assert_Equals_Int(utils_inventory::Get_NumItems(_Source), 0,
            "Source inventory should hold 0 items after a successful full transfer");
        Assert_Equals_Int(utils_inventory::Get_NumItems(_Target), 1,
            "Target inventory should hold 1 item after a successful transfer");

        FinishSuccess();
    }
}
