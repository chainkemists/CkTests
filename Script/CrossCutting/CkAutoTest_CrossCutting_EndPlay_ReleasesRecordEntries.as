// Language=angelscript

//============================================================================
// CK CROSS-CUTTING — AUTOMATION TEST: ENDPLAY RELEASES RECORD ENTRIES
//============================================================================
//
// Pins the Record-of-Entities prune contract: when a member entity is
// released through its module's proper API (e.g. Request_RemoveItem), the
// owning Record's valid-entry count must drop on the next processor tick.
// Every feature-module's Record-of-X pattern depends on this — Inventory is
// the load-bearing canonical user.
//
// Note: the framework rejects direct Request_DestroyEntity on Record-owned
// members (CkInventory items in particular) because the parent record's
// invariants would be violated. Use the module's remove API.
//
// The refactor is expected to simplify the prune processor. This test
// catches a regression where the prune is skipped, deferred indefinitely,
// or pruned twice.
//
// Setup:
//   - Add a DataOnly inventory to the test entity.
//   - Add 2 swords via Request_AddItemByDefinition.
//   - WaitOneFrame for the add to settle, snapshot NumItems == 2.
//   - Issue Request_RemoveItem on one item.
//   - WaitOneFrame for the remove + prune to settle.
//   - Assert NumItems == 1.
//
// Pass: NumItems drops from 2 to 1 within the post-remove WaitOneFrame.
// Fail: count stays at 2, drops to 0, or harness times out.
//============================================================================

class UCk_AutoTest_CrossCutting_EndPlay_ReleasesRecordEntries : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_Inventory_DataOnly _Inventory;
    private FCk_Handle_Item _ItemToRemove;
    private int32 _ItemsAddedSnapshot = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_BaseFacade_Target"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto SwordDef = inv_gym_items::Sword();
        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(SwordDef, 2);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(AddRequest,
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

        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded ||
            InItemsCreated.Num() != 2)
        {
            FinishFailure(f"Setup failed: expected 2 items added; result={InResult}, items={InItemsCreated.Num()}");
            return;
        }

        _ItemToRemove = InItemsCreated[0];
        _ItemsAddedSnapshot = _Inventory.Get_NumItems();

        WaitUntil(n"Check_BothItemsPresent", n"OnSettleAfterAdd");
    }

    // _Inventory is this test's own component, so its item count cannot be
    // occupied by another test — no shared-surface ambiguity here.
    UFUNCTION()
    private void Check_BothItemsPresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Inventory.Get_NumItems() >= 2);
    }

    // Decisive: the count is 2 on entry, so this is false until the Record prune
    // actually runs on a later processor pass.
    UFUNCTION()
    private void Check_RecordPruned(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Inventory.Get_NumItems() == 1);
    }

    UFUNCTION()
    private void OnSettleAfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_ItemsAddedSnapshot, 2,
            "Pre-remove snapshot: inventory should hold 2 items after adding 2 ForceNewItem swords");

        // Properly remove one item via the module API. The Record's prune
        // must drop the count on the next processor pass.
        auto RemoveRequest = FCk_Request_Inventory_RemoveItem(_ItemToRemove);
        _Inventory.Request_RemoveItem(RemoveRequest,
            FCk_Delegate_Inventory_OnOperationResult_Remove(this, n"OnRemoveResult"));
    }

    UFUNCTION()
    private void OnRemoveResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InRemovedItem,
        ECk_Inventory_OperationResult_Remove InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Remove::Success,
            f"Request_RemoveItem should succeed; got {InResult}");

        WaitUntil(n"Check_RecordPruned", n"OnSettleAfterRemove");
    }

    UFUNCTION()
    private void OnSettleAfterRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_Inventory.Get_NumItems(), 1,
            "Inventory NumItems should drop from 2 to 1 after Request_RemoveItem pruned the Record");

        FinishSuccess();
    }
}
