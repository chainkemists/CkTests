// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: OVERRIDE BOUNDS
//============================================================================
//
// Verifies that Request_OverrideBounds expands a bounded data-only inventory's
// capacity, allowing previously-rejected adds to succeed:
//   1. Create a bounded(1) inventory.
//   2. Add Bare → Success (count=1, at capacity).
//   3. Add Bare → rejected (Failed_NoSpaceAvailable).
//   4. Request_OverrideBounds(5).
//   5. Poll until Get_BoundsInfo reports 5 (the request is deferred —
//      issuing the next add immediately uses the OLD bound and fails).
//   6. Add Bare → Success (count=2, capacity now 5).
//
// IMPORTANT — TIMING:
//   Request_OverrideBounds is a deferred request handled by a processor
//   on a subsequent frame. Queueing the next add in the same frame as
//   the override request results in the add being processed against the
//   OLD bound. The first revision of this test made that mistake. The
//   correct pattern is to poll Get_BoundsInfo in a tick callback and
//   only queue the post-override add once the new bound is observable.
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_OverrideBounds : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;
    private int32 _AddsObserved = 0;
    private bool _OverrideRequested = false;
    private bool _PostOverrideAddQueued = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Bounded"),
            1,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));

        QueueAdd();
    }

    private void QueueAdd()
    {
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
        _AddsObserved++;

        if (_AddsObserved == 1)
        {
            Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
                f"Add #1 at capacity 1 should succeed (got {InResult})");
            QueueAdd();
            return;
        }

        if (_AddsObserved == 2)
        {
            Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Failed_NoSpaceAvailable,
                f"Add #2 over bounded(1) should fail with Failed_NoSpaceAvailable pre-override (got {InResult})");

            _Inventory.Request_OverrideBounds(5);
            _OverrideRequested = true;
            // OnTick will queue the post-override add once bounds reflect 5.
            return;
        }

        // Third add — should now succeed under expanded bound.
        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
            f"Add #3 after OverrideBounds(5) should succeed (got {InResult})");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 2,
            "Inventory should hold 2 items after expanded-bound add");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (!_OverrideRequested) { return; }
        if (_PostOverrideAddQueued) { return; }

        auto BoundsInfo = _Inventory.Get_BoundsInfo();
        if (BoundsInfo.Get_Mode() == ECk_Inventory_DataOnly_BoundMode::BoundedByUniqueEntries && BoundsInfo.Get_Value() >= 5)
        {
            _PostOverrideAddQueued = true;
            QueueAdd();
        }
    }
}
