// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: ENDPOINT ADMISSION PRESERVES SUBMISSION ORDER
//============================================================================
//
// B starts full. B -> C is submitted before A -> B, so the first transfer must
// vacate B before the second can complete. This characterizes the expected
// three-inventory endpoint behavior and protects the coordinator's source/target
// participant admission contract.
//============================================================================

class UCk_AutoTest_Inventory_Transfer_EndpointAdmission_SubmissionOrder : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Inventory_DataOnly _A;
    private FCk_Handle_Inventory_DataOnly _B;
    private FCk_Handle_Inventory_DataOnly _C;
    private FCk_Handle_Item _AItem;
    private FCk_Handle_Item _BItem;
    private int32 _SeedCallbacks = 0;
    private int32 _TransferCallbacks = 0;
    private bool _ACompleted = false;
    private bool _BCompleted = false;
    private bool _Dispatched = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Keep endpoint creation deterministic so repeated runs use the same fixture topology.
        auto CParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_EndpointAdmission_C"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _C = utils_inventory_data_only::Add(InHandle, CParams, ECk_Replication::DoesNotReplicate);

        auto BParams = utils_inventory_data_only::Make_Params_BoundedByTotalUnits(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_EndpointAdmission_B"), 1,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _B = utils_inventory_data_only::Add(InHandle, BParams, ECk_Replication::DoesNotReplicate);

        auto AParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_EndpointAdmission_A"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _A = utils_inventory_data_only::Add(InHandle, AParams, ECk_Replication::DoesNotReplicate);

        auto BAdd = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
        BAdd.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _B.Request_AddItemByDefinition(BAdd,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeeded"));

        auto AAdd = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        AAdd.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _A.Request_AddItemByDefinition(AAdd,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeeded"));
    }

    UFUNCTION()
    private void OnSeeded(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded
            || InAmountAdded != 1 || InItemsCreated.Num() != 1)
        { FinishFailure("Setup: expected each endpoint-admission seed to add one item"); return; }

        FCk_Handle_Inventory A = _A;
        FCk_Handle_Inventory B = _B;
        if (InInventory == A) { _AItem = InItemsCreated[0]; }
        else if (InInventory == B) { _BItem = InItemsCreated[0]; }
        else { FinishFailure("Setup: seed callback named an unexpected inventory"); return; }

        _SeedCallbacks += 1;
        if (_SeedCallbacks != 2 || _Dispatched) { return; }
        _Dispatched = true;

        _B.Request_TransferItem_ToDataOnly(
            FCk_Request_Inventory_TransferItem_ToDataOnly(_BItem, _C),
            FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransfer"));
        _A.Request_TransferItem_ToDataOnly(
            FCk_Request_Inventory_TransferItem_ToDataOnly(_AItem, _B),
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
        FCk_Handle_Inventory A = _A;
        FCk_Handle_Inventory B = _B;
        FCk_Handle_Inventory C = _C;
        const bool IsOutgoing = InSource == B && InSourceItem == _BItem && InTarget == C;
        const bool IsIncoming = InSource == A && InSourceItem == _AItem && InTarget == B;
        if (IsOutgoing == false && IsIncoming == false)
        { FinishFailure("Transfer callback did not identify one of the submitted endpoint operations"); return; }
        if ((IsOutgoing && _BCompleted) || (IsIncoming && _ACompleted))
        { FinishFailure("An endpoint-sharing transfer callback fired more than once"); return; }
        if (InResult != ECk_Inventory_OperationResult_Transfer::Success
            || InAmountTransferred != 1 || ck::Is_NOT_Valid(InTargetItem))
        { FinishFailure("Both endpoint-sharing transfers must succeed after ordered admission"); return; }

        if (IsOutgoing) { _BCompleted = true; }
        else { _ACompleted = true; }
        _TransferCallbacks += 1;
        if (_TransferCallbacks == 2)
        { WaitUntil(n"Check_FinalState", n"OnFinalState"); }
    }

    UFUNCTION()
    private void Check_FinalState(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_A.Get_TotalUnits() == 0 && _B.Get_TotalUnits() == 1 && _C.Get_TotalUnits() == 1);
    }

    UFUNCTION()
    private void OnFinalState(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_Equals_Int(_TransferCallbacks, 2, "Both submitted endpoint-sharing transfers reported exactly once");
        Assert_Equals_Int(_A.Get_TotalUnits(), 0, "A is empty after its transfer to B");
        Assert_Equals_Int(_B.Get_TotalUnits(), 1, "B was vacated then refilled without exceeding its bound");
        Assert_Equals_Int(_C.Get_TotalUnits(), 1, "C received B's originally held unit");
        FinishSuccess();
    }
}
