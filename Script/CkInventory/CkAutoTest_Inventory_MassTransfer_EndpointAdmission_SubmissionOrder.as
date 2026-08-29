// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: MASS TRANSFER SHARES ENDPOINT ADMISSION
//============================================================================
//
// The ordinary A -> B transfer and the paced MassTransfer B -> C share B.
// The mass transfer is submitted first and must vacate B before A -> B runs.
// This protects the requirement that MassTransfer steps use the same
// all-participant arbitration as ordinary transfer requests.
//============================================================================

class UCk_AutoTest_Inventory_MassTransfer_EndpointAdmission_SubmissionOrder : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Inventory_DataOnly _A;
    private FCk_Handle_Inventory_DataOnly _B;
    private FCk_Handle_Inventory_DataOnly _C;
    private FCk_Handle_Item _AItem;
    private int32 _SeedCallbacks = 0;
    private bool _Dispatched = false;
    private bool _MassCompleted = false;
    private bool _TransferCompleted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Keep endpoint creation deterministic so repeated runs use the same fixture topology.
        auto CParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MassEndpointAdmission_C"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _C = utils_inventory_data_only::Add(InHandle, CParams, ECk_Replication::DoesNotReplicate);

        auto BParams = utils_inventory_data_only::Make_Params_BoundedByTotalUnits(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MassEndpointAdmission_B"), 1,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _B = utils_inventory_data_only::Add(InHandle, BParams, ECk_Replication::DoesNotReplicate);

        auto AParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MassEndpointAdmission_A"),
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
        { FinishFailure("Setup: expected each mass endpoint-admission seed to add one item"); return; }
        FCk_Handle_Inventory A = _A;
        FCk_Handle_Inventory B = _B;
        if (InInventory == A) { _AItem = InItemsCreated[0]; }
        else if (InInventory != B)
        { FinishFailure("Setup: seed callback named an unexpected inventory"); return; }

        _SeedCallbacks += 1;
        if (_SeedCallbacks != 2 || _Dispatched) { return; }
        _Dispatched = true;

        auto Sources = TArray<FCk_Handle_Inventory>();
        Sources.Add(_B);
        auto Candidates = TArray<FCk_Handle_Inventory>();
        Candidates.Add(_C);
        auto MassRequest = FCk_Request_Inventory_MassTransfer(
            Sources, FCk_BestTransferTargetParams(Candidates));
        utils_inventory::Request_MassTransfer(_B, MassRequest,
            FCk_Delegate_Inventory_MassTransfer_OnComplete(this, n"OnMassComplete"));

        _A.Request_TransferItem_ToDataOnly(
            FCk_Request_Inventory_TransferItem_ToDataOnly(_AItem, _B),
            FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransferComplete"));
    }

    UFUNCTION()
    private void OnMassComplete(
        FCk_Handle InOperation,
        ECk_Inventory_MassTransfer_Result InResult,
        int InUnitsMoved,
        int InItemsFullyMoved,
        int InItemsFailed)
    {
        if (IsFinished()) { return; }
        if (_MassCompleted)
        { FinishFailure("Mass transfer completion fired more than once"); return; }
        Assert_True(InResult == ECk_Inventory_MassTransfer_Result::Success,
            f"The first-submitted mass transfer must complete successfully (got {InResult})");
        Assert_Equals_Int(InUnitsMoved, 1, "Mass transfer vacated B by exactly one unit");
        Assert_Equals_Int(InItemsFullyMoved, 1, "Mass transfer fully moved B's one item");
        Assert_Equals_Int(InItemsFailed, 0, "Mass transfer had no failed items");
        if (IsFinished()) { return; }
        _MassCompleted = true;
        TryFinish();
    }

    UFUNCTION()
    private void OnTransferComplete(
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
        if (InSource != A || InSourceItem != _AItem || InTarget != B)
        { FinishFailure("Ordinary transfer callback did not identify A -> B"); return; }
        if (InResult != ECk_Inventory_OperationResult_Transfer::Success
            || InAmountTransferred != 1 || ck::Is_NOT_Valid(InTargetItem))
        { FinishFailure("Ordinary transfer must succeed after the mass transfer vacates B"); return; }
        if (_TransferCompleted)
        { FinishFailure("Ordinary transfer callback fired more than once"); return; }
        _TransferCompleted = true;
        TryFinish();
    }

    private void TryFinish()
    {
        if (_MassCompleted && _TransferCompleted)
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
        Assert_True(_MassCompleted, "Mass transfer completed exactly once before final state inspection");
        Assert_True(_TransferCompleted, "Ordinary transfer completed exactly once before final state inspection");
        Assert_Equals_Int(_A.Get_TotalUnits(), 0, "A is empty after its ordinary transfer");
        Assert_Equals_Int(_B.Get_TotalUnits(), 1, "B was vacated by mass transfer then refilled");
        Assert_Equals_Int(_C.Get_TotalUnits(), 1, "C received B's mass-transferred unit");
        FinishSuccess();
    }
}
