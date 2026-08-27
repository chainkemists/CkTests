// Language=angelscript

//============================================================================
// INVENTORY GYM - SHELF LOOT/STOCK DESYNC REPRO ENTITY SCRIPT
//============================================================================
//
// Simulates the in-game shelf operations that caused desyncs with IFP.
//
// Two inventories (Player + Shelf) start with 10 potions on the player.
// A pump timer continuously runs stock+loot cycles at configurable speed:
//
//   STOCK: split 1 off player stack -> transfer to shelf (ForceNewItem)
//   LOOT:  first shelf potion -> transfer to player (PreferStacking)
//
// The display shows live potion counts for both inventories. The user
// watches the total -- if it drifts from 10 and stays there, that's the
// desync bug. Transient mid-frame blips are expected and harmless.
//
// Commands:
//   ShelfStart / ShelfStop  -- toggle the continuous pump
//   ShelfSpeed [ms]         -- set pump interval (lower = faster spam)
//   ShelfStock / ShelfLoot  -- single manual operation
//   ShelfReset              -- clear everything and re-seed
//
//============================================================================

class UCk_EntityScript_InvGym_ShelfDesync : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_Inventory_DataOnly PlayerInv;
    FCk_Handle_Inventory_DataOnly ShelfInv;
    FCk_Handle_Timer PumpTimer;
    bool PumpRunning = true;
    int32 AutoStep = 0;

    int32 InitialPotionCount = 10;
    int32 StockOps = 0;
    int32 LootOps = 0;

    // Alternate stock/loot each pump tick so they interleave like real gameplay.
    bool NextOpIsStock = true;

    FCkGym_AutoConfig AutoConfig;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, n"TAG_InvGym_ShelfDesync");

        // Display timer (always running)
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // Player inventory (unbounded data-only)
        auto PlayerParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.Backpack"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        PlayerInv = utils_inventory_data_only::Add(InHandle, PlayerParams, ECk_Replication::DoesNotReplicate);

        // Shelf inventory (unbounded data-only)
        auto ShelfParams = utils_inventory_data_only::Make_Params(
            utils_gameplay_tag::ResolveGameplayTag(n"Inventory.Equipment"),
            FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic(),
            FCk_Delegate_Inventory_CustomCanStackItems_Dynamic());
        ShelfInv = utils_inventory_data_only::Add(InHandle, ShelfParams, ECk_Replication::DoesNotReplicate);

        // Seed player with initial potion stack
        auto PotionDef = inv_gym_items::Potion();
        if (PotionDef != nullptr)
        {
            auto SeedReq = FCk_Request_Inventory_AddItemByDefinition(PotionDef, InitialPotionCount);
            SeedReq.Set_Policy(ECk_Inventory_AddPolicy::PreferStacking);
            PlayerInv.Request_AddItemByDefinition(SeedReq,
                FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_ShelfStock, FCk_Delegate_Messaging_OnBroadcast(this, n"OnStock"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_ShelfLoot,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnLoot"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_ShelfLoop,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnLoop"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_InvGym_ShelfReset, FCk_Delegate_Messaging_OnBroadcast(this, n"OnReset"));

        PumpTimer = gym_auto::Setup(InHandle, this, FCk_Time(0.05f), n"PumpTick");

        AutoConfig.TotalSteps = 2;
        AutoConfig.Description = "Rapid stock/loot pump simulating in-game\nshelf operations. Watch total for drift.";
        AutoConfig.GlobalAutoCommand = "Ck_GymInventory_Auto [0/1]";
        AutoConfig.PerStationAutoCommand = "Ck_GymInventory_AutoShelf";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Alternating stock/loot pump", 0, 1));
        AutoConfig.ManualCommands.Add("Ck_GymInventory_ShelfStart");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_ShelfStop");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_ShelfStock");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_ShelfLoot");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_ShelfReset");
        AutoConfig.ManualCommands.Add("Ck_GymInventory_RestartAll");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    //------------------------------------------------------------------------
    // QUERIES
    //------------------------------------------------------------------------

    int32 Get_PlayerPotionCount()
    {
        if (ck::IsValid(PlayerInv) == false) { return 0; }
        auto Items = PlayerInv.Get_Items();
        auto Total = 0;
        for (auto Item : Items)
        {
            if (utils_item::Get_Definition(Item) != inv_gym_items::Potion()) { continue; }
            if (utils_item_trait_stackable::Get_IsStackable(Item))
            {
                Total += utils_item_trait_stackable::Get_StackCount(Item);
            }
            else
            {
                Total += 1;
            }
        }
        return Total;
    }

    int32 Get_ShelfPotionCount()
    {
        if (ck::IsValid(ShelfInv) == false) { return 0; }
        auto Items = ShelfInv.Get_Items();
        auto Total = 0;
        for (auto Item : Items)
        {
            if (utils_item::Get_Definition(Item) != inv_gym_items::Potion()) { continue; }
            if (utils_item_trait_stackable::Get_IsStackable(Item))
            {
                Total += utils_item_trait_stackable::Get_StackCount(Item);
            }
            else
            {
                Total += 1;
            }
        }
        return Total;
    }

    FCk_Handle_Item Get_PlayerPotionStack()
    {
        auto Items = PlayerInv.Get_Items();
        for (auto Item : Items)
        {
            if (utils_item::Get_Definition(Item) == inv_gym_items::Potion()) { return Item; }
        }
        return utils_item::Get_InvalidHandle();
    }

    //------------------------------------------------------------------------
    // PUMP -- continuous stock/loot alternation
    //------------------------------------------------------------------------

    UFUNCTION()
    private void PumpTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (NextOpIsStock)
        {
            Do_Stock();
        }
        else
        {
            Do_Loot();
        }
        NextOpIsStock = !NextOpIsStock;
        AutoStep++;
    }

    //------------------------------------------------------------------------
    // STOCK: transfer 1 from player stack to shelf as a new item (single atomic request)
    //------------------------------------------------------------------------

    void Do_Stock()
    {
        auto PlayerStack = Get_PlayerPotionStack();
        if (ck::IsValid(PlayerStack) == false) { return; }

        // Single TransferItem with Count=1, ForceNewItem -- the processor handles
        // the stack decrement + new item creation in one pass, no intermediate state.
        auto TransferReq = FCk_Request_Inventory_TransferItem_ToDataOnly(PlayerStack, ShelfInv);
        TransferReq.Set_Count(1);
        TransferReq.Set_Policy(ECk_Inventory_AddPolicy::ForceNewItem);
        PlayerInv.Request_TransferItem_ToDataOnly(TransferReq,
            FCk_Delegate_Inventory_OnOperationResult_Transfer());

        StockOps++;
    }

    //------------------------------------------------------------------------
    // LOOT: take first shelf potion, merge into player stack
    //------------------------------------------------------------------------

    void Do_Loot()
    {
        auto ShelfItems = ShelfInv.Get_Items();
        FCk_Handle_Item ShelfPotion = utils_item::Get_InvalidHandle();
        for (auto Item : ShelfItems)
        {
            if (utils_item::Get_Definition(Item) == inv_gym_items::Potion())
            {
                ShelfPotion = Item;
                break;
            }
        }

        if (ck::IsValid(ShelfPotion) == false) { return; }

        auto TransferReq = FCk_Request_Inventory_TransferItem_ToDataOnly(ShelfPotion, PlayerInv);
        TransferReq.Set_Policy(ECk_Inventory_AddPolicy::PreferStacking);
        ShelfInv.Request_TransferItem_ToDataOnly(TransferReq,
            FCk_Delegate_Inventory_OnOperationResult_Transfer());

        LootOps++;
    }

    //------------------------------------------------------------------------
    // MESSAGE HANDLERS
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnStock(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(PumpTimer, PumpRunning);
        Do_Stock();
    }

    UFUNCTION()
    private void OnLoot(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(PumpTimer, PumpRunning);
        Do_Loot();
    }

    UFUNCTION()
    private void OnLoop(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_InvGym_ShelfLoop);

        if (Typed.Iterations == 0)
        {
            utils_timer::Request_Pause(PumpTimer);
            PumpRunning = false;
            ck::Trace("[InvGym Shelf] Pump stopped");
        }
        else
        {
            utils_timer::Request_Resume(PumpTimer);
            PumpRunning = true;
            ck::Trace("[InvGym Shelf] Pump started (50ms interval -- alternating stock/loot)");
        }
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, PumpTimer, PumpRunning);
    }

    UFUNCTION()
    private void OnReset(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        utils_timer::Request_Pause(PumpTimer);
        PumpRunning = false;
        NextOpIsStock = true;

        auto PlayerItems = PlayerInv.Get_Items();
        for (auto Item : PlayerItems)
        {
            PlayerInv.Request_RemoveItem(FCk_Request_Inventory_RemoveItem(Item),
                FCk_Delegate_Inventory_OnOperationResult_Remove());
        }
        auto ShelfItems = ShelfInv.Get_Items();
        for (auto Item : ShelfItems)
        {
            ShelfInv.Request_RemoveItem(FCk_Request_Inventory_RemoveItem(Item),
                FCk_Delegate_Inventory_OnOperationResult_Remove());
        }

        auto PotionDef = inv_gym_items::Potion();
        if (PotionDef != nullptr)
        {
            auto SeedReq = FCk_Request_Inventory_AddItemByDefinition(PotionDef, InitialPotionCount);
            SeedReq.Set_Policy(ECk_Inventory_AddPolicy::PreferStacking);
            PlayerInv.Request_AddItemByDefinition(SeedReq,
                FCk_Delegate_Inventory_OnOperationResult_AddByDefinition());
        }

        StockOps = 0;
        LootOps = 0;
        ck::Trace("[InvGym Shelf] Reset -- player re-seeded, shelf empty, pump stopped");
    }

    //------------------------------------------------------------------------
    // DISPLAY
    //------------------------------------------------------------------------

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DisplayStats();
    }

    void DisplayStats()
    {
        auto SelfEntity = ck::ToEntity(this);
        if (ck::IsValid(PlayerInv) == false || ck::IsValid(ShelfInv) == false) { return; }

        auto PlayerPotions = Get_PlayerPotionCount();
        auto ShelfPotions = Get_ShelfPotionCount();
        auto Total = PlayerPotions + ShelfPotions;
        auto Delta = Total - InitialPotionCount;

        auto ModeStr = PumpRunning ? "[AUTO]" : "[MANUAL]";

        auto DisplayText = gym_auto::FormatHeader(AutoConfig, PumpRunning);
        DisplayText = f"{DisplayText}Expected total: {InitialPotionCount}\n";
        DisplayText = f"{DisplayText}Player: {PlayerPotions}   Shelf: {ShelfPotions}\n";
        DisplayText = f"{DisplayText}TOTAL: {Total}";
        if (Delta != 0) { DisplayText = f"{DisplayText}  [FAIL] DRIFT {Delta}"; }
        DisplayText = f"{DisplayText}\n\n";

        DisplayText = f"{DisplayText}Stock ops: {StockOps}   Loot ops: {LootOps}\n\n";

        DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, PumpRunning);

        auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
        auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(f"SHELF LOOT/STOCK {ModeStr}");
        Fragment.Description = FText::FromString(DisplayText);
    }
}
