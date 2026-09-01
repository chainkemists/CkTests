// Language=angelscript

//============================================================================
// CK INVENTORY - AUTOMATION TEST: REMOVE RELEASES THE LIFETIME CLAIM
//============================================================================
//
// Add and Remove must be symmetric about entity lifetime. Add calls
// Request_TransferLifetimeOwner to make the item a lifetime dependent of the
// inventory entity; Remove has to give that claim back.
//
// Without the release a Remove is only half a removal: the record entry and the
// ParentInventory pointer clear, so the item vanishes from Get_Items and
// Get_NumItems, but the entity stays ALIVE as a lifetime child of the container
// it just left. Those orphans are invisible to every inventory query, ride every
// snapshot capture as that container's children, and are swept by that
// container's destroy cascade even though they are no longer in it. Any caller
// that removes without immediately re-adding accumulates one per removal, for
// the lifetime of the container.
//
// Steps:
//   1. Add a Potion to a bounded(5) DataOnly inventory.
//   2. On the add result, pin that the Add DID claim the item (owner == inventory).
//   3. Request_RemoveItem.
//   4. On the remove result, pin that the claim is gone: the item is still alive,
//      is no longer owned by the inventory, and sits on the inventory's context
//      owner - where UCk_Utils_Item_UE::Create parents a fresh item.
//============================================================================

class UCk_AutoTest_Inventory_DataOnly_RemoveReleasesLifetimeClaim : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory_DataOnly _Inventory;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = utils_inventory_data_only::Make_Params_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Bounded"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory_data_only::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Potion(), 1);
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
            FinishFailure("Add did not produce any item to remove");
            return;
        }

        auto Item = InItemsCreated[0];

        // The premise of the whole test: if Add ever stops claiming the item, the
        // release below would trivially "pass" while proving nothing.
        const FCk_Handle InventoryEntity = _Inventory;
        Assert_True(ck::OwnerEntity(Item) == InventoryEntity,
            "PRECONDITION: Add should make the item a lifetime dependent of the inventory entity");

        _Inventory.Request_RemoveItem(FCk_Request_Inventory_RemoveItem(Item),
            FCk_Delegate_Inventory_OnOperationResult_Remove(this, n"OnRemoveResult"));
    }

    UFUNCTION()
    private void OnRemoveResult(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        ECk_Inventory_OperationResult_Remove InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Inventory_OperationResult_Remove::Success,
            f"Remove result should be Success (got {InResult})");

        // Remove hands the item back to the caller; it must not destroy it. A
        // transfer is remove-then-add, so a destroying Remove would break every transfer.
        Assert_True(ck::IsValid(InItem),
            "Remove should leave the item alive for the caller to re-home or destroy");

        const FCk_Handle InventoryEntity = _Inventory;
        const FCk_Handle NewOwner = ck::OwnerEntity(InItem);

        Assert_True((NewOwner == InventoryEntity) == false,
            "A removed item must NOT stay a lifetime dependent of the inventory it left");

        Assert_True(NewOwner == InventoryEntity.Get_ContextOwner(),
            "A removed item should be released to the inventory's context owner");

        FinishSuccess();
    }
}
