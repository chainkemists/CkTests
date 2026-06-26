// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: SPATIAL RELOCATE ITEM — SUCCESS
//============================================================================
//
// Pins the happy-path Request_RelocateItem contract on a spatial inventory:
//   1. Build a 4x4 spatial inventory.
//   2. Add a Shield (1x1, bare trait) via Request_AddItemByDefinition. Item
//      auto-places at some coordinate; capture its starting placement.
//   3. Choose a target coordinate that is empty (Shield is the only item).
//   4. Request_RelocateItem(inventory, FCk_Request_Inventory_Spatial_RelocateItem
//      (Shield, FCk_SpatialPlacement(TargetCoord, None)), delegate).
//   5. On result: ECk_Inventory_OperationResult_Relocate::Success.
//      Get_ItemPlacementCoordinate(Shield) reflects the new coordinate.
//
// Uses Shield (Dimensions=1x1, Tags-only) to sidestep the Stackable framework
// warning that affects Potion/Arrow-based inventory tests.
//============================================================================

class UCk_AutoTest_Inventory_Spatial_RelocateItem_Success : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_Spatial _Inventory;
    private FCk_Handle_Item _Shield;
    private FIntPoint _TargetCoord;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_RelocateSuccess"),
            FIntPoint(4, 4),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_spatial::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Shield(), 1);
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
        if (InItemsCreated.Num() == 0)
        {
            FinishFailure("Setup: failed to add Shield to spatial inventory");
            return;
        }

        _Shield = InItemsCreated[0];
        auto StartCoord = utils_inventory_spatial::Get_ItemPlacementCoordinate(_Inventory, _Shield);

        // Pick a target coordinate guaranteed different from start and
        // within the 4x4 grid. Shield is 1x1 so any in-bounds vacant cell
        // works.
        _TargetCoord = FIntPoint(3, 3);
        if (StartCoord == _TargetCoord)
        {
            _TargetCoord = FIntPoint(0, 0);
        }

        auto NewPlacement = FCk_SpatialPlacement();
        NewPlacement.Set_Coordinate(_TargetCoord);
        NewPlacement.Set_Rotation(ECk_CardinalRotation::None);
        auto RelocateRequest = FCk_Request_Inventory_Spatial_RelocateItem(_Shield, NewPlacement);
        _Inventory.Request_RelocateItem(RelocateRequest,
            FCk_Delegate_Inventory_OnOperationResult_Relocate(this, n"OnRelocateResult"));
    }

    UFUNCTION()
    private void OnRelocateResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        FIntPoint InNewCoord,
        ECk_Inventory_OperationResult_Relocate InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Relocate::Success,
            f"Relocate to a vacant cell should succeed (got {InResult})");
        Assert_True(InNewCoord == _TargetCoord,
            f"OnRelocateResult payload should carry the target coordinate {_TargetCoord} (got {InNewCoord})");

        auto NowCoord = utils_inventory_spatial::Get_ItemPlacementCoordinate(_Inventory, _Shield);
        Assert_True(NowCoord == _TargetCoord,
            f"Get_ItemPlacementCoordinate should report the relocated coordinate {_TargetCoord} (got {NowCoord})");

        FinishSuccess();
    }
}
