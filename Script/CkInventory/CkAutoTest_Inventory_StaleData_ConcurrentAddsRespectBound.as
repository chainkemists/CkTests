// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: CONCURRENT ADDS RESPECT THE UNIT BOUND
//============================================================================
//
// Characterization of the cross-request stale-data hazard. Stack counts are
// attribute-backed, so a stack write is a deferred modifier that does not fold
// until a later pump pass. Two stacking adds issued in the SAME frame drain in
// one HandleRequests pass: the second reads the first's un-folded write as
// stale, sees room that is already gone, and over-commits past the bound.
//
// A BoundedByTotalUnits(6) inventory seeded to 4 units has room for 2 more.
// Two same-frame adds of 5 each: coherent reads => 2 then 0 (holds at 6);
// stale cross-request reads => 2 then 2 (over-commits to 8).
//
// Guards the paced-draining contract (one request per pump pass, so a request's
// deferred stack write folds before the next request reads it). Regresses to 8
// if HandleRequests ever drains the whole queue in a single pass again.
//============================================================================

class UCk_AutoTest_Inventory_StaleData_ConcurrentAddsRespectBound : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_Inventory_DataOnly _Target;
    private int32 _SeedTries = 0;
    private int32 _SettleFrames = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_BoundedByTotalUnits(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_StaleConcurrentAdds"), 6,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto SeedRequest = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 4);
        _Target.Request_AddItemByDefinition(SeedRequest,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeedResult"));
    }

    UFUNCTION()
    private void OnSeedResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded)
        {
            FinishFailure(f"Setup: seeding Potion x4 failed (result={InResult})");
            return;
        }
        WaitOneFrame(n"OnSeedSettled");
    }

    UFUNCTION()
    private void OnSeedSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Deferred stack write can fold a frame later — poll until the seed has settled.
        if (_Target.Get_TotalUnits() != 4 && _SeedTries < 40)
        {
            _SeedTries += 1;
            WaitOneFrame(n"OnSeedSettled");
            return;
        }

        if (_Target.Get_TotalUnits() != 4)
        {
            FinishFailure(f"Setup: expected 4 units after seeding, got {_Target.Get_TotalUnits()}");
            return;
        }

        // Two stacking adds in the SAME frame. Both drain in one HandleRequests pass.
        auto Add1 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 5);
        auto Add2 = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 5);
        _Target.Request_AddItemByDefinition(Add1, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        _Target.Request_AddItemByDefinition(Add2, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());

        WaitOneFrame(n"OnSettle");
    }

    UFUNCTION()
    private void OnSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Let both adds + their deferred stack writes fully settle before reading the total.
        _SettleFrames += 1;
        if (_SettleFrames < 6)
        {
            WaitOneFrame(n"OnSettle");
            return;
        }

        Assert_Equals_Int(_Target.Get_TotalUnits(), 6,
            "BoundedByTotalUnits(6) must hold at most 6 units after two same-frame stacking adds");

        FinishSuccess();
    }
}
