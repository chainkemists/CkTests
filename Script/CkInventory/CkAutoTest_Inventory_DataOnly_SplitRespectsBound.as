// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: SPLIT RESPECTS ENTRY BOUND
//============================================================================
//
// A split mints a NEW entry, so the entry bound must gate it (regression
// guard: DataOnly TSplitStack used to skip the bounds check entirely and
// could overflow a Bounded inventory).
//   1. Create a BoundedByUniqueEntries(2) inventory.
//   2. Add Potion x3 (PreferStacking → 1 entry, stack 3).
//   3. Add Potion x1 (ForceNewItem → entry 2; at entry capacity).
//   4. Request_SplitStack(stack3, 1) → Failed_NoSpaceForNewItem; still 2 entries.
//
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_SplitRespectsBound : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private FCk_Handle_Item _StackedItem;
    private int _SettleTries = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SplitBound"),
            2,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 3);
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
            f"Add(Potion x3) should succeed (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 1, "Potion x3 should land as a single stack entry");

        if (InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Expected 1 created item, got {InItemsCreated.Num()}");
            return;
        }
        _StackedItem = InItemsCreated[0];

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

        // Let the deferred stack-count Override settle before splitting. A write made in the late
        // pump passes of frame N can fold mid-frame N+1 (after the inventory drain), so a fixed
        // one-frame wait is not enough — poll until the count actually reads back.
        WaitOneFrame(n"OnSettledBeforeSplit");
    }

    UFUNCTION()
    private void OnSettledBeforeSplit(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (utils_item_trait_stackable::Get_StackCount(_StackedItem) != 3 && _SettleTries < 40)
        {
            _SettleTries++;
            WaitOneFrame(n"OnSettledBeforeSplit");
            return;
        }

        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_StackedItem), 3,
            "Stacked item should read count 3 once the deferred Override settles");

        _Inventory.Request_SplitStack(FCk_Request_Inventory_SplitStack(_StackedItem, 1),
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

        Assert_True(InResult == ECk_Inventory_OperationResult_Split::Failed_NoSpaceForNewItem,
            f"Split at the entry bound should fail with Failed_NoSpaceForNewItem (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 2,
            "A rejected split must not mint a third entry past the bound");

        FinishSuccess();
    }
}
