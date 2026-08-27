// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: SPATIAL ADD-BY-DEFINITION NO-SPACE
//============================================================================
//
// Pins the rejection path of Request_AddItemByDefinition on a spatial
// inventory when no item from the request can be placed:
//
//   1. Build a 2x2 spatial inventory.
//   2. Request_AddItemByDefinition(Sword, Amount=1, ForceNewItem) - the
//      Sword footprint is 3x1 (Tags+Dimensions, no Stackable), which can
//      never fit in a 2-column / 2-row grid at any rotation.
//   3. Result delegate must report `Failed_NoSpaceAvailable`,
//      AmountAdded == 0, ItemsCreated empty, and the inventory remains
//      empty.
//
// Sword (Tags+Dimensions only - no Stackable) is used deliberately so this
// test sidesteps the Stackable+Tags trait double-apply framework bug
// documented in CkAutoTest_Inventory_DataOnly_AddItem.as. This negative
// path is the spatial counterpart to BoundedReject (DataOnly).
//============================================================================

class UCk_AutoTest_Inventory_Spatial_AddByDefinition_NoSpace : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Inventory_Spatial _Inventory;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SpatialAddByDefNoSpace"),
            FIntPoint(2, 2),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Inventory = utils_inventory_spatial::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Inventory.Request_AddItemByDefinition(Request,
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

        Assert_True(InResult == ECk_Inventory_OperationResult_AddByDefinition::Failed_NoSpaceAvailable,
            f"Adding a 3x1 Sword to a 2x2 spatial inventory must fail with Failed_NoSpaceAvailable (got {InResult})");
        Assert_Equals_Int(InAmountAdded, 0, "AmountAdded must be 0 when no item can be placed");
        Assert_Equals_Int(InItemsCreated.Num(), 0, "ItemsCreated must be empty when the add is rejected");
        Assert_Equals_Int(_Inventory.Get_NumItems(), 0,
            "Spatial inventory must remain empty after a no-space rejection");

        FinishSuccess();
    }
}
