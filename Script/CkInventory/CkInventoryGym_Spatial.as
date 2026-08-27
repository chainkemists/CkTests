// Language=angelscript

//============================================================================
// INVENTORY GYM - SPATIAL ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_InvGym_Spatial : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Inventory_Spatial Inventory;
    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    int32 AutoStep = 0;

    FIntPoint LastFailedCoord = FIntPoint(-1, -1);
    FIntPoint LastRandomCoord = FIntPoint(-1, -1);
    ECk_CardinalRotation LastRandomRotation = ECk_CardinalRotation::None;
    FString LastResult = "";

    FCkGym_AutoConfig AutoConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_InvGym_Spatial");

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        auto Params = utils_inventory_spatial::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.Equipment"),
            FIntPoint(8, 6),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        Inventory = utils_inventory_spatial::Add(InHandle, Params, ECk_Replication::DoesNotReplicate);

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemByDef, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemByDef"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemAt,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemAt"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_RemoveFirst,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveFirst"));

        AutoTimer = gym_auto::Setup(InHandle, this);

        AutoConfig.TotalSteps = 10;
        AutoConfig.Description = "8x6 grid with auto-placement, explicit\ncoordinates, and multi-cell items (3x1).";
        AutoConfig.GlobalAutoCommand = "Ck_GymInventory_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "Ck_GymInventory_AutoSpatial";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Auto-place 3x1 swords (x2)", 0, 1));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add shield (auto-place)", 2, 2));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Place sword at random coord", 3, 3));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add shield (expect blocked)", 4, 4));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Remove first (x5)", 5, 9));
        AutoConfig.ManualCommands.Add("Ck_GymInventory_AddSword");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_AddShieldAt [x] [y]");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_RemoveFirst");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_RestartAll");

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

        auto Dims = Inventory.Get_Dimensions();
        auto NumItems = Inventory.Get_NumItems();
        auto Items = Inventory.Get_Items();

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);
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
                auto ItemAtCell = Inventory.Get_ItemAtCoordinate(FIntPoint(X, Y));
                auto CellChar = ck::IsValid(ItemAtCell) ? Get_ItemCellChar(ItemAtCell) : "-";
                DisplayText = f"{DisplayText}{CellChar} ";
            }
            DisplayText = f"{DisplayText}\n";
        }

        DisplayText = f"{DisplayText}\nSword:{SwordCount} Shield:{ShieldCount} Potion:{PotionCount}\n";
        if (LastRandomCoord.X >= 0)
        {
            DisplayText = f"{DisplayText}Last random: ({LastRandomCoord.X},{LastRandomCoord.Y}) rot={LastRandomRotation}\n";
        }
        if (LastFailedCoord.X >= 0)
        {
            DisplayText = f"{DisplayText}Last blocked: ({LastFailedCoord.X},{LastFailedCoord.Y})\n";
        }

        if (LastResult != "") { DisplayText = f"{DisplayText}Last: {LastResult}\n"; }

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"SPATIAL INVENTORY (8x6) {ModeStr}");
        Fragment.Description = FText::FromString(DisplayText);
    }

    UFUNCTION()
    private void OnAddItemByDef(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_InvGym_AddItemByDef);
        auto Def = inv_gym_helpers::ResolveDefByName(Typed.DefName);
        if (Def == nullptr) { return; }

        auto SelfEntity = ck::ToEntity(this);
        auto Request = FCk_Request_Inventory_AddItemByDefinition(Def, Typed.Amount);
        Inventory.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
    }

    UFUNCTION()
    private void OnAddItemAt(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_InvGym_AddItemAt);
        auto Def = inv_gym_helpers::ResolveDefByName(Typed.DefName);
        if (Def == nullptr) { return; }

        auto SelfEntity = ck::ToEntity(this);
        auto NewItem = utils_item::Create(SelfEntity, Def);
        if (ck::IsValid(NewItem) == false) { return; }

        auto Placement = Inventory.Get_CanPlaceItemAt(NewItem, Typed.Coordinate);
        if (Placement._Succeeded == false)
        {
            LastFailedCoord = Typed.Coordinate;
            ck::Warning(f"[InvGym Spatial] Cannot place {Typed.DefName} at ({Typed.Coordinate.X},{Typed.Coordinate.Y}) - blocked");
            return;
        }

        auto Request = FCk_Request_Inventory_AddItem(NewItem);
        auto NewPlacement = FCk_SpatialPlacement();
        NewPlacement.Set_Coordinate(Typed.Coordinate);
        Inventory.Request_AddItem(Request, NewPlacement,
            FCk_Delegate_Inventory_OnOperationResult_Add(this, n"OnAddResult"));
    }

    UFUNCTION()
    void OnAddResult(FCk_Handle_Inventory InInventory, FCk_Handle_Item InItem, ECk_Inventory_OperationResult_Add InResult)
    {
        LastResult = f"AddItem: {InResult}";
    }

    UFUNCTION()
    private void OnRemoveFirst(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Items = Inventory.Get_Items();
        if (Items.Num() == 0) { return; }

        auto Request = FCk_Request_Inventory_RemoveItem(Items[0]);
        Inventory.Request_RemoveItem(Request,
            FCk_Delegate_Inventory_OnOperationResult_Remove());
    }

    //------------------------------------------------------------------------
    // AUTO MODE
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Step = AutoStep % 10;
        auto SwordDef = inv_gym_items::Sword();
        auto ShieldDef = inv_gym_items::Shield();

        if (Step <= 1 && SwordDef != nullptr)
        {
            Inventory.Request_AddItemByDefinition(FCk_Request_Inventory_AddItemByDefinition(SwordDef, 1), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 2 && ShieldDef != nullptr)
        {
            Inventory.Request_AddItemByDefinition(FCk_Request_Inventory_AddItemByDefinition(ShieldDef, 1), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 3 && SwordDef != nullptr)
        {
            auto GridDims = Inventory.Get_Dimensions();
            auto RandX = Math::RandRange(0, GridDims.X - 1);
            auto RandY = Math::RandRange(0, GridDims.Y - 1);
            auto RandRot = Math::RandRange(0, 3);
            auto Rotation = ECk_CardinalRotation(RandRot);

            LastRandomCoord = FIntPoint(RandX, RandY);
            LastRandomRotation = Rotation;

            auto SelfEntity = ck::ToEntity(this);
            auto NewItem = utils_item::Create(SelfEntity, SwordDef);
            if (ck::IsValid(NewItem))
            {
                auto Req = FCk_Request_Inventory_AddItem(NewItem);
                auto Placement = FCk_SpatialPlacement();
                Placement.Set_Coordinate(FIntPoint(RandX, RandY));
                Placement.Set_Rotation(Rotation);
                Inventory.Request_AddItem(Req, Placement, FCk_Delegate_Inventory_OnOperationResult_Add(this, n"OnAddResult"));
            }
        }
        else if (Step == 4 && ShieldDef != nullptr)
        {
            LastFailedCoord = FIntPoint(0, 0);
            Inventory.Request_AddItemByDefinition(FCk_Request_Inventory_AddItemByDefinition(ShieldDef, 1), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step >= 5)
        {
            // 5 removes to match 5 adds (steps 0-4)
            auto Items = Inventory.Get_Items();
            if (Items.Num() > 0)
            {
                Inventory.Request_RemoveItem(FCk_Request_Inventory_RemoveItem(Items[0]), FCk_Delegate_Inventory_OnOperationResult_Remove());
            }
        }

        AutoStep++;
    }
}
