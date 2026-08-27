// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: TRANSFER VIA BASE-HANDLE FACADE
//============================================================================
//
// Pins the Tier C base-handle facade introduced by the inventory refactor:
// FCk_Handle_Inventory (the *base* handle) now exposes Request_TransferItem_*
// directly via mixin propagation, with a single runtime shape-branch at the
// public Utils boundary that dispatches to the correct typed Utils.
//
// This test exercises the Spatial->DataOnly direction *via the base handle*:
//   1. Create a Spatial(3x3) source and a DataOnly(5) target on the test entity.
//      (3x3 large enough for the 3x1 Sword - see CkAutoTest_Inventory_SpatialPlacementRejection
//      which uses the same staging dimensions.)
//   2. Seed the source with one Sword.
//   3. Transfer via the base handle:
//        utils_inventory::Request_TransferItem_ToDataOnly(SourceAsBase, ...)
//      where SourceAsBase is implicitly converted from FCk_Handle_Inventory_Spatial
//      to FCk_Handle_Inventory (this is the call shape the brief asked for
//      callers stop having to know the source's shape).
//   4. Assert Success (or Success_Partial), source.NumItems == 0,
//      target.NumItems == 1.
//
// If the Utils-boundary shape-branch is broken (e.g. dispatches to the wrong
// typed Utils, or doesn't dispatch at all), no signal fires and the test
// times out. If the branch dispatches but to the wrong typed handler, the
// transfer outcome won't match.
//============================================================================

class UCk_AutoTest_Inventory_TransferItem_BaseHandleFacade : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Inventory_Spatial _Source;
    private FCk_Handle_Inventory_DataOnly _Target;
    private bool _SourceItemSeen = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SourceParams = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_BaseFacade_Source"),
            FIntPoint(3, 3),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Source = utils_inventory_spatial::Add(LocalHandle, SourceParams, ECk_Replication::DoesNotReplicate);

        auto TargetParams = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_BaseFacade_Target"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_data_only::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto SwordDef = inv_gym_items::Sword();
        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(SwordDef, 1);
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
            FinishFailure(f"Pre-transfer setup: failed to seed source spatial inventory (result={InResult}, items={InItemsCreated.Num()})");
            return;
        }
        _SourceItemSeen = true;

        auto SourceItem = InItemsCreated[0];
        auto Request = FCk_Request_Inventory_TransferItem_ToDataOnly(SourceItem, _Target);

        // KEY ASSERTION: call via the *base* handle. The Spatial source implicitly
        // converts to FCk_Handle_Inventory; the base Utils shape-branches and
        // delegates to the typed Spatial Utils internally.
        FCk_Handle_Inventory SourceAsBase = _Source;
        utils_inventory::Request_TransferItem_ToDataOnly(SourceAsBase, Request,
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
            f"Base-handle transfer Spatial->DataOnly should succeed (got {InResult})");
        Assert_True(InAmountTransferred >= 1,
            f"AmountTransferred should be >= 1 (got {InAmountTransferred})");

        Assert_Equals_Int(_Source.Get_NumItems(), 0,
            "Source spatial inventory should hold 0 items after successful base-handle transfer");
        Assert_Equals_Int(_Target.Get_NumItems(), 1,
            "Target dataonly inventory should hold 1 item after successful base-handle transfer");

        FinishSuccess();
    }
}
