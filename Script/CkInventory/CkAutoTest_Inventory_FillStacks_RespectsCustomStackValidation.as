// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: FILL-STACKS RESPECTS CUSTOM STACK VALIDATION
//============================================================================
//
// Regression guard: Request_FillExistingStacks used to skip the inventory's
// custom stack validation entirely, so a per-inventory stacking restriction
// was enforced on direct StackItems requests but silently bypassed by
// AddByDefinition's PreferStacking pre-fill.
//   1. Inventory whose CustomCanStackItems always rejects.
//   2. Add Potion x1 → entry 1.
//   3. Add Potion x1 (PreferStacking) → pre-fill must SKIP the existing stack
//      → a second entry is created (2 entries, 1 unit each).
//
//============================================================================

class UCk_AutoTest_Inventory_FillStacks_RespectsCustomStackValidation : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;

    UFUNCTION()
    private void RejectAllStacking(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InSourceItem,
        FCk_Handle_Item InTargetItem,
        bool&out OutCanStack)
    {
        OutCanStack = false;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_FillStacksCustomReject"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic(this, n"RejectAllStacking"));

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
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
            f"First Add(Potion x1) should succeed (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 1, "First add should create the first entry");

        WaitOneFrame(n"OnFirstAddSettled");
    }

    UFUNCTION()
    private void OnFirstAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // PreferStacking on purpose — the custom rejection must defeat the pre-fill.
        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
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
            f"Second add should succeed as a NEW entry (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 2,
            "Custom stack rejection must force a second entry instead of merging");

        WaitOneFrame(n"OnSecondAddSettled");
    }

    UFUNCTION()
    private void OnSecondAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        for (auto Item : _Inventory.Get_Items())
        {
            Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(Item), 1,
                "No units may have merged through the rejected pre-fill");
        }

        FinishSuccess();
    }
}
