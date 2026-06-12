// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: STACKING POLICY — NO STACKING
//============================================================================
//
// Verifies ECk_Inventory_StackingPolicy::NoStacking caps every stack in the
// inventory at 1 unit, regardless of the item definition's max stack (Potion
// defines max 10):
//   1. Create an unbounded inventory with NoStacking.
//   2. Add Potion x3 (PreferStacking) → 3 separate entries, 1 unit each.
//   3. Request_StackItems(entry0 → entry1) → Failed_TargetStackFull.
//
// Combined with Make_Params_Bounded this is the "N unique items, no stacks"
// container ("6 unique items, stack <= 1 each").
//
//============================================================================

class UCk_AutoTest_Inventory_StackingPolicy_NoStacking : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_NoStacking"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        Params._StackingPolicy = ECk_Inventory_StackingPolicy::NoStacking;

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        // PreferStacking on purpose — the policy must defeat it.
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
            f"Add(Potion x3) should succeed as separate entries (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 3, "All 3 units should be added");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 3,
            "NoStacking must spread 3 units across 3 entries despite PreferStacking");

        WaitOneFrame(n"OnAddSettled");
    }

    UFUNCTION()
    private void OnAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Items = _Inventory.Get_Items();
        for (auto Item : Items)
        {
            Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(Item), 1,
                "Every entry in a NoStacking inventory should hold exactly 1 unit");
        }

        Assert_Equals_Int(utils_item_trait_stackable::Get_EffectiveMaxStackSize(_Inventory, Items[0]), 1,
            "Effective max stack size in a NoStacking inventory should be 1");

        _Inventory.Request_StackItems(FCk_Request_Inventory_StackItems(Items[0], Items[1]),
            FCk_Delegate_Inventory_OnOperationResult_Stack(this, n"OnStackResult"));
    }

    UFUNCTION()
    private void OnStackResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InSourceItem,
        FCk_Handle_Item InTargetItem,
        ECk_Inventory_OperationResult_Stack InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Stack::Failed_TargetStackFull,
            f"Merging stacks under NoStacking should fail with Failed_TargetStackFull (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 3,
            "A rejected stack merge must not change the entry count");

        FinishSuccess();
    }
}
