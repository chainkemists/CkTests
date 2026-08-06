// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: STACKABLE TRAIT — CONSUME FROM STACK
//============================================================================
//
// Request_ConsumeFromStack is the destroy-style counterpart to
// Request_SplitStack (sell, eat, craft input). It exists because a split CANNOT
// serve that purpose: a split mints a NEW entry, so it fails at an entry bound —
// see CkAutoTest_Inventory_DataOnly_SplitRespectsBound, which pins exactly that.
//
// This test therefore uses that test's setup DELIBERATELY: an inventory sitting
// AT its entry bound, where a split is proven to fail with
// Failed_NoSpaceForNewItem. Consuming in place must still succeed there. Keeping
// the two setups identical is the point — if the bound is ever relaxed here the
// test stops covering the case the API was added for.
//
//   1. BoundedByUniqueEntries(2) inventory.
//   2. Add Potion x5 (PreferStacking → 1 entry, stack 5).
//   3. Add Potion x1 (ForceNewItem → entry 2; now AT the entry bound).
//   4. Request_ConsumeFromStack(stack5, 2) → true, stack reads 3, still 2 entries.
//   5. Request_ConsumeFromStack(stack3, 1) → true, stack reads 2 — deltas compose
//      across calls (Add/Subtract modifiers), unlike an Override which would
//      last-writer-win.
//
// The refusal paths (invalid item, non-stackable, consuming the WHOLE stack) are
// caller contract violations and ENSURE rather than returning quietly, so they
// cannot be asserted here — an ensure fails the test outright, and the autotest
// base has no expected-ensure facility. They are documented on the function.
//
//============================================================================

class UCk_AutoTest_Inventory_StackableTrait_ConsumeFromStack : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private FCk_Handle_Item _StackedItem;

    UFUNCTION()
    private void Check_StackIsFive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_item_trait_stackable::Get_StackCount(_StackedItem) == 5);
    }

    UFUNCTION()
    private void Check_StackIsThree(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_item_trait_stackable::Get_StackCount(_StackedItem) == 3);
    }

    UFUNCTION()
    private void Check_StackIsTwo(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_item_trait_stackable::Get_StackCount(_StackedItem) == 2);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_ConsumeFromStack"),
            2,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 5);
        _Inventory.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnFirstAdd"));
    }

    UFUNCTION()
    private void OnFirstAdd(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
            f"Add(Potion x5) should succeed (got {InResult})");

        if (InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Expected 1 created item, got {InItemsCreated.Num()}");
            return;
        }
        _StackedItem = InItemsCreated[0];

        // Fill the second (last) entry so the inventory sits AT its bound — the
        // state in which a split provably cannot mint its new entry.
        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSecondAdd"));
    }

    UFUNCTION()
    private void OnSecondAdd(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
            f"ForceNewItem add should fill the second entry (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 2, "Inventory should be at its 2-entry bound");

        // The stack count is a deferred attribute write — poll for it rather than
        // assuming a fixed frame count (see SplitRespectsBound's note).
        WaitUntil(n"Check_StackIsFive", n"OnSettledBeforeConsume");
    }

    UFUNCTION()
    private void OnSettledBeforeConsume(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_StackedItem), 5,
            "Stacked item should read count 5 once the deferred write settles");

        const auto Consumed = utils_item_trait_stackable::Request_ConsumeFromStack(_StackedItem, 2);
        Assert_True(Consumed,
            "ConsumeFromStack(2) must succeed at the entry bound — the case Request_SplitStack cannot serve");

        if (Consumed == false)
        { FinishFailure("ConsumeFromStack refused a valid partial consume"); return; }

        WaitUntil(n"Check_StackIsThree", n"OnFirstConsumeSettled");
    }

    UFUNCTION()
    private void OnFirstConsumeSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_StackedItem), 3,
            "Consuming 2 of 5 should leave 3");

        // The structural property that separates this from a split: no new entry.
        Assert_Equals_Int(_Inventory.Get_NumItems(), 2,
            "Consuming in place must not mint an entry — the inventory stays at its bound");

        // Deltas compose across calls (Add/Subtract modifiers), unlike Override.
        const auto Consumed = utils_item_trait_stackable::Request_ConsumeFromStack(_StackedItem, 1);
        Assert_True(Consumed, "A second ConsumeFromStack should also succeed");

        if (Consumed == false)
        { FinishFailure("Second ConsumeFromStack refused"); return; }

        WaitUntil(n"Check_StackIsTwo", n"OnSecondConsumeSettled");
    }

    UFUNCTION()
    private void OnSecondConsumeSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_StackedItem), 2,
            "Consecutive consumes must compose (5 - 2 - 1 = 2), not last-writer-win");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 2,
            "Entry count still unchanged after the second consume");

        FinishSuccess();
    }
}
