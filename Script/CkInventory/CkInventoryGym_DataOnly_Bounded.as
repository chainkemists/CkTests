// Language=angelscript

//============================================================================
// INVENTORY GYM - DATA-ONLY BOUNDED ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_InvGym_DataOnlyBounded : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Inventory Inventory;
    FCk_Handle_Timer AutoTimer;

    int32 LastAddResult = -1;
    bool AutoRunning = true;
    int32 AutoStep = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_InvGym_DataOnlyBounded");

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        auto Params = utils_inventory::Make_InventoryParams_DataOnly_Bounded(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.Bounded"),
            5,
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());

        Inventory = utils_inventory::Add(InHandle, Params, ECk_Replication::DoesNotReplicate);

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_AddItemByDef,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddItemByDef"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_RemoveFirst,     FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveFirst"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_OverrideBounds,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnOverrideBounds"));
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

        auto DataOnly = utils_inventory_data_only::DoCastChecked(Inventory);
        auto IsBounded = false;
        auto BoundMax = utils_inventory_data_only::Get_BoundMax_BP(DataOnly, IsBounded);
        auto NumItems = utils_inventory::Get_NumItems(Inventory);

        auto DisplayText = "";
        DisplayText = f"{DisplayText}===== Data-Only Bounded =====\n";
        auto BoundedStr = IsBounded ? f"{BoundMax}" : "UNBOUNDED";
        DisplayText = f"{DisplayText}Items: {NumItems}/{BoundedStr}\n";
        DisplayText = f"{DisplayText}Last Add Result: {LastAddResult}\n\n";

        DisplayText = f"{DisplayText}===== Contents =====\n";
        auto Items = utils_inventory::Get_Items(Inventory);
        auto Index = 0;
        for (auto Item : Items)
        {
            auto ItemName = inv_gym_helpers::GetItemDisplayName(Item);
            DisplayText = f"{DisplayText}  [{Index}] {ItemName}\n";
            Index++;
        }

        auto Step = AutoStep % 11;
        auto A0 = (AutoRunning && Step <= 4)  ? ">> " : "   ";
        auto A1 = (AutoRunning && Step == 5)  ? ">> " : "   ";
        auto A2 = (AutoRunning && Step == 6)  ? ">> " : "   ";
        auto A3 = (AutoRunning && Step <= 8 && Step >= 7) ? ">> " : "   ";
        auto A4 = (AutoRunning && Step == 9)  ? ">> " : "   ";
        auto A5 = (AutoRunning && Step == 10) ? ">> " : "   ";

        auto AutoStr = AutoRunning ? ">> Ck_GymInventory_Auto - ON" : "   Ck_GymInventory_Auto - OFF";

        DisplayText = f"{DisplayText}\n===== Operations =====\n";
        DisplayText = f"{DisplayText}{AutoStr}\n";
        DisplayText = f"{DisplayText}{A0}Ck_GymInventory_FillBounded - Fill to 5\n";
        DisplayText = f"{DisplayText}{A1}Ck_GymInventory_FillBounded - Overfill (reject)\n";
        DisplayText = f"{DisplayText}{A2}Ck_GymInventory_SetBounds 10 - Expand limit\n";
        DisplayText = f"{DisplayText}{A3}Ck_GymInventory_FillBounded - Add 2 more\n";
        DisplayText = f"{DisplayText}{A4}Ck_GymInventory_RemoveFirst - Clear all\n";
        DisplayText = f"{DisplayText}{A5}Ck_GymInventory_SetBounds 5 - Reset limit";

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        auto ModeStr = AutoRunning ? "[AUTO]" : "[MANUAL]";
        Fragment.Title = FText::FromString(f"DATA-ONLY BOUNDED (max 5) {ModeStr}");
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

        auto Request = FCk_Request_Inventory_AddItemByDefinition(Def, Typed.Amount);
        Request.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        utils_inventory::Request_AddItemByDefinition(
            Inventory,
            Request,
            FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
    }

    UFUNCTION()
    void OnAddResult(FCk_Handle_Inventory InInventory, ECk_Inventory_OperationResult_AddByDefinition InResult, int InAmountAdded, const TArray<FCk_Handle_Item>&in InItemsCreated)
    {
        LastAddResult = int32(InResult);
        ck::Trace(f"[InvGym Bounded] Add result: {InResult} added={InAmountAdded}");
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

    UFUNCTION()
    private void OnOverrideBounds(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        StopAuto();
        auto Typed = InPayload.Get(FCk_Message_InvGym_OverrideBounds);
        auto DataOnly = utils_inventory_data_only::DoCastChecked(Inventory);
        utils_inventory_data_only::Request_OverrideBounds(DataOnly, Typed.NewBound);
        ck::Trace(f"[InvGym Bounded] Bounds overridden to {Typed.NewBound}");
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
        auto Step = AutoStep % 11;
        auto PotionDef = inv_gym_items::Potion();
        auto DataOnly = utils_inventory_data_only::DoCastChecked(Inventory);

        if (Step <= 5 && PotionDef != nullptr)
        {
            auto Req = FCk_Request_Inventory_AddItemByDefinition(PotionDef, 1);
            Req.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            utils_inventory::Request_AddItemByDefinition(Inventory, Req, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
        }
        else if (Step == 6)
        {
            utils_inventory_data_only::Request_OverrideBounds(DataOnly, 10);
        }
        else if (Step <= 8 && PotionDef != nullptr)
        {
            auto Req = FCk_Request_Inventory_AddItemByDefinition(PotionDef, 1);
            Req.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
            utils_inventory::Request_AddItemByDefinition(Inventory, Req, FCk_Delegate_Inventory_OnOperationResult_AddByDefinition(this, n"OnAddResult"));
        }
        else if (Step == 9)
        {
            auto Items = utils_inventory::Get_Items(Inventory);
            for (auto Item : Items)
            {
                utils_inventory::Request_RemoveItem(Inventory, FCk_Request_Inventory_RemoveItem(Item), FCk_Delegate_Inventory_OnOperationResult_Remove());
            }
        }
        else if (Step == 10)
        {
            utils_inventory_data_only::Request_OverrideBounds(DataOnly, 5);
        }

        AutoStep++;
    }
}
