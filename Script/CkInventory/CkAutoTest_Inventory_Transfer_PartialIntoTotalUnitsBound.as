// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: TRANSFER PARTIAL INTO TOTAL-UNITS BOUND
//============================================================================
//
// Verifies DoTransfer clamps to the target's absorbable units and settles as
// Success_Partial instead of failing after moving nothing:
//   1. Source: unbounded; holds Potion x8 (one stack).
//   2. Target: BoundedByTotalUnits(5).
//   3. Transfer AllAvailable → Success_Partial, CountTransferred=5.
//   4. Source keeps 3 units; target holds 5.
//
//============================================================================

class UCk_AutoTest_Inventory_Transfer_PartialIntoTotalUnitsBound : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _Target;
    private FCk_Handle_Item _SourceItem;

    // These settles were hand-rolled retry loops bounded by a try counter that
    // FELL THROUGH into the assertions on exhaustion, so a hang reported as a
    // value mismatch rather than as a timeout. WaitUntil names the condition it
    // was waiting on and is bounded by the test timeout.

    UFUNCTION()
    private void Check_SourceStackIsEight(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_item_trait_stackable::Get_StackCount(_SourceItem) == 8);
    }

    UFUNCTION()
    private void Check_SourceStackIsThree(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_item_trait_stackable::Get_StackCount(_SourceItem) == 3);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_UnitsTransfer_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto TargetParams = utils_inventory_data_only::Make_Params_BoundedByTotalUnits(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_UnitsTransfer_Target"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_data_only::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 8);
        _Source.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSourceStocked"));
    }

    UFUNCTION()
    private void OnSourceStocked(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
            f"Stocking the source with Potion x8 should succeed (got {InResult})");

        if (InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Expected the 8 units in 1 stack, got {InItemsCreated.Num()} items");
            return;
        }
        _SourceItem = InItemsCreated[0];

        // Let the stack-count Override settle before the transfer reads it.
        WaitUntil(n"Check_SourceStackIsEight", n"OnSourceSettled");
    }

    UFUNCTION()
    private void OnSourceSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }


        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_SourceItem), 8,
            "Source stack should hold 8 units before the transfer");

        auto Request = FCk_Request_Inventory_TransferItem_ToDataOnly(_SourceItem, _Target);
        _Source.Request_TransferItem_ToDataOnly(Request,
            FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransferResult"));
    }

    UFUNCTION()
    private void OnTransferResult(
        FCk_Handle_Inventory InSourceInventory,
        FCk_Handle_Item InItem,
        FCk_Handle_Inventory InTargetInventory,
        int InCountTransferred,
        FCk_Handle_Item InNewItemInTarget,
        ECk_Inventory_OperationResult_Transfer InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Transfer::Success_Partial,
            f"Transferring 8 units into units(5) should settle as Success_Partial (got {InResult})");
        Assert_Equals_Int(InCountTransferred, 5,
            "Exactly the target's 5 units of room should transfer");
        Assert_Equals_Int(_Target.Get_NumItems(), 1, "Target should hold the units as one new entry");
        Assert_Equals_Int(_Source.Get_NumItems(), 1, "Source keeps its (reduced) stack");

        // Both inventories' stack adjustments are deferred — settle before count asserts.
        WaitUntil(n"Check_SourceStackIsThree", n"OnTransferSettled");
    }

    UFUNCTION()
    private void OnTransferSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }


        Assert_Equals_Int(utils_item_trait_stackable::Get_StackCount(_SourceItem), 3,
            "Source stack should retain 8 - 5 = 3 units");
        Assert_Equals_Int(_Target.Get_TotalUnits(), 5, "Target should sit exactly at its 5-unit bound");
        Assert_Equals_Int(_Target.Get_RemainingCapacity(), 0, "Target should have no unit room left");

        FinishSuccess();
    }
}
