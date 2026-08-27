// Language=angelscript

//============================================================================
// CK AUTOMATION TEST - NETWORKED INVENTORY DataOnly AddItem REPLICATION
//============================================================================
//
// Server calls Request_AddItemByDefinition on its inventory; assert the new
// item replicates to the client via the FCk_RepData_Inventory_DataOnly_Items
// handler. Server and client each have their own inventory child entity
// created by UCk_AutoTest_NetSubject_InventoryEntityScript_UE during Construct
// (symmetric setup), so the rep handler has a target on both sides.
//
// Surface: Ck.Inventory.Net.AS_DataOnly_AddItem_Replicates
//============================================================================

class UCk_AutoTest_Net_DataOnly_AddItem_Replicates : UCk_AutoTest_NetBase
{
    // Override the harness's spawn-subject class. The generator reads this from
    // the CDO and emits the matching SpawnActor in the Replicated-mode C++ stub.
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

        auto Inventory = InventoryActor._TestInventory;
        if (ck::Is_NOT_Valid(Inventory))
        { FinishFailure("inventory handle not populated by entity-script"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            // Server side: drive the add via the standard request API.
            auto PotionDef = inv_gym_items::Potion();
            if (PotionDef == nullptr)
            { FinishFailure("Potion item definition not loadable"); return; }

            auto Request = FCk_Request_Inventory_AddItemByDefinition(PotionDef, TargetItemCount);
            Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            Inventory.Request_AddItemByDefinition(Request,
                FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
            return;
        }

        // Client side: poll for the replicated item to arrive.
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
            "Server-side AddItem operation should succeed");
        Assert_Equals_Int(InAmountAdded, TargetItemCount, "Server-side AddItem amount");
        FinishSuccess();
    }

    UFUNCTION()
    private void OnInventoryPollTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

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
        if (NumItems == TargetItemCount)
        {
            Assert_True(true, "Item replicated to client inventory");
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnInventoryPollTick");
    }
}
