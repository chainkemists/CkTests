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
    FCk_Handle_Timer AutoTimer;

    int32 TagChangeCount = 0;
    bool AutoRunning = true;
    int32 AutoStep = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
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
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AutoToggle,   FCk_Delegate_Messaging_OnBroadcast(this, n"OnAutoToggle"));

        auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5f));
        AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
        AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"AutoTick"));

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

        auto Step = AutoStep % 6;
        auto A0 = (AutoRunning && Step == 0) ? ">> " : "   ";
        auto A1 = (AutoRunning && Step == 1) ? ">> " : "   ";
        auto A2 = (AutoRunning && Step == 2) ? ">> " : "   ";
        auto A3 = (AutoRunning && Step == 3) ? ">> " : "   ";
        auto A4 = (AutoRunning && Step == 4) ? ">> " : "   ";
        auto A5 = (AutoRunning && Step == 5) ? ">> " : "   ";

        auto AutoStr = AutoRunning ? ">> Ck_GymInventory_Auto - ON" : "   Ck_GymInventory_Auto - OFF";

        DisplayText = f"{DisplayText}\n===== Operations =====\n";
        DisplayText = f"{DisplayText}{AutoStr}\n";
        DisplayText = f"{DisplayText}{A0}Ck_GymInventory_AddPotion - Add item\n";
        DisplayText = f"{DisplayText}{A1}Ck_GymInventory_AddRareTag - Tag Rare\n";
        DisplayText = f"{DisplayText}{A2}Ck_GymInventory_AddRareTag - Tag Legendary\n";
        DisplayText = f"{DisplayText}{A3}Ck_GymInventory_RemoveRareTag - Untag Rare\n";
        DisplayText = f"{DisplayText}{A4}Ck_GymInventory_RemoveRareTag - Untag Legendary\n";
        DisplayText = f"{DisplayText}{A5}Ck_GymInventory_RemoveFirst - Remove item";

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"TAGS TRAIT {ModeStr}");
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

    void StopAuto()
    {
        if (AutoRunning) { AutoRunning = false; utils_timer::Request_Pause(AutoTimer); }
    }

    UFUNCTION()
    private void OnAddItemByDef(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        StopAuto();
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
        StopAuto();
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
        StopAuto();
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

    //------------------------------------------------------------------------
    // AUTO MODE
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnAutoToggle(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        AutoRunning = !AutoRunning;
        if (AutoRunning) { utils_timer::Request_Resume(AutoTimer); }
        else { utils_timer::Request_Pause(AutoTimer); }
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Step = AutoStep % 6;
        auto SwordDef = inv_gym_items::Sword();
        auto RareTag = utils_gameplay_tag::ResolveGameplayTag(n"Item.Rarity.Rare");
        auto LegendaryTag = utils_gameplay_tag::ResolveGameplayTag(n"Item.Rarity.Legendary");

        if (Step == 0 && SwordDef != nullptr)
        {
            utils_inventory::Request_AddItemByDefinition(Inventory, FCk_Request_Inventory_AddItemByDefinition(SwordDef, 1), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 1 || Step == 2)
        {
            auto TagToAdd = (Step == 1) ? RareTag : LegendaryTag;
            auto Items = utils_inventory::Get_Items(Inventory);
            for (auto Item : Items)
            {
                if (utils_item_trait_tags::Get_HasTagsFeature(Item))
                {
                    utils_item_trait_tags::Request_AddTag(Item, TagToAdd);
                }
            }
        }
        else if (Step == 3 || Step == 4)
        {
            auto TagToRemove = (Step == 3) ? RareTag : LegendaryTag;
            auto Items = utils_inventory::Get_Items(Inventory);
            for (auto Item : Items)
            {
                if (utils_item_trait_tags::Get_HasTagsFeature(Item))
                {
                    utils_item_trait_tags::Request_RemoveTag(Item, TagToRemove);
                }
            }
        }
        else if (Step == 5)
        {
            auto Items = utils_inventory::Get_Items(Inventory);
            if (Items.Num() > 0)
            {
                utils_inventory::Request_RemoveItem(Inventory, FCk_Request_Inventory_RemoveItem(Items[0]), FCk_Delegate_Inventory_OnOperationResult_Remove());
            }
        }

        AutoStep++;
    }
}
