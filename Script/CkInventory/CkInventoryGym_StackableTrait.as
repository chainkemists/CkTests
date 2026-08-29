// Language=angelscript

//============================================================================
// INVENTORY GYM - STACKABLE TRAIT ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_InvGym_StackableTrait : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Inventory_DataOnly Inventory;
    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    int32 AutoStep = 0;

    int32 StackEventsCount = 0;
    FString LastResult = "";

    FCkGym_AutoConfig AutoConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_InvGym_StackableTrait");

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

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemByDef,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemByDef"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_StackFirstTwo,   FCk_Delegate_Messaging_OnBroadcast(this, n"OnStackFirstTwo"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_SplitFirst,      FCk_Delegate_Messaging_OnBroadcast(this, n"OnSplitFirst"));

        AutoTimer = gym_auto::Setup(InHandle, this);

        AutoConfig.TotalSteps = 6;
        AutoConfig.Description = "Request_StackItems, Request_SplitStack.\nBinds OnStackCountChanged per item.";
        AutoConfig.GlobalAutoCommand = "panel [U] auto on / [Y] auto off";
        AutoConfig.PerStationAutoCommand = "panel [K] Re-arm auto (Stackable trait)";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add potion (new stack)", 0, 0));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add potion (new stack)", 1, 1));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Merge first two stacks", 2, 2));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Split 1 off first stack", 3, 3));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Re-merge first two", 4, 4));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Remove first item", 5, 5));
        AutoConfig.ManualCommands.Add("Ck_GymInventory_AddPotion [n]");
        AutoConfig.ManualCommands.Add("panel [6] Stack the potions");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_SplitStack [n]");
        AutoConfig.ManualCommands.Add("panel [5] Remove the first item");
        AutoConfig.ManualCommands.Add("panel [R] Restart everything");

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

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);
        DisplayText = f"{DisplayText}Items: {NumItems}   Stack events: {StackEventsCount}\n";
        if (LastResult != "") { DisplayText = f"{DisplayText}Last: {LastResult}\n"; }
        DisplayText = f"{DisplayText}\n";

        DisplayText = f"{DisplayText}===== Stacks =====\n";
        auto Items = Inventory.Get_Items();
        auto Index = 0;
        for (auto Item : Items)
        {
            auto ItemName = inv_gym_helpers::GetItemDisplayName(Item);
            if (utils_item_trait_stackable::Get_IsStackable(Item))
            {
                auto Count = utils_item_trait_stackable::Get_StackCount(Item);
                auto Max = utils_item_trait_stackable::Get_MaxStackSize(Item);
                auto Remaining = utils_item_trait_stackable::Get_RemainingStackCapacity(Item);
                auto FullStr = utils_item_trait_stackable::Get_IsStackFull(Item) ? " [FULL]" : "";
                DisplayText = f"{DisplayText}  [{Index}] {ItemName}: {Count}/{Max} (room: {Remaining}){FullStr}\n";
            }
            else
            {
                DisplayText = f"{DisplayText}  [{Index}] {ItemName} (not stackable)\n";
            }
            Index++;
        }

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"STACKABLE TRAIT {ModeStr}");
        Fragment.Description = FText::FromString(DisplayText);
    }

    UFUNCTION()
    void OnItemsChanged(FCk_Handle_Inventory InInventory, const TArray<FCk_Handle_Item>&in InItemsAdded, const TArray<FCk_Handle_Item>&in InItemsRemoved)
    {
        // Bind stack-count-changed to any newly added stackable item
        for (auto Item : InItemsAdded)
        {
            if (utils_item_trait_stackable::Get_IsStackable(Item))
            {
                utils_item_trait_stackable::BindTo_OnStackCountChanged(
                    Item,
                    FCk_Delegate_Stackable_OnStackCountChanged(this, n"OnStackCountChanged"));
            }
        }
    }

    UFUNCTION()
    void OnStackCountChanged(FCk_Handle_Item InItem, FCk_Payload_Item_OnStackCountChanged InPayload)
    {
        StackEventsCount++;
    }

    UFUNCTION()
    private void OnAddItemByDef(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_InvGym_AddItemByDef);
        auto Def = inv_gym_helpers::ResolveDefByName(Typed.DefName);
        if (Def == nullptr) { return; }

        auto Request = FCk_Request_Inventory_AddItemByDefinition(Def, Typed.Amount);
        // Force new item so each add creates a separate stack for the manual stack demo
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        Inventory.Request_AddItemByDefinition(Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
    }

    UFUNCTION()
    private void OnStackFirstTwo(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Items = Inventory.Get_Items();
        if (Items.Num() < 2)
        {
            ck::Warning("[InvGym Stackable] Need at least 2 items to stack");
            return;
        }

        auto Request = FCk_Request_Inventory_StackItems(Items[0], Items[1]);
        Inventory.Request_StackItems(Request,
            FCk_Delegate_Inventory_OnOperationResult_Stack(this, n"OnStackResult"));
    }

    UFUNCTION()
    void OnStackResult(FCk_Handle_Inventory InInventory, FCk_Handle_Item InSource, FCk_Handle_Item InTarget, ECk_Inventory_OperationResult_Stack InResult)
    {
        LastResult = f"Stack: {InResult}";
    }

    UFUNCTION()
    private void OnSplitFirst(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        auto Typed = InPayload.Get(FCk_Message_InvGym_SplitFirst);
        auto Items = Inventory.Get_Items();
        if (Items.Num() == 0)
        {
            ck::Warning("[InvGym Stackable] No item to split");
            return;
        }

        auto Request = FCk_Request_Inventory_SplitStack(Items[0], Typed.SplitCount);
        Inventory.Request_SplitStack(Request,
            FCk_Delegate_Inventory_OnOperationResult_Split(this, n"OnSplitResult"));
    }

    UFUNCTION()
    void OnSplitResult(FCk_Handle_Inventory InInventory, FCk_Handle_Item InSource, FCk_Handle_Item InNewItem, ECk_Inventory_OperationResult_Split InResult)
    {
        LastResult = f"Split: {InResult}";
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
        auto Step = AutoStep % 6;
        auto PotionDef = inv_gym_items::Potion();

        if (Step <= 1 && PotionDef != nullptr)
        {
            auto Req = FCk_Request_Inventory_AddItemByDefinition(PotionDef, 1);
            Req.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            Inventory.Request_AddItemByDefinition(Req, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 2 || Step == 4)
        {
            auto Items = Inventory.Get_Items();
            if (Items.Num() >= 2)
            {
                Inventory.Request_StackItems(FCk_Request_Inventory_StackItems(Items[0], Items[1]), FCk_Delegate_Inventory_OnOperationResult_Stack());
            }
        }
        else if (Step == 3)
        {
            auto Items = Inventory.Get_Items();
            if (Items.Num() > 0)
            {
                Inventory.Request_SplitStack(FCk_Request_Inventory_SplitStack(Items[0], 1), FCk_Delegate_Inventory_OnOperationResult_Split());
            }
        }
        else if (Step == 5)
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
