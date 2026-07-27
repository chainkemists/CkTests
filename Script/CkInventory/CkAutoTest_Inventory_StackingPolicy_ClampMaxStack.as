// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: STACKING POLICY — CLAMP MAX STACK SIZE
//============================================================================
//
// Verifies ECk_Inventory_StackingPolicy::ClampMaxStackSize caps stacks at
// min(definition max, clamp). Potion defines max 10; the inventory clamps to 3.
//   1. Add Potion x7 (PreferStacking) → 3 entries (3 + 3 + 1), all 7 units in.
//   2. Each entry's count never exceeds the clamp.
//
// The settle was a hand-rolled retry loop bounded by a try counter.
// On exhausting the budget it FELL THROUGH into the assertions anyway, so a
// genuine hang reported as "Units must be conserved across the clamped stacks"
// — a data-integrity failure pointing at the inventory system when the real
// cause was that the wait gave up. WaitUntil names the condition it was
// waiting on and is bounded by the test timeout instead.
//============================================================================

class UCk_AutoTest_Inventory_StackingPolicy_ClampMaxStack : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_ClampStack"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        Params.Set_StackingPolicy(ECk_Inventory_StackingPolicy::ClampMaxStackSize);
        Params.Set_MaxStackSizeClamp(3);

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 7);
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
            f"Add(Potion x7) should fully succeed across clamped stacks (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 7, "All 7 units should be added");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 3,
            "7 units under clamp(3) should land as 3 entries (3 + 3 + 1)");

        WaitUntil(n"Check_SevenUnitsFolded", n"OnAddSettled");
    }

    UFUNCTION()
    private void Check_SevenUnitsFolded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Inventory.Get_TotalUnits() == 7);
    }

    UFUNCTION()
    private void OnAddSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Items = _Inventory.Get_Items();
        auto TotalUnits = 0;

        for (auto Item : Items)
        {
            auto Count = utils_item_trait_stackable::Get_StackCount(Item);
            Assert_True(Count <= 3, f"No stack may exceed the clamp of 3 (found {Count})");
            TotalUnits += Count;
        }

        Assert_Equals_Int(TotalUnits, 7, "Units must be conserved across the clamped stacks");
        Assert_Equals_Int(utils_item_trait_stackable::Get_EffectiveMaxStackSize(_Inventory, Items[0]), 3,
            "Effective max stack size should be min(definition 10, clamp 3) = 3");

        FinishSuccess();
    }
}
