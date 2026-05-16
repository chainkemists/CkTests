// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: STACKABLE TRAIT — STACK ITEMS
//============================================================================
//
// Verifies Request_StackItems merges two existing stacks of the same
// stackable definition:
//   1. Add Potion x1 with ForceNewItem → stack #1, count=1.
//   2. Add Potion x1 with ForceNewItem → stack #2, count=1.
//   3. Request_StackItems(stack#1, stack#2).
//   4. OnStackResult fires with Result=Success.
//   5. The surviving target stack reports stack count = 2.
//   6. Total Get_NumItems is now 1 (source stack consumed by merge).
//
// EXPECTED FAILURE — TWO DISTINCT ISSUES:
//
//   1. Framework bug: see CkAutoTest_Inventory_DataOnly_AddItem.as for the
//      canonical explanation. This test fails at the framework level
//      (Stackable trait warnings on item creation).
//
//   2. Count-semantic anomaly observed in test run:
//        After Request_StackItems on two stacks of count 1+1, the
//        surviving stack reports count 1 (not 2). The Stack result
//        enum DID return Success, and Get_NumItems went from 2 to 1
//        (source destroyed) — but the source's count was not added
//        to the target. Either:
//          a) Real framework bug: stack-merge loses count.
//          b) My misreading of the API contract (e.g. count maybe
//             means "number of separate stacks merged into target",
//             not "sum of counts").
//
//      Needs investigation once the framework warning fix lands and we
//      can iterate green-test-first against the real semantics. The
//      assertion below stays strict to preserve the question — relaxing
//      it now would let a real bug slip past once the warnings clear.
//============================================================================

class UCk_AutoTest_Inventory_StackableTrait_StackItems : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private int32 _AddsObserved = 0;
    private FCk_Handle_Item _Source;
    private FCk_Handle_Item _Target;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Stackable"),
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

        if (_AddsObserved == 1)
        {
            QueueAdd();
            return;
        }

        // After the second add, both items exist as separate stacks.
        auto Items = _Inventory.Get_Items();
        if (Items.Num() < 2)
        {
            FinishFailure(f"Expected 2 separate stacks after ForceNewItem adds (got {Items.Num()})");
            return;
        }
        _Source = Items[0];
        _Target = Items[1];

        _Inventory.Request_StackItems(FCk_Request_Inventory_StackItems(_Source, _Target),
            FCk_Delegate_Inventory_OnOperationResult_Stack(this, n"OnStackResult"));
    }

    UFUNCTION()
    private void OnStackResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InSource,
        FCk_Handle_Item InTarget,
        ECk_Inventory_OperationResult_Stack InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Stack::Success,
            f"Stack result should be Success (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 1,
            "After merge, inventory should hold a single stack");

        // StackItems applies its count delta to the target via a deferred
        // IntegerAttribute Adjust modifier; wait one tick before reading.
        WaitOneFrame(n"OnPostStackSettled");
    }

    UFUNCTION()
    private void OnPostStackSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Items = _Inventory.Get_Items();
        if (Items.Num() != 1)
        {
            FinishFailure(f"Expected 1 surviving stack after merge, got {Items.Num()}");
            return;
        }

        auto Survivor = Items[0];
        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(Survivor), 2,
            "Surviving stack should hold count 2 (1 + 1) after deferred Adjust settles");

        FinishSuccess();
    }
}
