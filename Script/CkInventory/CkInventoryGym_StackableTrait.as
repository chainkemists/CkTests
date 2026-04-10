// Language=angelscript

//============================================================================
// INVENTORY GYM - STACKABLE TRAIT ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_InvGym_StackableTrait : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Inventory Inventory;
    FCk_Handle_Timer AutoTimer;

    int32 StackEventsCount = 0;
    bool AutoRunning = true;
    int32 AutoStep = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_InvGym_StackableTrait");

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

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemByDef,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemByDef"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_StackFirstTwo,   FCk_Delegate_Messaging_OnBroadcast(this, n"OnStackFirstTwo"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_SplitFirst,      FCk_Delegate_Messaging_OnBroadcast(this, n"OnSplitFirst"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AutoToggle,      FCk_Delegate_Messaging_OnBroadcast(this, n"OnAutoToggle"));

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
        DisplayText = f"{DisplayText}===== Stackable Trait =====\n";
        DisplayText = f"{DisplayText}Items: {NumItems}   Stack events: {StackEventsCount}\n\n";

        DisplayText = f"{DisplayText}===== Stacks =====\n";
        auto Items = utils_inventory::Get_Items(Inventory);
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
        DisplayText = f"{DisplayText}{A0}Ck_GymInventory_AddPotion - New stack\n";
        DisplayText = f"{DisplayText}{A1}Ck_GymInventory_AddPotion - New stack\n";
        DisplayText = f"{DisplayText}{A2}Ck_GymInventory_StackPotions - Merge first two\n";
        DisplayText = f"{DisplayText}{A3}Ck_GymInventory_SplitStack 1 - Split off 1\n";
        DisplayText = f"{DisplayText}{A4}Ck_GymInventory_StackPotions - Re-merge\n";
        DisplayText = f"{DisplayText}{A5}Ck_GymInventory_RemoveFirst - Remove";

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
        // Force new item so each add creates a separate stack for the manual stack demo
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        utils_inventory::Request_AddItemByDefinition(
            Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
    }

    UFUNCTION()
    private void OnStackFirstTwo(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        StopAuto();
        auto Items = utils_inventory::Get_Items(Inventory);
        if (Items.Num() < 2)
        {
            ck::Warning("[InvGym Stackable] Need at least 2 items to stack");
            return;
        }

        auto Request = FCk_Request_Inventory_StackItems(Items[0], Items[1]);
        utils_inventory::Request_StackItems(
            Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_Stack(this, n"OnStackResult"));
    }

    UFUNCTION()
    void OnStackResult(FCk_Handle_Inventory InInventory, FCk_Handle_Item InSource, FCk_Handle_Item InTarget, ECk_Inventory_OperationResult_Stack InResult)
    {
        ck::Trace(f"[InvGym Stackable] Stack result: {InResult}");
    }

    UFUNCTION()
    private void OnSplitFirst(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        StopAuto();
        auto Typed = InPayload.Get(FCk_Message_InvGym_SplitFirst);
        auto Items = utils_inventory::Get_Items(Inventory);
        if (Items.Num() == 0)
        {
            ck::Warning("[InvGym Stackable] No item to split");
            return;
        }

        auto Request = FCk_Request_Inventory_SplitStack(Items[0], Typed.SplitCount);
        utils_inventory::Request_SplitStack(
            Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_Split(this, n"OnSplitResult"));
    }

    UFUNCTION()
    void OnSplitResult(FCk_Handle_Inventory InInventory, FCk_Handle_Item InSource, FCk_Handle_Item InNewItem, ECk_Inventory_OperationResult_Split InResult)
    {
        ck::Trace(f"[InvGym Stackable] Split result: {InResult}");
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
        auto PotionDef = inv_gym_items::Potion();

        if (Step <= 1 && PotionDef != nullptr)
        {
            auto Req = FCk_Request_Inventory_AddItemByDefinition(PotionDef, 1);
            Req.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            utils_inventory::Request_AddItemByDefinition(Inventory, Req, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }
        else if (Step == 2 || Step == 4)
        {
            auto Items = utils_inventory::Get_Items(Inventory);
            if (Items.Num() >= 2)
            {
                utils_inventory::Request_StackItems(Inventory, FCk_Request_Inventory_StackItems(Items[0], Items[1]), FCk_Delegate_Inventory_OnOperationResult_Stack());
            }
        }
        else if (Step == 3)
        {
            auto Items = utils_inventory::Get_Items(Inventory);
            if (Items.Num() > 0)
            {
                utils_inventory::Request_SplitStack(Inventory, FCk_Request_Inventory_SplitStack(Items[0], 1), FCk_Delegate_Inventory_OnOperationResult_Split());
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
