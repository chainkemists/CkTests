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

    int32 LastAddResult = -1;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
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

        DisplayText = f"{DisplayText}\n===== Commands =====\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_FillBounded\n";
        DisplayText = f"{DisplayText}Ck_GymInventory_SetBounds [n]\n";
        DisplayText = f"{DisplayText}(try overfilling to see Failed_NoSpaceAvailable)";

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString("DATA-ONLY BOUNDED (max 5)");
        Fragment.Description = FText::FromString(DisplayText);
    }

    UFUNCTION()
    private void OnAddItemByDef(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
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
        auto Typed = InPayload.Get(FCk_Message_InvGym_OverrideBounds);
        auto DataOnly = utils_inventory_data_only::DoCastChecked(Inventory);
        utils_inventory_data_only::Request_OverrideBounds(DataOnly, Typed.NewBound);
        ck::Trace(f"[InvGym Bounded] Bounds overridden to {Typed.NewBound}");
    }
}
