// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: BOUNDED BY TOTAL UNITS
//============================================================================
//
// Verifies the BoundedByTotalUnits metric: the limit counts the SUM of stack
// counts, not unique entries.
//   1. Create a BoundedByTotalUnits(6) inventory.
//   2. Add Potion x4 (PreferStacking) → Success_AllAdded; 1 entry, 4 units.
//   3. Add Potion x4 again → Success_PartiallyAdded with AmountAdded=2
//      (only 2 units of room remain); still 1 entry, 6 units.
//   4. Add Potion x1 → Failed_NoSpaceAvailable; RemainingCapacity is 0.
//
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_TotalUnitsBound : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private int _SettleTries = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_BoundedByTotalUnits(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_TotalUnits"),
            6,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        Assert_True(_Inventory.Get_EffectiveBoundMode() == ECk_Inventory_DataOnly_BoundMode::BoundedByTotalUnits,
            "Effective bound mode should report BoundedByTotalUnits");

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 4);
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
            f"Add(Potion x4) into units(6) should fully succeed (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 4, "First add should report 4 units added");

        // Stack writes settle via deferred attribute modifiers — wait before the next
        // capacity-sensitive operation reads TotalUnits.
        WaitOneFrame(n"OnFirstAddSettled");
    }

    UFUNCTION()
    private void OnFirstAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Deferred stack writes can fold a frame later than a single wait — poll until settled.
        if (_Inventory.Get_TotalUnits() != 4 && _SettleTries < 40)
        {
            _SettleTries++;
            WaitOneFrame(n"OnFirstAddSettled");
            return;
        }

        Assert_Equals_Int(_Inventory.Get_TotalUnits(), 4, "Inventory should hold 4 units after the first add");
        Assert_Equals_Int(_Inventory.Get_RemainingCapacity(), 2, "2 units of room should remain");
        _SettleTries = 0;

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 4);
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

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_PartiallyAdded,
            f"Add(Potion x4) with 2 units of room should partially succeed (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 2, "Second add should absorb exactly the 2 remaining units");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 1,
            "Units should have merged into the existing stack (entry count is unconstrained but stacking wins)");

        WaitOneFrame(n"OnSecondAddSettled");
    }

    UFUNCTION()
    private void OnSecondAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_Inventory.Get_TotalUnits() != 6 && _SettleTries < 40)
        {
            _SettleTries++;
            WaitOneFrame(n"OnSecondAddSettled");
            return;
        }

        Assert_Equals_Int(_Inventory.Get_TotalUnits(), 6, "Inventory should now sit at its 6-unit bound");
        Assert_Equals_Int(_Inventory.Get_RemainingCapacity(), 0, "No unit room should remain");

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
        _Inventory.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnThirdAdd"));
    }

    UFUNCTION()
    private void OnThirdAdd(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Failed_NoSpaceAvailable,
            f"Add over the unit bound should fail with Failed_NoSpaceAvailable (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_TotalUnits(), 6, "Unit count must not exceed the bound");

        FinishSuccess();
    }
}
