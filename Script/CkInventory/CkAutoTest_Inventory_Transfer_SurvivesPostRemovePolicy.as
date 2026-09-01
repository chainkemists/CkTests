// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: TRANSFER IS NOT A CONSUME
//============================================================================
//
// The regression risk of putting a destroy inside TRemoveItem is that TRANSFER
// is built out of it. DoTransfer calls the very same handler (remove from
// source, add to target, re-add on rollback), so a destroy that leaked into
// that path would delete the moved item mid-transfer and silently eat it.
//
// The defence is that the destroy is opt-in per REQUEST and DoTransfer builds
// its own remove request without one, so it takes the default KeepItem. That is
// an argument about the code; this is the gate.
//
// The item is followed by IDENTITY, not by count: the transferred entity must be
// the SAME entity that was in the source, still alive, now in the target. A
// count-only assertion would pass if the transfer destroyed the original and the
// target happened to mint a replacement, which is exactly the failure mode a
// stack-merging transfer could hide.
//
// Then the item is checked again a frame later. A deferred destroy tagged during
// the transfer would not have been reaped yet at the callback, so an
// immediately-after check alone could not tell a survivor from a corpse.
//============================================================================

class UCk_AutoTest_Inventory_Transfer_SurvivesPostRemovePolicy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _Target;
    private FCk_Handle_Item _SeededItem;
    private bool _SourceItemSeen = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_PostRemovePolicy_Source"), 5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto TargetParams = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_PostRemovePolicy_Target"), 5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_data_only::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Source.Request_AddItemByDefinition(AddRequest,
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
        if (_SourceItemSeen) { return; }

        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded ||
            InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Setup: failed to seed source inventory (result={InResult})");
            return;
        }
        _SourceItemSeen = true;
        _SeededItem = InItemsCreated[0];

        auto Request = FCk_Request_Inventory_TransferItem_ToDataOnly(_SeededItem, _Target);
        _Source.Request_TransferItem_ToDataOnly(Request,
            FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransferResult"));
    }

    UFUNCTION()
    private void OnTransferResult(
        FCk_Handle_Inventory InSource,
        FCk_Handle_Item InSourceItem,
        FCk_Handle_Inventory InTarget,
        int InAmountTransferred,
        FCk_Handle_Item InTargetItem,
        ECk_Inventory_OperationResult_Transfer InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Transfer::Success,
            f"the transfer should still report Success (got {InResult})");
        Assert_Equals_Int(_Source.Get_NumItems(), 0, "the source should be empty after the move");
        Assert_Equals_Int(_Target.Get_NumItems(), 1, "the target should hold the moved item");

        Assert_True(ck::IsValid(_SeededItem),
            "the transferred item must survive the remove half of the transfer");

        const FCk_Handle SeededEntity = _SeededItem;
        const FCk_Handle TargetItemEntity = InTargetItem;
        Assert_True(SeededEntity == TargetItemEntity,
            "the item in the target must be the SAME entity that was in the source, not a replacement");

        WaitFrames(2, n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // The check that a deferred destroy would fail: a corpse tagged during the transfer is
        // only reaped a frame or two later, so this is where an eaten item shows up.
        Assert_True(ck::IsValid(_SeededItem),
            "the transferred item must still be alive after the lifetime processor has run");
        Assert_Equals_Int(_Target.Get_NumItems(), 1,
            "the target must still hold the moved item once destroys have been reaped");

        FinishSuccess();
    }
}
