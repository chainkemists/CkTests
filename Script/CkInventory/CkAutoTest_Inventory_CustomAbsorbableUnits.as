// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: CUSTOM ABSORBABLE-UNITS QUOTA
//============================================================================
//
// Verifies the quantitative acceptance quota (weight-style custom rule):
// a dynamic CustomGetAbsorbableUnits hook that allows at most 5 total units
// composes by min() with the built-in capacity and gates every add path.
//   1. Unbounded inventory + quota hook "5 - TotalUnits".
//   2. Add Potion x4 -> Success_AllAdded (quota room 5).
//   3. Add Potion x4 -> Success_PartiallyAdded, AmountAdded=1 (quota room 1).
//   4. Add Potion x1 -> Failed_NoSpaceAvailable (quota room 0).
//
//============================================================================

class UCk_AutoTest_Inventory_CustomAbsorbableUnits : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;

    // These settles were hand-rolled retry loops bounded by a try counter that
    // FELL THROUGH into the assertions on exhaustion, so a hang reported as a
    // value mismatch rather than as a timeout. WaitUntil names the condition it
    // was waiting on and is bounded by the test timeout.

    UFUNCTION()
    private void Check_FourUnits(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Inventory.Get_TotalUnits() == 4);
    }

    UFUNCTION()
    private void Check_FiveUnits(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Inventory.Get_TotalUnits() == 5);
    }

    UFUNCTION()
    private void GetQuota(
        FCk_Handle_Inventory InInventory,
        UCk_InventoryItem_Definition InDefinition,
        FCk_Handle_Item InItem,
        int&in OutAbsorbableUnits)
    {
        OutAbsorbableUnits = Math::Max(0, 5 - InInventory.Get_TotalUnits());
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Quota"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        Params.Set_CustomGetAbsorbableUnitsDynamic(FCk_Delegate_Inventory_CustomGetAbsorbableUnits_Dynamic(this, n"GetQuota"));

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

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
            f"Add(Potion x4) under quota 5 should fully succeed (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 4, "First add should report 4 units added");

        WaitUntil(n"Check_FourUnits", n"OnFirstAddSettled");
    }

    UFUNCTION()
    private void OnFirstAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }


        Assert_Equals_Int(_Inventory.Get_AbsorbableUnits(inv_gym_items::Potion()), 1,
            "Absorbable units should report the quota's remaining 1");

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
            f"Add(Potion x4) with quota room 1 should partially succeed (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 1, "Second add should absorb exactly the quota's remaining 1 unit");

        WaitUntil(n"Check_FiveUnits", n"OnSecondAddSettled");
    }

    UFUNCTION()
    private void OnSecondAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }


        Assert_Equals_Int(_Inventory.Get_TotalUnits(), 5, "Inventory should hold exactly the quota's 5 units");

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
            f"Add with quota exhausted should fail with Failed_NoSpaceAvailable (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_TotalUnits(), 5, "Quota must hold the line at 5 units");

        FinishSuccess();
    }
}
