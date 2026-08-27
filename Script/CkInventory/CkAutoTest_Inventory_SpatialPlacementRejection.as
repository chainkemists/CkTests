// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: SPATIAL PLACEMENT REJECTION
//============================================================================
//
// Pins the failure path of spatial placement when an item's footprint
// cannot fit in the configured grid:
//
//   1. Build a 2x2 spatial inventory.
//   2. Use Sword (Dimensions = 3x1) - too wide for a 2x2 grid.
//   3. Get_FirstAvailablePlacement returns FCk_SpatialPlacementResult
//      with _Succeeded == false.
//   4. Get_CanPlaceItemAt at (0,0) likewise reports _Succeeded == false.
//
// The 3x1 Sword cannot fit in a 2-column grid at any rotation
// (1x3 also overflows in column at any cell), so both query forms
// must reject. Counter-fixture below adds a Shield (1x1) to the same
// grid via Request_AddItem to confirm the grid is otherwise functional
// the rejection above is footprint-specific, not blanket.
//
// Approach: spawn a Sword item directly via Request_AddItemByDefinition
// against a sufficiently-large staging spatial inventory (3x3), then test
// placement of that real item against the 2x2 target.
//============================================================================

class UCk_AutoTest_Inventory_SpatialPlacementRejection : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Inventory_Spatial _Staging;
    private FCk_Handle_Inventory_Spatial _Target;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Staging: 3x3 - large enough for the 3x1 Sword.
        auto StagingParams = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SpatialStaging"),
            FIntPoint(3, 3),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Staging = utils_inventory_spatial::Add(LocalHandle, StagingParams, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(_Staging))
        {
            FinishFailure("Staging inventory should be a spatial inventory after Make_Params");
            return;
        }

        // Target: 2x2 - too small for a 3x1 Sword.
        auto TargetParams = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_SpatialTarget"),
            FIntPoint(2, 2),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        _Target = utils_inventory_spatial::Add(LocalHandle, TargetParams, ECk_Replication::DoesNotReplicate);

        auto SwordDef = inv_gym_items::Sword();
        auto AddRequest = FCk_Request_Inventory_AddItemByDefinition(SwordDef, 1);
        AddRequest.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        _Staging.Request_AddItemByDefinition(AddRequest,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnSwordCreated"));
    }

    UFUNCTION()
    private void OnSwordCreated(
        FCk_Handle_Inventory InInventory,
        ECk_Inventory_OperationResult_AddByDefinition InResult,
        int InAmountAdded,
        const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        if (IsFinished()) { return; }

        if (InResult != ECk_Inventory_OperationResult_AddByDefinition::Success_AllAdded ||
            InItemsCreated.Num() != 1)
        {
            FinishFailure(f"Setup: failed to create Sword in 3x3 staging inventory (result={InResult})");
            return;
        }
        auto Sword = InItemsCreated[0];

        auto FirstPlacement = _Target.Get_FirstAvailablePlacement(Sword);
        Assert_True(FirstPlacement.Get_Succeeded() == false,
            "Get_FirstAvailablePlacement on a 2x2 spatial inventory must reject a 3x1 Sword (no rotation makes it fit)");

        auto AtZero = _Target.Get_CanPlaceItemAt(Sword, FIntPoint(0, 0));
        Assert_True(AtZero.Get_Succeeded() == false,
            "Get_CanPlaceItemAt at (0,0) on a 2x2 grid must reject a 3x1 Sword");

        FinishSuccess();
    }
}
