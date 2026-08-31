// Language=angelscript

//============================================================================
// INVENTORY GYM - PLAYER CONTROLLER
//============================================================================

class ACk_InventoryGym_PlayerController : ACk_Gym_Base_PlayerController
{
    // Preset-ring position for the bounded-capacity row. It reports its STEP, not a value, because
    // the bounded station's own auto sequence calls Request_OverrideBounds(10)/(5) behind the panel's
    // back - a mirrored number would read 20 while the inventory was back at 5.
    private int32 _BoundsPresetIndex = -1;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.DataOnlyUnbounded");
            Station.AutoSize = true;
            Station.Title = FText::FromString("DATA-ONLY UNBOUNDED");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Unlimited-capacity data-only inventory."));
            Description.Add(FText::FromString("Tests add/remove/sort and OnItemsChanged."));
            Description.Add(FText::FromString("Starts in auto mode."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.DataOnlyBounded");
            Station.AutoSize = true;
            Station.Title = FText::FromString("DATA-ONLY BOUNDED");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Bounded inventory (max 5)."));
            Description.Add(FText::FromString("Demonstrates Request_OverrideBounds and rejection."));
            Description.Add(FText::FromString("Starts in auto mode."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.Spatial");
            Station.AutoSize = true;
            Station.Title = FText::FromString("SPATIAL INVENTORY");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("8x6 grid with auto-placement, explicit coords,"));
            Description.Add(FText::FromString("and multi-cell items (3x1). Starts in auto mode."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.StackableTrait");
            Station.AutoSize = true;
            Station.Title = FText::FromString("STACKABLE TRAIT");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Request_StackItems, Request_SplitStack."));
            Description.Add(FText::FromString("Binds OnStackCountChanged. Starts in auto mode."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.TagsTrait");
            Station.AutoSize = true;
            Station.Title = FText::FromString("TAGS TRAIT");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Runtime tag add/remove via Request_AddTag /"));
            Description.Add(FText::FromString("Request_RemoveTag. Binds OnTagsChanged."));
            Description.Add(FText::FromString("Starts in auto mode."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.ShelfDesync");
            Station.AutoSize = true;
            Station.Title = FText::FromString("SHELF LOOT/STOCK");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Rapid stock/loot pump simulating in-game"));
            Description.Add(FText::FromString("shelf operations. Watch total for drift."));
            Description.Add(FText::FromString("Starts in auto mode."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartStation_DataOnlyUnbounded();
        Request_StartStation_DataOnlyBounded();
        Request_StartStation_Spatial();
        Request_StartStation_StackableTrait();
        Request_StartStation_TagsTrait();
        Request_StartStation_ShelfDesync();
        ck::Trace("[OK] Inventory Gym - All stations started");
    }

    //------------------------------------------------------------------------
    // STATION STARTUP
    //------------------------------------------------------------------------

    void Request_StartStation_DataOnlyUnbounded()
    {
        auto T = Get_StationAnchorTransform("Gym.Inventory.DataOnlyUnbounded", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.DataOnlyUnbounded"),
            UCk_EntityScript_InvGym_DataOnlyUnbounded,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("[OK] DataOnly Unbounded started"); }
        else { ck::Error("[FAIL] Failed to spawn DataOnly Unbounded entity"); }
    }

    void Request_StartStation_DataOnlyBounded()
    {
        auto T = Get_StationAnchorTransform("Gym.Inventory.DataOnlyBounded", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.DataOnlyBounded"),
            UCk_EntityScript_InvGym_DataOnlyBounded,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("[OK] DataOnly Bounded started"); }
        else { ck::Error("[FAIL] Failed to spawn DataOnly Bounded entity"); }
    }

    void Request_StartStation_Spatial()
    {
        auto T = Get_StationAnchorTransform("Gym.Inventory.Spatial", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.Spatial"),
            UCk_EntityScript_InvGym_Spatial,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("[OK] Spatial started"); }
        else { ck::Error("[FAIL] Failed to spawn Spatial entity"); }
    }

    void Request_StartStation_StackableTrait()
    {
        auto T = Get_StationAnchorTransform("Gym.Inventory.StackableTrait", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.StackableTrait"),
            UCk_EntityScript_InvGym_StackableTrait,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("[OK] Stackable Trait started"); }
        else { ck::Error("[FAIL] Failed to spawn Stackable Trait entity"); }
    }

    void Request_StartStation_TagsTrait()
    {
        auto T = Get_StationAnchorTransform("Gym.Inventory.TagsTrait", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.TagsTrait"),
            UCk_EntityScript_InvGym_TagsTrait,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("[OK] Tags Trait started"); }
        else { ck::Error("[FAIL] Failed to spawn Tags Trait entity"); }
    }

    void Request_StartStation_ShelfDesync()
    {
        auto T = Get_StationAnchorTransform("Gym.Inventory.ShelfDesync", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.ShelfDesync"),
            UCk_EntityScript_InvGym_ShelfDesync,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("[OK] Shelf Desync started"); }
        else { ck::Error("[FAIL] Failed to spawn Shelf Desync entity"); }
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Every keyed row fires at its command's own default count or coordinate - the values the gym's
    // placards talk about. The bound is a preset ring instead, since its three interesting values are
    // exactly the ones the bounded station demonstrates. Four commands genuinely need a number, a pair
    // or a direction the panel cannot express; they stay on the console and get a Status row that
    // names them.
    //
    // The six per-station auto-drive rows are Actions, not Toggles: every station calls
    // gym_auto::StopAuto the moment any manual row fires, so a mirrored bool would read ON while the
    // station had already stopped. An Action that re-arms is the only honest shape. Their letters
    // carry no mnemonic - six stations exhaust the free initials.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "INVENTORY";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("ITEMS"));
        Rows.Add(CkGym_Control::Numbered(0, "Add a potion", false));
        Rows.Add(CkGym_Control::Numbered(1, "Add an arrow", false));
        Rows.Add(CkGym_Control::Numbered(2, "Add a sword", false));
        Rows.Add(CkGym_Control::Numbered(3, "Add a shield at 0,0", false));
        Rows.Add(CkGym_Control::Numbered(4, "Remove the first item", false));
        Rows.Add(CkGym_Control::Numbered(5, "Stack the potions", false));
        Rows.Add(CkGym_Control::Numbered(6, "Split one off a stack", false));
        Rows.Add(CkGym_Control::Numbered(7, "Sort everything", false));
        Rows.Add(CkGym_Control::Numbered(8, "Fill the bounded inventory", false));

        Rows.Add(CkGym_Control::Header("TAGS"));
        Rows.Add(CkGym_Control::Action(EKeys::T, "T", "Add the RARE tag"));
        Rows.Add(CkGym_Control::Action(EKeys::Y, "Y", "Remove the RARE tag"));

        Rows.Add(CkGym_Control::Header("SHELF"));
        Rows.Add(CkGym_Control::Action(EKeys::O, "O", "Stock"));
        Rows.Add(CkGym_Control::Action(EKeys::L, "L", "Loot"));
        Rows.Add(CkGym_Control::Action(EKeys::G, "G", "Start"));
        Rows.Add(CkGym_Control::Action(EKeys::X, "X", "Stop"));
        Rows.Add(CkGym_Control::Action(EKeys::Z, "Z", "Reset"));

        Rows.Add(CkGym_Control::Header("RUN"));
        Rows.Add(CkGym_Control::Action(EKeys::U, "U", "Auto-drive every station"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Restart everything"));

        Rows.Add(CkGym_Control::Header("BOUNDED CAPACITY"));
        Rows.Add(CkGym_Control::Cycle(EKeys::B, "B", "Override the bound", DoGet_BoundsPresetLabel()));

        Rows.Add(CkGym_Control::Header("RE-ARM AUTO-DRIVE (one station)"));
        Rows.Add(CkGym_Control::Action(EKeys::F, "F", "Data-only unbounded"));
        Rows.Add(CkGym_Control::Action(EKeys::I, "I", "Data-only bounded"));
        Rows.Add(CkGym_Control::Action(EKeys::J, "J", "Spatial"));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Stackable trait"));
        Rows.Add(CkGym_Control::Action(EKeys::M, "M", "Tags trait"));
        Rows.Add(CkGym_Control::Action(EKeys::N, "N", "Shelf loot/stock"));
        Rows.Add(CkGym_Control::Action(EKeys::Y, "Y", "Stop auto-drive everywhere"));

        Rows.Add(CkGym_Control::Header("CONSOLE (free-range input the panel cannot express)"));
        Rows.Add(CkGym_Control::Status("Shield at a coordinate", "Ck_GymInventory_AddShieldAt X Y"));
        Rows.Add(CkGym_Control::Status("Split N off a stack", "Ck_GymInventory_SplitStack N"));
        Rows.Add(CkGym_Control::Status("Add N of an item", "Ck_GymInventory_AddPotion N - Ck_GymInventory_AddArrow N"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Rows 0, 10, 13, 19, 22, 24 and 31 are headers, which hold no key and never arrive here.
        if (InRowIndex == 1) { Ck_GymInventory_AddPotion(1); }
        else if (InRowIndex == 2) { Ck_GymInventory_AddArrow(1); }
        else if (InRowIndex == 3) { DoAddSword(); }
        else if (InRowIndex == 4) { Ck_GymInventory_AddShieldAt(0, 0); }
        else if (InRowIndex == 5) { DoRemoveFirst(); }
        else if (InRowIndex == 6) { DoStackPotions(); }
        else if (InRowIndex == 7) { Ck_GymInventory_SplitStack(1); }
        else if (InRowIndex == 8) { DoSortAll(); }
        else if (InRowIndex == 9) { DoFillBounded(); }
        else if (InRowIndex == 11) { DoSetRareTag(true); }
        else if (InRowIndex == 12) { DoSetRareTag(false); }
        else if (InRowIndex == 14) { DoBroadcastToShelf(FInstancedStruct::Make(FCk_Message_InvGym_ShelfStock())); }
        else if (InRowIndex == 15) { DoBroadcastToShelf(FInstancedStruct::Make(FCk_Message_InvGym_ShelfLoot())); }
        else if (InRowIndex == 16) { DoBroadcastToShelf(FInstancedStruct::Make(FCk_Message_InvGym_ShelfLoop(1))); }
        else if (InRowIndex == 17) { DoBroadcastToShelf(FInstancedStruct::Make(FCk_Message_InvGym_ShelfLoop(0))); }
        else if (InRowIndex == 18) { DoBroadcastToShelf(FInstancedStruct::Make(FCk_Message_InvGym_ShelfReset())); }
        else if (InRowIndex == 20) { BroadcastAutoToAll(true); }
        else if (InRowIndex == 21) { DoRestartAll(); }
        else if (InRowIndex == 23) { DoCycleBoundsPreset(); }
        else if (InRowIndex == 25) { BroadcastAutoToTag(n"TAG_InvGym_DataOnlyUnbounded", true); }
        else if (InRowIndex == 26) { BroadcastAutoToTag(n"TAG_InvGym_DataOnlyBounded", true); }
        else if (InRowIndex == 27) { BroadcastAutoToTag(n"TAG_InvGym_Spatial", true); }
        else if (InRowIndex == 28) { BroadcastAutoToTag(n"TAG_InvGym_StackableTrait", true); }
        else if (InRowIndex == 29) { BroadcastAutoToTag(n"TAG_InvGym_TagsTrait", true); }
        else if (InRowIndex == 30) { BroadcastAutoToTag(n"TAG_InvGym_ShelfDesync", true); }
        else if (InRowIndex == 31) { BroadcastAutoToAll(false); }
    }

    // 5 is the bound the station is authored with, 10 is what its auto sequence overrides to, and 20
    // is the headroom step that makes a rejection stop happening.
    private FString DoGet_BoundsPresetLabel()
    {
        return _BoundsPresetIndex < 0 ? "(5 / 10 / 20)" : f"step {_BoundsPresetIndex + 1}";
    }

    private void DoCycleBoundsPreset()
    {
        _BoundsPresetIndex = (_BoundsPresetIndex + 1) % 3;

        auto Values = TArray<int32>();
        Values.Add(5); Values.Add(10); Values.Add(20);

        auto Msg = FCk_Message_InvGym_OverrideBounds(Values[_BoundsPresetIndex]);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_DataOnlyBounded");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Add Potion")
    void Ck_GymInventory_AddPotion(int32 InCount = 1)
    {
        auto Msg = FCk_Message_InvGym_AddItemByDef("Potion", InCount);
        auto Unbounded = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_DataOnlyUnbounded");
        for (auto E : Unbounded) { utils_messaging::Broadcast(E, Msg); }
        auto Stackable = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_StackableTrait");
        for (auto E : Stackable) { utils_messaging::Broadcast(E, Msg); }
        auto TagsEntities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_TagsTrait");
        for (auto E : TagsEntities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Add Arrow")
    void Ck_GymInventory_AddArrow(int32 InCount = 1)
    {
        auto Msg = FCk_Message_InvGym_AddItemByDef("Arrow", InCount);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_DataOnlyUnbounded");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Add Shield At")
    void Ck_GymInventory_AddShieldAt(int32 InX = 0, int32 InY = 0)
    {
        auto Msg = FCk_Message_InvGym_AddItemAt("Shield", FIntPoint(InX, InY));
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_Spatial");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Split Stack")
    void Ck_GymInventory_SplitStack(int32 InCount = 1)
    {
        auto Msg = FCk_Message_InvGym_SplitFirst(InCount);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_StackableTrait");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    //------------------------------------------------------------------------
    // PANEL ACTIONS
    //------------------------------------------------------------------------

    private void DoAddSword()
    {
        auto Msg = FCk_Message_InvGym_AddItemByDef("Sword", 1);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_Spatial");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    private void DoRemoveFirst()
    {
        auto Msg = FCk_Message_InvGym_RemoveFirst();
        auto StationTags = TArray<FName>();
        StationTags.Add(n"TAG_InvGym_DataOnlyUnbounded");
        StationTags.Add(n"TAG_InvGym_DataOnlyBounded");
        StationTags.Add(n"TAG_InvGym_Spatial");
        for (auto Tag : StationTags)
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
        }
    }

    private void DoStackPotions()
    {
        auto Msg = FCk_Message_InvGym_StackFirstTwo();
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_StackableTrait");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    private void DoSortAll()
    {
        auto Msg = FCk_Message_InvGym_SortInventory();
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_DataOnlyUnbounded");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    private void DoFillBounded()
    {
        auto Msg = FCk_Message_InvGym_AddItemByDef("Potion", 1);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_DataOnlyBounded");
        for (auto i = 0; i < 8; i++)
        {
            for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
        }
    }

    private void DoSetRareTag(bool InAdd)
    {
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"Item.Rarity.Rare");
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_TagsTrait");

        if (InAdd)
        {
            auto AddMsg = FCk_Message_InvGym_AddTag(Tag);
            for (auto E : Entities) { utils_messaging::Broadcast(E, AddMsg); }
            return;
        }

        auto RemoveMsg = FCk_Message_InvGym_RemoveTag(Tag);
        for (auto E : Entities) { utils_messaging::Broadcast(E, RemoveMsg); }
    }

    private void DoBroadcastToShelf(FInstancedStruct InMessage)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_ShelfDesync");
        for (auto E : Entities) { utils_messaging::Broadcast(E, InMessage); }
    }

    private void DoRestartAll()
    {
        auto AllTags = TArray<FName>();
        AllTags.Add(n"TAG_InvGym_DataOnlyUnbounded");
        AllTags.Add(n"TAG_InvGym_DataOnlyBounded");
        AllTags.Add(n"TAG_InvGym_Spatial");
        AllTags.Add(n"TAG_InvGym_StackableTrait");
        AllTags.Add(n"TAG_InvGym_TagsTrait");
        AllTags.Add(n"TAG_InvGym_ShelfDesync");

        for (auto Tag : AllTags)
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto Entity : Entities)
            {
                utils_entity_lifetime::Request_DestroyEntity(Entity);
            }
        }

        Request_StartGym();
    }

    //------------------------------------------------------------------------
    // AUTO MODE
    //------------------------------------------------------------------------

    private void BroadcastAutoToAll(bool InEnabled)
    {
        auto Msg = FCk_Message_Gym_AutoSet(InEnabled);
        auto AllTags = TArray<FName>();
        AllTags.Add(n"TAG_InvGym_DataOnlyUnbounded");
        AllTags.Add(n"TAG_InvGym_DataOnlyBounded");
        AllTags.Add(n"TAG_InvGym_Spatial");
        AllTags.Add(n"TAG_InvGym_StackableTrait");
        AllTags.Add(n"TAG_InvGym_TagsTrait");
        AllTags.Add(n"TAG_InvGym_ShelfDesync");

        for (auto Tag : AllTags)
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
        }
    }

    private void BroadcastAutoToTag(FName InTag, bool InEnabled)
    {
        auto Msg = FCk_Message_Gym_AutoSet(InEnabled);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

}
