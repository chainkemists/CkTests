// Language=angelscript

//============================================================================
// INVENTORY GYM - DATA-ONLY UNBOUNDED ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_InvGym_DataOnlyUnbounded : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Inventory_DataOnly Inventory;
    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    int32 AutoStep = 0;
    FString LastResult = "";

    int32 ItemsAddedCount = 0;
    int32 ItemsRemovedCount = 0;

    FCkGym_AutoConfig AutoConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_InvGym_DataOnlyUnbounded");

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        auto Params = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.Backpack"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        Inventory = utils_inventory_data_only::Add(InHandle, Params, ECk_Replication::DoesNotReplicate);

        Inventory.BindTo_OnItemsChanged(FCk_Delegate_Inventory_OnItemsChanged(this, n"OnItemsChanged"));

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemByDef,   FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemByDef"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_RemoveFirst,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveFirst"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_SortInventory,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnSort"));

        AutoTimer = gym_auto::Setup(InHandle, this);

        AutoConfig.TotalSteps = 7;
        AutoConfig.Description = "Unlimited-capacity data-only inventory.\nTests add/remove/sort and OnItemsChanged.";
        AutoConfig.GlobalAutoCommand = "Ck_GymInventory_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "panel [F] Re-arm auto (Data-only unbounded)";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add 3 potions", 0, 0));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add 5 arrows", 1, 1));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add 1 sword", 2, 2));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Sort inventory", 3, 3));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Remove first (x3)", 4, 6));
        AutoConfig.ManualCommands.Add("Ck_GymInventory_AddPotion [n]");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_AddArrow [n]");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_RemoveFirst");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_SortAll");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_RestartAll");

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

        auto NumItems = Inventory.Get_NumItems();
        auto Items = Inventory.Get_Items();

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);
        DisplayText = f"{DisplayText}Items: {NumItems} (no limit)\n";
        DisplayText = f"{DisplayText}Added: {ItemsAddedCount}  Removed: {ItemsRemovedCount}\n";
        if (LastResult != "") { DisplayText = f"{DisplayText}Last: {LastResult}\n"; }
        DisplayText = f"{DisplayText}\n";

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

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"DATA-ONLY UNBOUNDED {ModeStr}");
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
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_InvGym_AddItemByDef);
        auto Def = inv_gym_helpers::ResolveDefByName(Typed.DefName);
        if (Def == nullptr) { return; }

        auto Request = FCk_Request_Inventory_AddItemByDefinition(Def, Typed.Amount);
        Inventory.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddByDefResult"));
    }

    UFUNCTION()
    void OnAddByDefResult(FCk_Handle_Inventory InInventory, ECk_Inventory_OperationResult_AddByDefinition InResult, int InAmountAdded, const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        LastResult = f"Add: {InResult} (+{InAmountAdded})";
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

    UFUNCTION()
    private void OnSort(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        Inventory.Request_Sort(FCk_Request_Inventory_Sort(),
            FCk_Delegate_Inventory_OnOperationResult_Sort());
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
        auto Step = AutoStep % 7;
        auto PotionDef = inv_gym_items::Potion();
        auto ArrowDef = inv_gym_items::Arrow();
        auto SwordDef = inv_gym_items::Sword();

        if (Step == 0 && PotionDef != nullptr)
        {
            Inventory.Request_AddItemByDefinition(FCk_Request_Inventory_AddItemByDefinition(PotionDef, 3), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 1 && ArrowDef != nullptr)
        {
            Inventory.Request_AddItemByDefinition(FCk_Request_Inventory_AddItemByDefinition(ArrowDef, 5), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 2 && SwordDef != nullptr)
        {
            Inventory.Request_AddItemByDefinition(FCk_Request_Inventory_AddItemByDefinition(SwordDef, 1), FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 3)
        {
            Inventory.Request_Sort(FCk_Request_Inventory_Sort(), FCk_Delegate_Inventory_OnOperationResult_Sort());
        }
        else if (Step >= 4)
        {
            auto Items = Inventory.Get_Items();
            if (Items.Num() > 0)
            {
                Inventory.Request_RemoveItem(FCk_Request_Inventory_RemoveItem(Items[0]), FCk_Delegate_Inventory_OnOperationResult_Remove());
            }
        }

        AutoStep++;
    }
}
