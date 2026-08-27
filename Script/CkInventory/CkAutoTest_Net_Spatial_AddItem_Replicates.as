// Language=angelscript

//============================================================================
// CK AUTOMATION TEST - NETWORKED INVENTORY Spatial AddItem REPLICATION
//============================================================================
//
// Server calls Request_AddItemByDefinition on its grid-backed (Spatial)
// inventory; assert the new item replicates to the client via the
// FCk_RepData_Inventory_Spatial_Items handler. Server and client each have
// their own Spatial inventory child entity created by
// UCk_AutoTest_NetSubject_InventoryEntityScript_UE during Construct (symmetric
// setup), stashed on the actor as `_TestInventory_Spatial`. Mirrors the
// DataOnly AddItem net test but exercises the spatial items container.
//
// Surface: Ck.Inventory.Net.AS_Spatial_AddItem_Replicates
//============================================================================

class UCk_AutoTest_Net_Spatial_AddItem_Replicates : UCk_AutoTest_NetBase
{
    default _NetSubjectClass = ACk_AutoTest_NetSubject_Inventory_UE;

    private const int32 TargetItemCount = 1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject not found - harness misconfigured?"); return; }

        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto InventoryActor = Cast<ACk_AutoTest_NetSubject_Inventory_UE>(SubjectActor);
        if (InventoryActor == nullptr)
        { FinishFailure("subject actor isn't an inventory net-subject"); return; }

        auto Inventory = InventoryActor._TestInventory_Spatial;
        if (ck::Is_NOT_Valid(Inventory))
        { FinishFailure("spatial inventory handle not populated by entity-script"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            // Shield is 1x1 with a Tags-only trait - it has the grid Dimensions a spatial
            // placement needs and avoids the Stackable framework warning that Potion/Arrow fire
            // (warnings escalate to test failures). See CkAutoTest_Inventory_Spatial_*.
            auto ShieldDef = inv_gym_items::Shield();
            if (ShieldDef == nullptr)
            { FinishFailure("Shield item definition not loadable"); return; }

            auto Request = FCk_Request_Inventory_AddItemByDefinition(ShieldDef, TargetItemCount);
            Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            Inventory.Request_AddItemByDefinition(Request,
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

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded,
            "Server-side spatial AddItem operation should succeed");
        Assert_Equals_Int(InAmountAdded, TargetItemCount, "Server-side spatial AddItem amount");
        FinishSuccess();
    }

    private int _PollCount = 0;
    private const int kPollBudget = 400;

    UFUNCTION()
    private void OnInventoryPollTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        auto Subject = Get_SubjectEntity();
        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto InventoryActor = Cast<ACk_AutoTest_NetSubject_Inventory_UE>(SubjectActor);
        if (InventoryActor == nullptr)
        { WaitOneFrame(n"OnInventoryPollTick"); return; }

        auto Inventory = InventoryActor._TestInventory_Spatial;
        if (ck::Is_NOT_Valid(Inventory))
        { WaitOneFrame(n"OnInventoryPollTick"); return; }

        if (Inventory.Get_NumItems() == TargetItemCount)
        {
            FinishSuccess();
            return;
        }
        if (_PollCount > kPollBudget)
        { FinishFailure("client spatial inventory never received the replicated item"); return; }

        WaitOneFrame(n"OnInventoryPollTick");
    }
}
