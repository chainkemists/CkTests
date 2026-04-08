// Language=angelscript

//============================================================================
// INVENTORY GYM - SPATIAL ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_InvGym_Spatial : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Inventory Inventory;

    FIntPoint LastFailedCoord = FIntPoint(-1, -1);

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_InvGym_Spatial");

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        auto Params = utils_inventory::Make_InventoryParams_Spatial(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.Equipment"),
            FIntPoint(8, 6),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        Inventory = utils_inventory::Add(InHandle, Params, ECk_Replication::DoesNotReplicate);

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemByDef, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemByDef"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemAt,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemAt"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_RemoveFirst,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveFirst"));

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

        auto Spatial = utils_inventory_spatial::DoCastChecked(Inventory);
        auto Dims = utils_inventory_spatial::Get_Dimensions(Spatial);
        auto NumItems = utils_inventory::Get_NumItems(Inventory);

        auto DisplayText = "";
        DisplayText = f"{DisplayText}===== Spatial Inventory =====\n";
        DisplayText = f"{DisplayText}Grid: {Dims.X} x {Dims.Y}\n";
        DisplayText = f"{DisplayText}Items: {NumItems}\n";
        DisplayText = f"{DisplayText}Last failed placement: ({LastFailedCoord.X},{LastFailedCoord.Y})\n\n";

        DisplayText = f"{DisplayText}===== Contents =====\n";
        auto Items = utils_inventory::Get_Items(Inventory);
        auto Index = 0;
        for (auto Item : Items)
        {
            auto ItemName = inv_gym_helpers::GetItemDisplayName(Item);
            DisplayText = f"{DisplayText}  [{Index}] {ItemName}\n";
            Index++;
            if (Index >= 10) { DisplayText = f"{DisplayText}  ... ({NumItems - 10} more)\n"; break; }
        }

        DisplayText = f"{DisplayText}\n===== Commands =====\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_AddSword (auto-place)\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_AddShieldAt [x] [y]";

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString("SPATIAL INVENTORY (8x6)");
        Fragment.Description = FText::FromString(DisplayText);
    }

    UFUNCTION()
    private void OnAddItemByDef(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_InvGym_AddItemByDef);
        auto Def = inv_gym_helpers::ResolveDefByName(Typed.DefName);
        if (Def == nullptr) { return; }

        auto SelfEntity = ck::ToEntity(this);
        auto Request = FCk_Request_Inventory_AddItemByDefinition(Def, Typed.Amount);
        utils_inventory::Request_AddItemByDefinition(
            Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
    }

    UFUNCTION()
    private void OnAddItemAt(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_InvGym_AddItemAt);
        auto Def = inv_gym_helpers::ResolveDefByName(Typed.DefName);
        if (Def == nullptr) { return; }

        auto SelfEntity = ck::ToEntity(this);
        auto NewItem = utils_item::Create(SelfEntity, Def);
        if (ck::IsValid(NewItem) == false) { return; }

        auto Spatial = utils_inventory_spatial::DoCastChecked(Inventory);
        auto Placement = utils_inventory_spatial::Get_CanPlaceItemAt(Spatial, NewItem, Typed.Coordinate);
        if (Placement._Succeeded == false)
        {
            LastFailedCoord = Typed.Coordinate;
            ck::Warning(f"[InvGym Spatial] Cannot place {Typed.DefName} at ({Typed.Coordinate.X},{Typed.Coordinate.Y}) — blocked");
            return;
        }

        auto Request = FCk_Request_Inventory_AddItem(NewItem);
        Request.Set_PlacementCoordinate(Typed.Coordinate);
        utils_inventory::Request_AddItem(
            Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_Add(this, n"OnAddResult"));
    }

    UFUNCTION()
    void OnAddResult(FCk_Handle_Inventory InInventory, FCk_Handle_Item InItem, ECk_Inventory_OperationResult_Add InResult)
    {
        ck::Trace(f"[InvGym Spatial] AddItem result: {InResult}");
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
}
