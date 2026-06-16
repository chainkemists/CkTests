// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: MASS TRANSFER — PARTIAL
//============================================================================
//
// 5 items in one source, a single candidate bounded to 3 entries. The churn
// places 3 and the bounded candidate rejects the remaining 2 -> Success_Partial,
// UnitsMoved == 3, ItemsFailed == 2, candidate sits exactly at its entry bound,
// source keeps the 2 it could not place (no over-commit past the candidate bound).
//============================================================================

class UCk_AutoTest_Inventory_MassTransfer_Partial : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _Candidate;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MTPartial_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto CandParams = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MTPartial_Cand"), 3,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Candidate = utils_inventory_data_only::Add(LocalHandle, CandParams, ECk_Replication::DoesNotReplicate);

        auto Add = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Key(), 5);
        _Source.Request_AddItemByDefinition(Add,
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
        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded ||
            _Source.Get_NumItems() != 5)
        {
            FinishFailure(f"Setup: expected 5 source items (result={InResult}, num={_Source.Get_NumItems()})");
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

        Assert_True(InResult == ECk_Inventory_MassTransfer_Result::Success_Partial,
            f"3 of 5 placed into a bound(3) candidate -> Success_Partial (got {InResult})");
        Assert_Equals_Int(InUnitsMoved, 3, "Exactly 3 units (the candidate's room) should move");
        Assert_Equals_Int(InItemsFailed, 2, "The 2 unplaceable items should be reported failed");
        Assert_Equals_Int(_Candidate.Get_NumItems(), 3, "Candidate sits at its 3-entry bound");
        Assert_Equals_Int(_Source.Get_NumItems(), 2, "Source keeps the 2 it could not place");

        FinishSuccess();
    }
}
