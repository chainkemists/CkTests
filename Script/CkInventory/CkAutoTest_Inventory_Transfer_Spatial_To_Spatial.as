// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: TRANSFER SPATIAL -> SPATIAL
//============================================================================
//
// Exercises the Spatial -> Spatial template instantiation of
// ck::inventory_helpers::ExecuteTransfer<TSource, TTarget>. Existing tests
// cover Spatial -> DataOnly (BaseHandleFacade) and DataOnly transfer paths;
// the Spatial -> Spatial symmetric path was not previously pinned.
//
// Procedure:
//   1. Create two 3x3 Spatial inventories (Source + Target) on the same
//      owner entity.
//   2. Seed Source with one Sword (3x1, bare-trait Dimensions+Tags).
//   3. Build FCk_Request_Inventory_TransferItem_ToSpatial(Source item -> Target).
//   4. Issue utils_inventory::Request_TransferItem_ToSpatial on the Source.
//   5. On result: Success (or Success_Partial), Source.NumItems == 0,
//      Target.NumItems == 1.
//
// Sword sidesteps the Stackable framework warning bug.
//============================================================================

class UCk_AutoTest_Inventory_Transfer_Spatial_To_Spatial : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Inventory_Spatial _Source;
    private FCk_Handle_Inventory_Spatial _Target;
    private bool _SourceItemSeen = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_S2S_Source"),
            FIntPoint(3, 3),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_spatial::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto TargetParams = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_S2S_Target"),
            FIntPoint(3, 3),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_spatial::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Source.Request_AddItemByDefinition(AddRequest,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
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
            FinishFailure(f"Pre-transfer setup: failed to seed source spatial inventory (result={InResult})");
            return;
        }
        _SourceItemSeen = true;

        auto SourceItem = InItemsCreated[0];
        auto Request = FCk_Request_Inventory_TransferItem_ToSpatial(SourceItem, _Target);

        FCk_Handle_Inventory SourceAsBase = _Source;
        utils_inventory::Request_TransferItem_ToSpatial(SourceAsBase, Request,
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

        auto IsSuccess =
            InResult == ECk_Inventory_OperationResult_Transfer::Success ||
            InResult == ECk_Inventory_OperationResult_Transfer::Success_Partial;
        Assert_True(IsSuccess,
            f"Spatial->Spatial transfer should succeed (got {InResult})");
        Assert_True(InAmountTransferred >= 1,
            f"AmountTransferred should be >= 1 (got {InAmountTransferred})");

        Assert_Equals_Int(_Source.Get_NumItems(), 0,
            "Source Spatial inventory should hold 0 items after Spatial->Spatial transfer");
        Assert_Equals_Int(_Target.Get_NumItems(), 1,
            "Target Spatial inventory should hold 1 item after Spatial->Spatial transfer");

        FinishSuccess();
    }
}
