// Language=angelscript

//============================================================================
// CK AUTOMATION TEST — NETWORKED INVENTORY DataOnly RemoveItem REPLICATION
//============================================================================
//
// Diagnostic instrumentation in place: each step records to the result fragment
// via Assert_True. On test failure the harness reports the first failure
// message, telling us which step stalled.
//============================================================================

class UCk_AutoTest_Net_DataOnly_RemoveItem_Replicates : UCk_AutoTest_NetBase
{
    default _NetSubjectClass = ACk_AutoTest_NetSubject_Inventory_UE;

    private FCk_Handle_Inventory_DataOnly _ServerInventory;
    private FCk_Handle_Item _ItemToRemove;
    private bool _ClientSawItemPresent = false;
    private int _ClientPollCount = 0;

    // Number of polling iterations the server waits between the Add-callback and the
    // Remove-call. Each iteration is one CkTimer-driven WaitOneFrame (0.05s), so 20 iterations
    // ≈ 1 second of real time. CkInventory's container rep handler delivers snapshot state,
    // not deltas — if Add and Remove happen within one rep cycle, the client only sees the
    // final "0 items" state and never observes the intermediate "1 item" state. The wait gives
    // Iris time to deliver the post-Add snapshot to the client before the Remove queues a new
    // one. (Diagnostic DIAG-I in earlier iterations of this test pinned this exact failure.)
    private const int kServerSettleIterations = 20;
    private int _ServerSettleCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("DIAG-A: subject not found"); return; }

        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto InventoryActor = Cast<ACk_AutoTest_NetSubject_Inventory_UE>(SubjectActor);
        if (InventoryActor == nullptr)
        { FinishFailure("DIAG-B: actor cast failed"); return; }

        auto Inventory = InventoryActor._TestInventory;
        if (ck::Is_NOT_Valid(Inventory))
        { FinishFailure("DIAG-C: inventory handle null"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            _ServerInventory = Inventory;

            auto PotionDef = inv_gym_items::Potion();
            if (PotionDef == nullptr)
            { FinishFailure("DIAG-D: Potion def null"); return; }

            auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(PotionDef, 1);
            AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            Inventory.Request_AddItemByDefinition(AddRequest,
                FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
            return;
        }

        WaitOneFrame(n"OnInventoryPollTick");
    }

    UFUNCTION()
    private void OnAddResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded)
        { FinishFailure("DIAG-E: add result not Success_AllAdded"); return; }
        if (InItemsCreated.Num() != 1)
        { FinishFailure("DIAG-F: AddResult didn't surface exactly one item"); return; }

        _ItemToRemove = InItemsCreated[0];

        // Defer the Remove via a settle loop so the post-Add rep snapshot lands on the client
        // before the Remove queues a new one. See kServerSettleIterations comment above.
        WaitOneFrame(n"OnServerSettleTick");
    }

    UFUNCTION()
    private void OnServerSettleTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ServerSettleCount++;
        if (_ServerSettleCount < kServerSettleIterations)
        {
            WaitOneFrame(n"OnServerSettleTick");
            return;
        }

        _ServerInventory.Request_RemoveItem(FCk_Request_Inventory_RemoveItem(_ItemToRemove),
            FCk_Delegate_Inventory_OnOperationResult_Remove(this, n"OnRemoveResult"));
    }

    UFUNCTION()
    private void OnRemoveResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        ECk_Inventory_OperationResult_Remove InResult)
    {
        if (IsFinished()) { return; }

        if (InResult != ECk_Inventory_OperationResult_Remove::Success)
        { FinishFailure("DIAG-G: remove result not Success"); return; }
        if (_ServerInventory.Get_NumItems() != 0)
        { FinishFailure("DIAG-H: server NumItems != 0 after Remove"); return; }

        FinishSuccess();
    }

    UFUNCTION()
    private void OnInventoryPollTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ClientPollCount++;

        auto Subject = Get_SubjectEntity();
        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto InventoryActor = Cast<ACk_AutoTest_NetSubject_Inventory_UE>(SubjectActor);
        if (InventoryActor == nullptr)
        {
            WaitOneFrame(n"OnInventoryPollTick");
            return;
        }

        auto Inventory = InventoryActor._TestInventory;
        if (ck::Is_NOT_Valid(Inventory))
        {
            WaitOneFrame(n"OnInventoryPollTick");
            return;
        }

        auto NumItems = Inventory.Get_NumItems();
        if (NumItems >= 1)
        {
            _ClientSawItemPresent = true;
        }
        if (_ClientSawItemPresent && NumItems == 0)
        {
            FinishSuccess();
            return;
        }

        // Bail if we've polled a LOT without seeing the cycle complete. This converts a
        // 30s harness-side timeout into an actionable diagnostic that pins WHERE we stalled.
        if (_ClientPollCount > 400)
        {
            // 400 polls * 0.05s = 20s of polling
            if (!_ClientSawItemPresent)
            { FinishFailure("DIAG-I: client never observed NumItems>=1 (add never replicated)"); return; }
            else
            { FinishFailure("DIAG-J: client saw add but never observed NumItems==0 (remove never replicated)"); return; }
        }

        WaitOneFrame(n"OnInventoryPollTick");
    }
}
