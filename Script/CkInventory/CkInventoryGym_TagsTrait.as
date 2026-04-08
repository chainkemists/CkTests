// Language=angelscript

//============================================================================
// INVENTORY GYM - TAGS TRAIT ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_InvGym_TagsTrait : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Inventory Inventory;

    int32 TagChangeCount = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InvGym_TagsTrait");

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        auto Params = utils_inventory::Make_InventoryParams_DataOnly(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.Backpack"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        Inventory = utils_inventory::Add(InHandle, Params, ECk_Replication::DoesNotReplicate);

        utils_inventory::BindTo_OnItemsChanged(
            Inventory,
            FCk_Delegate_Inventory_OnItemsChanged(this, n"OnItemsChanged"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemByDef, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemByDef"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddTag,       FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddTag"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_RemoveTag,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveTag"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DisplayStats();
    }

    void DisplayStats()
    {
        auto SelfEntity = ck::ToEntity(this);
        if (ck::IsValid(Inventory) == false) { return; }

        auto NumItems = utils_inventory::Get_NumItems(Inventory);

        auto DisplayText = "";
        DisplayText = f"{DisplayText}===== Tags Trait =====\n";
        DisplayText = f"{DisplayText}Items: {NumItems}   Tag changes: {TagChangeCount}\n\n";

        DisplayText = f"{DisplayText}===== Items and Tags =====\n";
        auto Items = utils_inventory::Get_Items(Inventory);
        auto Index = 0;
        for (auto Item : Items)
        {
            auto ItemName = inv_gym_helpers::GetItemDisplayName(Item);
            if (utils_item_trait_tags::Get_HasTagsFeature(Item))
            {
                auto ItemTags = utils_item_trait_tags::Get_Tags(Item);
                auto TagStr = inv_gym_helpers::TagsToString(ItemTags);
                DisplayText = f"{DisplayText}  [{Index}] {ItemName}: {TagStr}\n";
            }
            else
            {
                DisplayText = f"{DisplayText}  [{Index}] {ItemName} (no tags feature)\n";
            }
            Index++;
            if (Index >= 6) { break; }
        }

        DisplayText = f"{DisplayText}\n===== Commands =====\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_AddRareTag\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_RemoveRareTag";

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString("TAGS TRAIT");
        Fragment.Description = FText::FromString(DisplayText);
    }

    UFUNCTION()
    void OnItemsChanged(FCk_Handle_Inventory InInventory, const TArray<FCk_Handle_Item>&in InItemsAdded, const TArray<FCk_Handle_Item>&in InItemsRemoved)
    {
        for (auto Item : InItemsAdded)
        {
            if (utils_item_trait_tags::Get_HasTagsFeature(Item))
            {
                utils_item_trait_tags::BindTo_OnTagsChanged(
                    Item,
                    FCk_Delegate_ItemTags_OnTagsChanged(this, n"OnTagsChanged"));
            }
        }
    }

    UFUNCTION()
    void OnTagsChanged(FCk_Handle_Item InItem, FCk_Payload_Item_OnTagsChanged InPayload)
    {
        TagChangeCount++;
    }

    UFUNCTION()
    private void OnAddItemByDef(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_InvGym_AddItemByDef);
        auto Def = inv_gym_helpers::ResolveDefByName(Typed.DefName);
        if (Def == nullptr) { return; }

        auto Request = FCk_Request_Inventory_AddItemByDefinition(Def, Typed.Amount);
        utils_inventory::Request_AddItemByDefinition(
            Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
    }

    UFUNCTION()
    private void OnAddTag(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_InvGym_AddTag);
        auto Items = utils_inventory::Get_Items(Inventory);
        for (auto Item : Items)
        {
            if (utils_item_trait_tags::Get_HasTagsFeature(Item))
            {
                utils_item_trait_tags::Request_AddTag(Item, Typed.Tag);
            }
        }
        ck::Trace(f"[InvGym TagsTrait] Added tag {Typed.Tag.ToString()} to all items");
    }

    UFUNCTION()
    private void OnRemoveTag(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_InvGym_RemoveTag);
        auto Items = utils_inventory::Get_Items(Inventory);
        for (auto Item : Items)
        {
            if (utils_item_trait_tags::Get_HasTagsFeature(Item))
            {
                utils_item_trait_tags::Request_RemoveTag(Item, Typed.Tag);
            }
        }
        ck::Trace(f"[InvGym TagsTrait] Removed tag {Typed.Tag.ToString()} from all items");
    }
}
