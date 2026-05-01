// Language=angelscript

//============================================================================
// CK INVENTORY — AUTOMATION TEST: TAGS TRAIT — ADD TAG
//============================================================================
//
// Verifies Request_AddTag attaches a runtime tag to an item carrying the
// Tags trait:
//   1. Add a Sword (has UCk_ItemTrait_Tags with Item.Weapon + Item.Melee).
//   2. Bind OnTagsChanged.
//   3. Request_AddTag(Item.Rarity.Rare).
//   4. OnTagsChanged fires.
//   5. Get_Tags() now contains Item.Rarity.Rare in addition to the
//      definition-baked Item.Weapon and Item.Melee.
//
// NOTE: This test passes cleanly. The Sword item def carries Tags +
// Dimensions but NOT Stackable, so it sidesteps the Stackable-specific
// double-application warning that affects the DataOnly_* and
// StackableTrait_* tests (see CkAutoTest_Inventory_DataOnly_AddItem.as
// for the canonical framework-bug explanation).
//============================================================================

class UCk_AutoTest_Inventory_TagsTrait_AddTag : UCk_AutoTest_Base
{
    private FCk_Handle_Inventory _Inventory;
    private FCk_Handle_Item _Sword;
    private FGameplayTag _RareTag;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _RareTag = utils_gameplay_tag::ResolveGameplayTag(n"Item.Rarity.Rare");

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
        Assert_True(utils_item_trait_tags::Get_HasTagsFeature(_Sword),
            "Sword definition should produce an item with the Tags trait");

        utils_item_trait_tags::BindTo_OnTagsChanged(
            _Sword,
            FCk_Delegate_ItemTags_OnTagsChanged(this, n"OnTagsChanged"));

        utils_item_trait_tags::Request_AddTag(_Sword, _RareTag);
    }

    UFUNCTION()
    private void OnTagsChanged(
        FCk_Handle_Item InItem,
        FCk_Payload_Item_OnTagsChanged InPayload)
    {
        if (IsFinished()) { return; }

        auto Tags = utils_item_trait_tags::Get_Tags(_Sword);
        Assert_True(Tags.HasTagExact(_RareTag),
            f"Tags should contain Item.Rarity.Rare after Request_AddTag");

        FinishSuccess();
    }
}
