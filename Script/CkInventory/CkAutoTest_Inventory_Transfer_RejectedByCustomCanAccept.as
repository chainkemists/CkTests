// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: TRANSFER REJECTED BY CUSTOM CAN-ACCEPT
//============================================================================
//
// Pins the rejection path of Request_TransferItem when the *target's*
// CustomCanAcceptItem delegate returns false. This is the transfer-side
// counterpart to CkAutoTest_Inventory_CustomCanAcceptItem (which only
// covers the AddItemByDefinition path) and is the only AutoTest that
// asserts source-stack rollback on a customs-rejected transfer.
//
// Procedure:
//   1. Create a permissive source inventory and a *rejecting* target
//      inventory (target's CustomCanAcceptItem returns false).
//   2. Seed the source with a Sword (Tags+Dimensions, no Stackable —
//      sidesteps the Stackable+Tags trait double-apply framework bug).
//   3. Request_TransferItem_ToDataOnly(SourceItem, TargetInventory).
//   4. Assert: result enum is `Failed_RejectedByCustomAcceptanceLogic`,
//      AmountTransferred == 0, source still holds the Sword, target is
//      empty, and the target's predicate WAS invoked (proves the
//      rejection path went through the user delegate, not a
//      short-circuit elsewhere).
//
// The strict source-rollback assertion here is what makes this test
// load-bearing for H2: the templated ExecuteTransfer<TSource, TTarget>
// rolls the source remove back when the target rejects the add. A
// regression that loses items in transit would be caught by the
// `source still has Sword` assertion below.
//============================================================================

class UCk_AutoTest_Inventory_Transfer_RejectedByCustomCanAccept : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _Target;
    private FCk_Handle_Item _SourceItem;
    private bool _SourceItemSeen = false;
    private bool _TargetPredicateInvoked = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_TransferReject_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto RejectingDelegate = FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(this, n"OnTargetCanAcceptItem");
        auto TargetParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_TransferReject_Target"),
            RejectingDelegate,
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_data_only::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto SwordDef = inv_gym_items::Sword();
        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(SwordDef, 1);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Source.Request_AddItemByDefinition(AddRequest,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
    }

    UFUNCTION()
    private void OnTargetCanAcceptItem(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        bool& OutCanAccept)
    {
        _TargetPredicateInvoked = true;
        OutCanAccept = false;
    }

    UFUNCTION()
    private void OnAddResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        if (_SourceItemSeen) { return; }

        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded ||
            InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Pre-transfer setup: failed to seed source inventory (result={InResult}, items={InItemsCreated.Num()})");
            return;
        }
        _SourceItemSeen = true;
        _SourceItem = InItemsCreated[0];

        auto Request = FCk_Request_Inventory_TransferItem_ToDataOnly(_SourceItem, _Target);
        _Source.Request_TransferItem_ToDataOnly(Request,
            FCk_Delegate_Inventory_OnOperationResult_Transfer(this, n"OnTransferResult"));
    }

    UFUNCTION()
    private void OnTransferResult(
        FCk_Handle_Inventory InSource,
        FCk_Handle_Item InSourceItem,
        FCk_Handle_Inventory InTarget,
        int InAmountTransferred,
        FCk_Handle_Item InTargetItem,
        ECk_Inventory_OperationResult_Transfer InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(_TargetPredicateInvoked,
            "Target's CustomCanAcceptItem predicate must be invoked during Request_TransferItem");
        Assert_True(InResult == ECk_Inventory_OperationResult_Transfer::Failed_RejectedByCustomAcceptanceLogic,
            f"When the target rejects via CustomCanAcceptItem, transfer result must be Failed_RejectedByCustomAcceptanceLogic (got {InResult})");
        Assert_Equals_Int(InAmountTransferred, 0,
            "AmountTransferred must be 0 when the target rejects the item");

        // Rollback contract: the source must still hold the original item after a customs-rejected transfer.
        Assert_Equals_Int(_Source.Get_NumItems(), 1,
            "Source inventory must roll back and still hold the original item after a rejected transfer");
        Assert_Equals_Int(_Target.Get_NumItems(), 0,
            "Target inventory must remain empty after rejecting the transfer");

        FinishSuccess();
    }
}

class ACk_AutoTest_Inventory_Transfer_RejectedByCustomCanAccept_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Inventory_Transfer_RejectedByCustomCanAccept;
    default _TimeoutSeconds = 4.0f;

    // The test asserts the rejection-with-rollback contract: target's CustomCanAcceptItem
    // returns false → AddItem fails internally → transfer rolls back the source remove.
    // The library correctly logs both the AddItem rejection and the rollback as Warnings
    // for any production caller; the test deliberately exercises this path. Suppress both
    // lines so the harness doesn't escalate them into a test failure. The library keeps
    // the Warning severity for everyone outside this test.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("Rejected by Custom Acceptance Logic");
        Out.Add("rolled back source remove");
        return Out;
    }
}
