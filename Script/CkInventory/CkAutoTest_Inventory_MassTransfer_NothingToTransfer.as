// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: MASS TRANSFER — NOTHING TO TRANSFER
//============================================================================
//
// A valid-but-empty source with an ample candidate. The gather produces zero
// items, so the op resolves to Failed_NothingToTransfer (NOT a synchronous
// Failed_NotEnqueued — an empty-but-valid source is observed on the async
// channel). Nothing moves anywhere.
//============================================================================

class UCk_AutoTest_Inventory_MassTransfer_NothingToTransfer : UCk_AutoTest_Base
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
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MTNothing_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto CandParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MTNothing_Cand"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Candidate = utils_inventory_data_only::Add(LocalHandle, CandParams, ECk_Replication::DoesNotReplicate);

        auto Candidates = TArray<FCk_Handle_Inventory>();
        Candidates.Add(_Candidate);

        auto Sources = TArray<FCk_Handle_Inventory>();
        Sources.Add(_Source);

        auto Target  = FCk_BestTransferTargetParams(Candidates);
        auto Request = FCk_Request_Inventory_MassTransfer(Sources, Target);

        utils_inventory::Request_MassTransfer(LocalHandle, Request,
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

        Assert_True(InResult == ECk_Inventory_MassTransfer_Result::Failed_NothingToTransfer,
            f"Empty source -> Failed_NothingToTransfer (got {InResult})");
        Assert_Equals_Int(InUnitsMoved, 0, "Nothing should move");
        Assert_Equals_Int(_Candidate.Get_NumItems(), 0, "Candidate should stay empty");

        FinishSuccess();
    }
}
