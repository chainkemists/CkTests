// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: DECLARED CONSUME ACTUALLY CONSUMES
//============================================================================
//
// FCk_Request_Inventory_RemoveItem carries a PostRemovePolicy because a removal
// means two different things and the request could not previously say which.
// KeepItem is a relocation - the item survives and something else will hold it.
// DestroyItem is a CONSUME - it was spent, sold, trashed, and nothing will hold
// it again.
//
// The policy has to live on the request rather than at the call site because
// Request_RemoveItem is DEFERRED: destroying the entity at the call site makes
// the queued handler bail on an invalid handle, so the record entry is never
// disconnected. The handler is the only place that knows the removal landed, so
// it is the only place the destroy can be atomic with it. Every caller that got
// this wrong left an item alive and invisible - absent from Get_Items and
// Get_NumItems (both record-based) yet still a real entity, captured into every
// snapshot, swept only by its ex-container's destroy cascade.
//
// This pins BOTH halves of the declared consume, because either alone is a lie:
//
//   * the RECORD half - Get_NumItems drops to 0. Without it a "destroy" could
//     leave a dangling entry that every later query trips over.
//   * the ENTITY half - the item is actually gone a frame later. Without it the
//     policy would be decorative and the leak would be untouched.
//
// The precondition (the item is alive and IN the record before the remove) is
// asserted first so the test cannot pass vacuously against an add that failed.
//
// Companion to CkAutoTest_Inventory_DataOnly_RemoveReleasesLifetimeClaim, which
// pins the DEFAULT policy: KeepItem must leave the item alive.
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_RemoveAndDestroyConsumesTheItem : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private FCk_Handle_Item _Item;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Bounded"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
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
        if (InItemsCreated.Num() == 0)
        {
            FinishFailure("Add did not produce any item to consume");
            return;
        }

        _Item = InItemsCreated[0];

        Assert_True(ck::IsValid(_Item),
            "PRECONDITION: the added item should be a live entity before the consume");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 1,
            "PRECONDITION: the added item should be IN the record before the consume");

        auto RemoveRequest = FCk_Request_Inventory_RemoveItem(_Item);
        RemoveRequest.Set_PostRemovePolicy(ECk_Inventory_PostRemovePolicy::DestroyItem);
        _Inventory.Request_RemoveItem(RemoveRequest,
            FCk_Delegate_Inventory_OnOperationResult_Remove(this, n"OnRemoveResult"));
    }

    UFUNCTION()
    private void OnRemoveResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        ECk_Inventory_OperationResult_Remove InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Remove::Success,
            f"Remove result should be Success (got {InResult})");

        // The record half, asserted at the one instant it is unambiguous: the handler has run.
        Assert_Equals_Int(_Inventory.Get_NumItems(), 0,
            "a consumed item must be disconnected from the record, not merely destroyed under it");

        // The entity half is NOT asserted here on purpose. Request_DestroyEntity tags the entity
        // and the lifetime processor reaps it later, and default validity passes an entity that has
        // only been tagged - so a check on this line would be measuring the tag, not the death.
        WaitUntil(n"Check_ItemIsGone", n"OnItemGone");
    }

    UFUNCTION()
    private void Check_ItemIsGone(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Item));
    }

    UFUNCTION()
    private void OnItemGone(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(ck::Is_NOT_Valid(_Item),
            "a DestroyItem removal must actually destroy the item entity, not just unlist it");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 0,
            "the record must stay empty after the destroy is reaped");

        FinishSuccess();
    }
}
