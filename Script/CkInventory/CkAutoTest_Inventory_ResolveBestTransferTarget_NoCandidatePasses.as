// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: RESOLVE BEST TRANSFER TARGET — NO PASSES
//============================================================================
//
// Pins the documented contract from CkInventory_Utils.h:
//   ResolveBestTransferTarget "Returns invalid handle if no candidate
//   qualifies." A candidate fails to qualify when it is either invalid or
//   fails Get_CanAcceptItem (often via the inventory's CustomCanAcceptItem
//   delegate).
//
// Setup: build a "Source" inventory holding a Sword item. Build two
// "Candidate" inventories whose CustomCanAcceptItem delegates always
// return false. Call ResolveBestTransferTarget(Sword, {Candidates}) and
// assert the returned inventory handle is invalid.
//
// Uses Sword (Dimensions+Tags, no Stackable) to keep this off the
// Stackable framework warning path.
//============================================================================

class UCk_AutoTest_Inventory_ResolveBestTransferTarget_NoCandidatePasses : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Source;
    private FCk_Handle_Inventory_DataOnly _CandidateA;
    private FCk_Handle_Inventory_DataOnly _CandidateB;
    private FCk_Handle_Item _Sword;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // Source inventory has no CustomCanAcceptItem rejection — it'll
        // accept the Sword we add to it.
        auto SourceParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_RBT_Source"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_data_only::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        // Two candidate inventories whose CustomCanAcceptItem rejects every
        // item. ResolveBestTransferTarget must filter both out and return
        // an invalid handle.
        auto RejectDelegate = FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(this, n"AlwaysReject");

        auto CandAParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_RBT_CandA"),
            RejectDelegate,
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _CandidateA = utils_inventory_data_only::Add(LocalHandle, CandAParams, ECk_Replication::DoesNotReplicate);

        auto CandBParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_RBT_CandB"),
            RejectDelegate,
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _CandidateB = utils_inventory_data_only::Add(LocalHandle, CandBParams, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Source.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
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
    private void OnAddResult(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }
        if (InItemsCreated.Num() == 0)
        {
            FinishFailure("Setup: failed to add Sword to source inventory");
            return;
        }

        _Sword = InItemsCreated[0];

        auto Candidates = TArray<FCk_Handle_Inventory>();
        Candidates.Add(_CandidateA);
        Candidates.Add(_CandidateB);

        auto Params = FCk_BestTransferTargetParams(Candidates);
        auto Resolved = utils_item_resolution::ResolveBestTransferTarget(_Sword, Params);

        Assert_True(ck::Is_NOT_Valid(Resolved),
            "ResolveBestTransferTarget must return an invalid handle when every candidate fails Get_CanAcceptItem");

        FinishSuccess();
    }
}
