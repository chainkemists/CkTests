// Language=angelscript

//============================================================================
// INVENTORY GYM - DATA-ONLY UNBOUNDED ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_InvGym_DataOnlyUnbounded : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Inventory Inventory;

    int32 ItemsAddedCount = 0;
    int32 ItemsRemovedCount = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InvGym_DataOnlyUnbounded");

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

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemByDef,   FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemByDef"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_RemoveFirst,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveFirst"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_SortInventory,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnSort"));

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
        auto Items = utils_inventory::Get_Items(Inventory);

        auto DisplayText = "";
        DisplayText = f"{DisplayText}===== Data-Only Unbounded =====\n";
        DisplayText = f"{DisplayText}Items: {NumItems} (no limit)\n";
        DisplayText = f"{DisplayText}Added: {ItemsAddedCount}  Removed: {ItemsRemovedCount}\n\n";

        DisplayText = f"{DisplayText}===== Contents =====\n";
        auto Index = 0;
        for (auto Item : Items)
        {
            auto ItemName = inv_gym_helpers::GetItemDisplayName(Item);
            auto StackStr = "";
            if (utils_item_trait_stackable::Get_IsStackable(Item))
            {
                auto Count = utils_item_trait_stackable::Get_StackCount(Item);
                auto Max = utils_item_trait_stackable::Get_MaxStackSize(Item);
                StackStr = f" [{Count}/{Max}]";
            }
            DisplayText = f"{DisplayText}  [{Index}] {ItemName}{StackStr}\n";
            Index++;
            if (Index >= 12) { DisplayText = f"{DisplayText}  ... ({NumItems - 12} more)\n"; break; }
        }

        DisplayText = f"{DisplayText}\n===== Commands =====\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_AddPotion [n]\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_AddArrow [n]\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_RemoveFirst\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_SortAll";

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString("DATA-ONLY UNBOUNDED");
        Fragment.Description = FText::FromString(DisplayText);
    }

    UFUNCTION()
    void OnItemsChanged(FCk_Handle_Inventory InInventory, const TArray<FCk_Handle_Item>&in InItemsAdded, const TArray<FCk_Handle_Item>&in InItemsRemoved)
    {
        ItemsAddedCount += InItemsAdded.Num();
        ItemsRemovedCount += InItemsRemoved.Num();
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
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddByDefResult"));
    }

    UFUNCTION()
    void OnAddByDefResult(FCk_Handle_Inventory InInventory, ECk_Inventory_OperationResult_AddByDefinition InResult, int InAmountAdded, const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        ck::Trace(f"[InvGym Unbounded] AddByDef result: {InResult} amount={InAmountAdded}");
    }

    UFUNCTION()
    private void OnRemoveFirst(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Items = utils_inventory::Get_Items(Inventory);
        if (Items.Num() == 0) { return; }

        auto Request = FCk_Request_Inventory_RemoveItem(Items[0]);
        utils_inventory::Request_RemoveItem(
            Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_Remove());
    }

    UFUNCTION()
    private void OnSort(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        utils_inventory::Request_Sort(
            Inventory,
            FCk_Request_Inventory_Sort(),
            FCk_Delegate_Inventory_OnOperationResult_Sort());
    }
}
