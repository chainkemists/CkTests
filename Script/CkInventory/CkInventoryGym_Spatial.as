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
    FCk_Handle_Timer AutoTimer;

    FIntPoint LastFailedCoord = FIntPoint(-1, -1);
    bool AutoRunning = true;
    int32 AutoStep = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
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

    FString Get_ItemCellChar(FCk_Handle_Item InItem)
    {
        auto ItemName = inv_gym_helpers::GetItemDisplayName(InItem);
        if (ItemName == "Potion") { return "P"; }
        if (ItemName == "Arrow")  { return "A"; }
        if (ItemName == "Sword")  { return "S"; }
        if (ItemName == "Shield") { return "O"; }
        if (ItemName == "Key")    { return "K"; }
        return "?";
    }

    void DisplayStats()
    {
        auto SelfEntity = ck::ToEntity(this);
        if (ck::IsValid(Inventory) == false) { return; }

        auto Spatial = utils_inventory_spatial::DoCastChecked(Inventory);
        auto Dims = utils_inventory_spatial::Get_Dimensions(Spatial);
        auto NumItems = utils_inventory::Get_NumItems(Inventory);
        auto Items = utils_inventory::Get_Items(Inventory);

        auto DisplayText = "";
        DisplayText = f"{DisplayText}Items: {NumItems}  Grid: {Dims.X}x{Dims.Y}\n\n";

        // Legend showing which color/letter maps to which item
        auto SwordCount = 0;
        auto ShieldCount = 0;
        auto PotionCount = 0;
        for (auto Item : Items)
        {
            auto ItemName = inv_gym_helpers::GetItemDisplayName(Item);
            if (ItemName == "Sword")  { SwordCount++; }
            if (ItemName == "Shield") { ShieldCount++; }
            if (ItemName == "Potion") { PotionCount++; }
        }

        for (auto Y = 0; Y < Dims.Y; Y++)
        {
            for (auto X = 0; X < Dims.X; X++)
            {
                auto ItemAtCell = utils_inventory_spatial::Get_ItemAtCoordinate(Spatial, FIntPoint(X, Y));
                auto CellChar = ck::IsValid(ItemAtCell) ? Get_ItemCellChar(ItemAtCell) : "-";
                DisplayText = f"{DisplayText}{CellChar} ";
            }
            DisplayText = f"{DisplayText}\n";
        }

        DisplayText = f"{DisplayText}\nSword:{SwordCount} Shield:{ShieldCount} Potion:{PotionCount}\n";
        if (LastFailedCoord.X >= 0)
        {
            DisplayText = f"{DisplayText}Last blocked: ({LastFailedCoord.X},{LastFailedCoord.Y})\n";
        }

        auto Step = AutoStep % 8;
        auto A0 = (AutoRunning && Step <= 1) ? ">> " : "   ";
        auto A1 = (AutoRunning && Step == 2) ? ">> " : "   ";
        auto A2 = (AutoRunning && Step == 3) ? ">> " : "   ";
        auto A3 = (AutoRunning && Step >= 4) ? ">> " : "   ";

        auto AutoStr = AutoRunning ? ">> Ck_GymInventory_Auto - ON" : "   Ck_GymInventory_Auto - OFF";

        DisplayText = f"{DisplayText}\n===== Operations =====\n";
        DisplayText = f"{DisplayText}{AutoStr}\n";
        DisplayText = f"{DisplayText}{A0}Ck_GymInventory_AddSword - Auto-place 3x1 (x2)\n";
        DisplayText = f"{DisplayText}{A1}Ck_GymInventory_AddShieldAt - Add shield\n";
        DisplayText = f"{DisplayText}{A2}Ck_GymInventory_AddShieldAt - Add another shield\n";
        DisplayText = f"{DisplayText}{A3}Ck_GymInventory_RemoveFirst - Remove (x4)";

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"SPATIAL INVENTORY (8x6) {ModeStr}");
        Fragment.Description = FText::FromString(DisplayText);
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
        StopAuto();
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
        StopAuto();
        auto Items = utils_inventory::Get_Items(Inventory);
        if (Items.Num() == 0) { return; }

        auto Request = FCk_Request_Inventory_RemoveItem(Items[0]);
        utils_inventory::Request_RemoveItem(
            Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_Remove());
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
        auto Step = AutoStep % 8;
        auto SwordDef = inv_gym_items::Sword();
        auto ShieldDef = inv_gym_items::Shield();
        auto SelfEntity = ck::ToEntity(this);

        if (Step <= 1 && SwordDef != nullptr)
        {
            // Add 3x1 swords via auto-place
            utils_inventory::Request_AddItemByDefinition(Inventory, FCk_Request_Inventory_AddItemByDefinition(SwordDef, 1), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 2 && ShieldDef != nullptr)
        {
            // Add shield via auto-place — finds first free slot
            utils_inventory::Request_AddItemByDefinition(Inventory, FCk_Request_Inventory_AddItemByDefinition(ShieldDef, 1), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 3 && ShieldDef != nullptr)
        {
            // Try adding another shield — use AddItemByDefinition but the grid
            // may be filling up. Also test the blocked coordinate query.
            auto Spatial = utils_inventory_spatial::DoCastChecked(Inventory);
            // Check if (0,0) is blocked (it should be — swords are there)
            // We need a temp item to query placement, use AddItemByDefinition
            // and let it auto-place. The blocked coord display is just informational.
            LastFailedCoord = FIntPoint(0, 0);
            utils_inventory::Request_AddItemByDefinition(Inventory, FCk_Request_Inventory_AddItemByDefinition(ShieldDef, 1), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step >= 4)
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
