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
//============================================================================

class UCk_AutoTest_Inventory_StackableTrait_SplitStack : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private FCk_Handle_Item _OriginalStack;
    private FCk_Handle_Item _SplitSource;
    private FCk_Handle_Item _SplitNewItem;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Split"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        // Default add policy (NOT ForceNewItem) so 3 Potions land as a
        // single stack of count 3.
        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 3);
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

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
            f"Initial Add(Potion x3) should succeed (got {InResult})");

        auto Items = _Inventory.Get_Items();
        if (Items.Num() != 1)
        {
            FinishFailure(f"Expected 1 stack, got {Items.Num()} items");
            return;
        }
        _OriginalStack = Items[0];

        // AddByDefinition has set the stack-count via a deferred IntegerAttribute
        // Override modifier; wait one tick so the compute processor applies it
        // before we read the count or issue the dependent SplitStack request.
        WaitOneFrame(n"OnPostAddSettled");
    }

    UFUNCTION()
    private void OnPostAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_OriginalStack), 3,
            "Initial stack should hold count 3 after deferred Override settles");

        _Inventory.Request_SplitStack(FCk_Request_Inventory_SplitStack(_OriginalStack, 1),
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
        Assert_Equals_Int(_Inventory.Get_NumItems(), 2,
            "After split, inventory should hold 2 stacks (original + new)");

        _SplitSource = InSource;
        _SplitNewItem = InNewItem;

        // SplitStack's count adjustments are also deferred — wait one tick.
        WaitOneFrame(n"OnPostSplitSettled");
    }

    UFUNCTION()
    private void OnPostSplitSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_SplitSource), 2,
            "Source stack should retain count 2 (3 - 1) after deferred adjust settles");
        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_SplitNewItem), 1,
            "New stack should hold count 1 after deferred adjust settles");

        FinishSuccess();
    }
}
