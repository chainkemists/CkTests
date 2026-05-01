// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: STACKABLE TRAIT — SPLIT STACK
//============================================================================
//
// Verifies Request_SplitStack carves N items off an existing stack into a
// new stack:
//   1. Add Potion x3 (default policy → single stack of count 3 by virtue
//      of the Stackable trait).
//   2. Request_SplitStack(stack, 1) — split 1 off.
//   3. OnSplitResult fires with Result=Success.
//   4. Inventory now holds 2 items: original (count 2) and new (count 1).
//
// EXPECTED FAILURE — TWO DISTINCT ISSUES:
//
//   1. Framework bug: see CkAutoTest_Inventory_DataOnly_AddItem.as for the
//      canonical explanation. This test fails at the framework level
//      (Stackable trait warnings on item creation).
//
//   2. Amount-parameter semantic anomaly observed in test run:
//        Request_AddItemByDefinition(PotionDef, 3) with default policy
//        produces a single item with stack count 1 (not 3), even though
//        Stackable's _MaxStackSize is 10 (so 3 should fit in one stack).
//        Either:
//          a) The Amount parameter means something different than
//             "total units to add" — possibly "number of add requests".
//          b) Default add policy interacts with Stackable initial count
//             in an unexpected way.
//          c) Real framework bug: Amount > 1 is silently truncated.
//
//      Needs investigation once the framework warning fix lands and we
//      can iterate green-test-first to nail down the contract. The strict
//      assertion below stays so the question is preserved — if Amount IS
//      supposed to deposit 3 units, this test will catch the regression
//      once warnings clear.
//============================================================================

class UCk_AutoTest_Inventory_StackableTrait_SplitStack : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory _Inventory;
    private FCk_Handle_Item _OriginalStack;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory::Make_InventoryParams_DataOnly(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Split"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        // Default add policy (NOT ForceNewItem) so 3 Potions land as a
        // single stack of count 3.
        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 3);
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

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
            f"Initial Add(Potion x3) should succeed (got {InResult})");

        auto Items = utils_inventory::Get_Items(_Inventory);
        if (Items.Num() != 1)
        {
            FinishFailure(f"Expected 1 stack of count 3, got {Items.Num()} items");
            return;
        }
        _OriginalStack = Items[0];
        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_OriginalStack), 3,
            "Initial stack should hold count 3");

        utils_inventory::Request_SplitStack(
            _Inventory,
            FCk_Request_Inventory_SplitStack(_OriginalStack, 1),
            FCk_Delegate_Inventory_OnOperationResult_Split(this, n"OnSplitResult"));
    }

    UFUNCTION()
    private void OnSplitResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InSource,
        FCk_Handle_Item InNewItem,
        ECk_Inventory_OperationResult_Split InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Split::Success,
            f"Split result should be Success (got {InResult})");
        Assert_Equals_Int(utils_inventory::Get_NumItems(_Inventory), 2,
            "After split, inventory should hold 2 stacks (original + new)");
        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(InSource), 2,
            "Source stack should retain count 2 (3 - 1)");
        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(InNewItem), 1,
            "New stack should hold count 1");

        FinishSuccess();
    }
}
