// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: SOURCE FIFO SURVIVES REENTRANT CALLBACK
//============================================================================
//
// Two transfers are queued on one source. The first completion callback queues
// a third transfer on that same source. The coordinator must preserve the
// original source FIFO and must not lose the callback-created request while
// draining copied request fragments.
//============================================================================

class UCk_AutoTest_Inventory_Transfer_SourceFifo_ReentrantCallback : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _B;
    private FCk_Handle_Inventory_DataOnly _C;
    private FCk_Handle_Inventory_DataOnly _D;
    private TArray<FCk_Handle_Item> _Items;
    private TArray<FCk_Handle_Item> _CallbackOrder;
    private int32 _SeedCallbacks = 0;
    private bool _InitialTransfersDispatched = false;
    private bool _ReentrantTransferDispatched = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SourceFifoReentrant_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(InHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto BParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SourceFifoReentrant_B"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _B = utils_inventory_data_only::Add(InHandle, BParams, ECk_Replication::DoesNotReplicate);

        auto CParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SourceFifoReentrant_C"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _C = utils_inventory_data_only::Add(InHandle, CParams, ECk_Replication::DoesNotReplicate);

        auto DParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SourceFifoReentrant_D"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _D = utils_inventory_data_only::Add(InHandle, DParams, ECk_Replication::DoesNotReplicate);

        for (int32 Index = 0; Index < 3; ++Index)
        {
            auto Add = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
            Add.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            _Source.Request_AddItemByDefinition(Add,
                FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeeded"));
        }
    }

    UFUNCTION()
    private void OnSeeded(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        FCk_Handle_Inventory Source = _Source;
        if (InInventory != Source || InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded
            || InAmountAdded != 1 || InItemsCreated.Num() != 1)
        { FinishFailure("Setup: expected three successful ForceNew source items"); return; }
        _Items.Add(InItemsCreated[0]);
        _SeedCallbacks += 1;
        if (_SeedCallbacks != 3 || _InitialTransfersDispatched) { return; }
        _InitialTransfersDispatched = true;

        _Source.Request_TransferItem_ToDataOnly(
            FCk_Request_Inventory_TransferItem_ToDataOnly(_Items[0], _B),
            FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransfer"));
        _Source.Request_TransferItem_ToDataOnly(
            FCk_Request_Inventory_TransferItem_ToDataOnly(_Items[1], _C),
            FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransfer"));
    }

    UFUNCTION()
    private void OnTransfer(
        FCk_Handle_Inventory InSource,
        FCk_Handle_Item InSourceItem,
        FCk_Handle_Inventory InTarget,
        int InAmountTransferred,
        FCk_Handle_Item InTargetItem,
        ECk_Inventory_OperationResult_Transfer InResult)
    {
        if (IsFinished()) { return; }
        FCk_Handle_Inventory Source = _Source;
        if (InSource != Source || _Items.Contains(InSourceItem) == false
            || InResult != ECk_Inventory_OperationResult_Transfer::Success
            || InAmountTransferred != 1 || ck::Is_NOT_Valid(InTargetItem))
        { FinishFailure("Every source-FIFO transfer must succeed exactly once"); return; }
        if (_CallbackOrder.Contains(InSourceItem))
        { FinishFailure("A source-FIFO transfer callback fired more than once"); return; }
        _CallbackOrder.Add(InSourceItem);

        if (InSourceItem == _Items[0])
        {
            FCk_Handle_Inventory B = _B;
            if (InTarget != B || _ReentrantTransferDispatched)
            { FinishFailure("First source request did not complete once into B"); return; }
            _ReentrantTransferDispatched = true;
            _Source.Request_TransferItem_ToDataOnly(
                FCk_Request_Inventory_TransferItem_ToDataOnly(_Items[2], _D),
                FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransfer"));
        }
        else if (InSourceItem == _Items[1])
        {
            FCk_Handle_Inventory C = _C;
            if (InTarget != C)
            { FinishFailure("Second source request did not complete into C"); return; }
        }
        else if (InSourceItem == _Items[2])
        {
            FCk_Handle_Inventory D = _D;
            if (InTarget != D)
            { FinishFailure("Reentrant source request did not complete into D"); return; }
        }

        if (_CallbackOrder.Num() == 3)
        { WaitUntil(n"Check_FinalState", n"OnFinalState"); }
    }

    UFUNCTION()
    private void Check_FinalState(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Source.Get_TotalUnits() == 0 && _B.Get_TotalUnits() == 1
            && _C.Get_TotalUnits() == 1 && _D.Get_TotalUnits() == 1);
    }

    UFUNCTION()
    private void OnFinalState(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_ReentrantTransferDispatched, "First callback submitted the third source request");
        Assert_Equals_Int(_CallbackOrder.Num(), 3, "All three source requests reported exactly once");
        Assert_True(_CallbackOrder[0] == _Items[0] && _CallbackOrder[1] == _Items[1]
                && _CallbackOrder[2] == _Items[2],
            "Initial source FIFO precedes the callback-created request");
        Assert_Equals_Int(_Source.Get_TotalUnits(), 0, "Source is empty after all FIFO transfers");
        Assert_Equals_Int(_B.Get_TotalUnits(), 1, "First request reached B");
        Assert_Equals_Int(_C.Get_TotalUnits(), 1, "Second request reached C");
        Assert_Equals_Int(_D.Get_TotalUnits(), 1, "Reentrant third request reached D");
        FinishSuccess();
    }
}
