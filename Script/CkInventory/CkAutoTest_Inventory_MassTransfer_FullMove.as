// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: MASS TRANSFER - FULL MOVE
//============================================================================
//
// 5 items across 2 source inventories, 2 ample-room candidates. A mass transfer
// moves every item -> Success, UnitsMoved == 5, both sources empty, the candidate
// set holds all 5. Pins the happy path of Request_MassTransfer (transient-owned
// op entity, paced churn, OnComplete tally).
//============================================================================

class UCk_AutoTest_Inventory_MassTransfer_FullMove : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Inventory_DataOnly _SourceA;
    private FCk_Handle_Inventory_DataOnly _SourceB;
    private FCk_Handle_Inventory_DataOnly _CandA;
    private FCk_Handle_Inventory_DataOnly _CandB;
    private int32 _SeedsRemaining = 2;
    private bool  _Kicked = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _SourceA = MakeInv(LocalHandle, n"Inventory.AutoTest_MTFull_SrcA");
        _SourceB = MakeInv(LocalHandle, n"Inventory.AutoTest_MTFull_SrcB");
        _CandA   = MakeInv(LocalHandle, n"Inventory.AutoTest_MTFull_CandA");
        _CandB   = MakeInv(LocalHandle, n"Inventory.AutoTest_MTFull_CandB");

        auto AddA = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Key(), 3);
        _SourceA.Request_AddItemByDefinition(AddA,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeeded"));

        auto AddB = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 2);
        _SourceB.Request_AddItemByDefinition(AddB,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeeded"));
    }

    private FCk_Handle_Inventory_DataOnly MakeInv(FCk_Handle InOwner, FName InName)
    {
        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(InName),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        return utils_inventory_data_only::Add(InOwner, Params, ECk_Replication::DoesNotReplicate);
    }

    UFUNCTION()
    private void OnSeeded(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded)
        {
            FinishFailure(f"Setup: seeding a source failed (result={InResult})");
            return;
        }

        _SeedsRemaining -= 1;
        if (_SeedsRemaining > 0 || _Kicked) { return; }
        _Kicked = true;

        if (_SourceA.Get_NumItems() != 3 || _SourceB.Get_NumItems() != 2)
        {
            FinishFailure(f"Setup: expected 3 + 2 items, got {_SourceA.Get_NumItems()} + {_SourceB.Get_NumItems()}");
            return;
        }

        auto Candidates = TArray<FCk_Handle_Inventory>();
        Candidates.Add(_CandA);
        Candidates.Add(_CandB);

        auto Sources = TArray<FCk_Handle_Inventory>();
        Sources.Add(_SourceA);
        Sources.Add(_SourceB);

        auto Target  = FCk_BestTransferTargetParams(Candidates);
        auto Request = FCk_Request_Inventory_MassTransfer(Sources, Target);

        utils_inventory::Request_MassTransfer(InInventory, Request,
            FCk_Delegate_Inventory_MassTransfer_OnComplete(this, n"OnComplete"));
    }

    UFUNCTION()
    private void OnComplete(
        FCk_Handle InOperation,
        ECk_Inventory_MassTransfer_Result InResult,
        int InUnitsMoved,
        int InItemsFullyMoved,
        int InItemsFailed)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_MassTransfer_Result::Success,
            f"Every item should fully move -> Success (got {InResult})");
        Assert_Equals_Int(InUnitsMoved, 5, "All 5 units should move");
        Assert_Equals_Int(InItemsFailed, 0, "No item should fail to place");
        Assert_Equals_Int(_SourceA.Get_NumItems(), 0, "Source A should be empty");
        Assert_Equals_Int(_SourceB.Get_NumItems(), 0, "Source B should be empty");
        Assert_Equals_Int(_CandA.Get_NumItems() + _CandB.Get_NumItems(), 5,
            "The candidate set should hold all 5 moved items");

        FinishSuccess();
    }
}
