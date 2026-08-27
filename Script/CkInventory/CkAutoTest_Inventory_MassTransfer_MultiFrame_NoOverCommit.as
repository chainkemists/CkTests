// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: MASS TRANSFER - MULTI-FRAME, NO OVER-COMMIT
//============================================================================
//
// The coherence + pacing guard. 6 separate 1-unit Potion stacks in the source, a
// BoundedByTotalUnits(4) candidate. Uses the DEFAULT MaxStepsPerFrame (1), so the
// 6-item batch spans 6 frames. Each transfer MERGES into the candidate's stack
// (PreferStacking), and a merge's stack-count write is a DEFERRED attribute modifier.
// The paced churn (one item / pass) folds that write before the next item resolves
// capacity, so the candidate stops exactly at its 4-unit bound:
//   coherent reads  => 4 placed, 2 failed, candidate TotalUnits == 4.
//   stale reads     => all 6 merge, candidate over-commits to 6.
//
// Also guards the default pump budget: this is the worst case (every item merges),
// and the gate requires the run log ZERO "High pump count" warnings. Raising the
// default would trip the warn here and fail the test.
//============================================================================

class UCk_AutoTest_Inventory_MassTransfer_MultiFrame_NoOverCommit : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _Candidate;
    private int32 _SeedsRemaining = 6;
    private bool  _Kicked = false;

    // These settles were hand-rolled retry loops bounded by a try counter that
    // FELL THROUGH into the assertions on exhaustion, so a hang reported as a
    // value mismatch rather than as a timeout. WaitUntil names the condition it
    // was waiting on and is bounded by the test timeout.

    UFUNCTION()
    private void Check_CandidateHasFourUnits(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Candidate.Get_TotalUnits() == 4);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MTMulti_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto CandParams = utils_inventory_data_only::Make_Params_BoundedByTotalUnits(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_MTMulti_Cand"), 4,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Candidate = utils_inventory_data_only::Add(LocalHandle, CandParams, ECk_Replication::DoesNotReplicate);

        // 6 separate 1-unit Potion entries (ForceNewItem keeps them un-merged in the source).
        for (int i = 0; i < 6; i++)
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
        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded)
        {
            FinishFailure(f"Setup: seeding a Potion failed (result={InResult})");
            return;
        }

        _SeedsRemaining -= 1;
        if (_SeedsRemaining > 0 || _Kicked) { return; }
        _Kicked = true;

        if (_Source.Get_NumItems() != 6)
        {
            FinishFailure(f"Setup: expected 6 separate Potion entries, got {_Source.Get_NumItems()}");
            return;
        }

        auto Candidates = TArray<FCk_Handle_Inventory>();
        Candidates.Add(_Candidate);

        auto Sources = TArray<FCk_Handle_Inventory>();
        Sources.Add(_Source);

        auto Target  = FCk_BestTransferTargetParams(Candidates);
        auto Request = FCk_Request_Inventory_MassTransfer(Sources, Target);
        // Intentionally NOT overriding MaxStepsPerFrame - exercise the default (1) so this test
        // guards both coherence AND the default pump budget (6 items > 1 => spans 6 frames).

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
            f"4 of 6 units into units(4) -> Success_Partial (got {InResult})");
        Assert_Equals_Int(InUnitsMoved, 4, "Exactly the bound (4 units) should move");
        Assert_Equals_Int(InItemsFailed, 2, "The 2 over-bound items should be reported failed");

        // The merged stack-count write is deferred - settle before reading TotalUnits.
        WaitUntil(n"Check_CandidateHasFourUnits", n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }


        Assert_Equals_Int(_Candidate.Get_TotalUnits(), 4,
            "Candidate must sit at its 4-unit bound - never over-commit past it");
        Assert_Equals_Int(_Source.Get_NumItems(), 2, "Source keeps the 2 unplaceable Potions");

        FinishSuccess();
    }
}
