// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: TAGS TRAIT — REMOVE TAG
//============================================================================
//
// Verifies Request_RemoveTag strips a definition-baked tag from an item:
//   1. Add a Sword (Item.Weapon + Item.Melee from definition).
//   2. Confirm Item.Weapon is present initially.
//   3. Bind OnTagsChanged.
//   4. Request_RemoveTag(Item.Weapon).
//   5. OnTagsChanged fires.
//   6. Get_Tags() no longer contains Item.Weapon (Item.Melee unchanged).
//
// NOTE: This test passes cleanly. The Sword item def carries Tags +
// Dimensions but NOT Stackable, so it sidesteps the Stackable-specific
// double-application warning that affects the DataOnly_* and
// StackableTrait_* tests (see CkAutoTest_Inventory_DataOnly_AddItem.as
// for the canonical framework-bug explanation).
//============================================================================

class UCk_AutoTest_Inventory_TagsTrait_RemoveTag : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory _Inventory;
    private FCk_Handle_Item _Sword;
    private FGameplayTag _WeaponTag;
    private FGameplayTag _MeleeTag;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _WeaponTag = utils_gameplay_tag::ResolveGameplayTag(n"Item.Weapon");
        _MeleeTag  = utils_gameplay_tag::ResolveGameplayTag(n"Item.Melee");

        auto Params = utils_inventory::Make_InventoryParams_DataOnly(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.AutoTest_Tags"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        _Inventory = utils_inventory::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);

        auto Request = FCk_Request_Inventory_AddItemByDefinition(inv_gym_items::Sword(), 1);
        utils_inventory::Request_AddItemByDefinition(
            _Inventory,
            Request,
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
            FinishFailure("Add did not produce a Sword item");
            return;
        }

        _Sword = InItemsCreated[0];

        auto InitialTags = utils_item_trait_tags::Get_Tags(_Sword);
        Assert_True(InitialTags.HasTagExact(_WeaponTag),
            "Freshly-added Sword should carry Item.Weapon from its definition");

        utils_item_trait_tags::BindTo_OnTagsChanged(
            _Sword,
            FCk_Delegate_ItemTags_OnTagsChanged(this, n"OnTagsChanged"));

        utils_item_trait_tags::Request_RemoveTag(_Sword, _WeaponTag);
    }

    UFUNCTION()
    private void OnTagsChanged(
        FCk_Handle_Item InItem,
        FCk_Payload_Item_OnTagsChanged InPayload)
    {
        if (IsFinished()) { return; }

        auto Tags = utils_item_trait_tags::Get_Tags(_Sword);
        Assert_True(!Tags.HasTagExact(_WeaponTag),
            "Tags should no longer contain Item.Weapon after Request_RemoveTag");
        Assert_True(Tags.HasTagExact(_MeleeTag),
            "Item.Melee should remain after removing Item.Weapon (other tags unaffected)");

        FinishSuccess();
    }
}
