// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: MASS TRANSFER - NO CANDIDATE ACCEPTS
//============================================================================
//
// Items exist but every candidate categorically rejects them (CustomCanAcceptItem
// always false). No unit can be placed anywhere -> Failed_NoCandidateAccepts,
// UnitsMoved == 0, source unchanged. Distinguishes "nothing could be placed" from
// "nothing to transfer" (the source is non-empty here).
//============================================================================

class UCk_AutoTest_Inventory_MassTransfer_NoCandidateAccepts : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _Candidate;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MTNoAccept_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto RejectDelegate = FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(this, n"AlwaysReject");
        auto CandParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MTNoAccept_Cand"),
            RejectDelegate,
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Candidate = utils_inventory_data_only::Add(LocalHandle, CandParams, ECk_Replication::DoesNotReplicate);

        auto Add = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Key(), 3);
        _Source.Request_AddItemByDefinition(Add,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSeeded"));
    }

    UFUNCTION()
    private void AlwaysReject(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        bool& OutCanAccept)
    {
        OutCanAccept = false;
    }

    UFUNCTION()
    private void OnSeeded(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded ||
            _Source.Get_NumItems() != 3)
        {
            FinishFailure(f"Setup: expected 3 source items (result={InResult}, num={_Source.Get_NumItems()})");
            return;
        }

        auto Candidates = TArray<FCk_Handle_Inventory>();
        Candidates.Add(_Candidate);

        auto Sources = TArray<FCk_Handle_Inventory>();
        Sources.Add(_Source);

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

        Assert_True(InResult == ECk_Inventory_MassTransfer_Result::Failed_NoCandidateAccepts,
            f"Items present but no candidate accepts -> Failed_NoCandidateAccepts (got {InResult})");
        Assert_Equals_Int(InUnitsMoved, 0, "Nothing should move");
        Assert_Equals_Int(_Source.Get_NumItems(), 3, "Source should be unchanged");
        Assert_Equals_Int(_Candidate.Get_NumItems(), 0, "Candidate should stay empty");

        FinishSuccess();
    }
}
