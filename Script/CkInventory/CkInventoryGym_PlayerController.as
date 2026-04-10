// Language=angelscript

//============================================================================
// INVENTORY GYM - PLAYER CONTROLLER
//============================================================================

class ACk_InventoryGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.DataOnlyUnbounded");
            Station.Height = 8.0f;
            Station.Title = FText::FromString("DATA-ONLY UNBOUNDED");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Unlimited-capacity data-only inventory."));
            Description.Add(FText::FromString("Tests add/remove/sort and OnItemsChanged signal."));
            Description.Add(FText::FromString("Console: Ck_GymInventory_AddPotion/AddArrow/RemoveFirst/SortAll"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.DataOnlyBounded");
            Station.Height = 8.0f;
            Station.Title = FText::FromString("DATA-ONLY BOUNDED");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Max 5 items; overfill returns Failed_NoSpaceAvailable."));
            Description.Add(FText::FromString("Demonstrates Request_OverrideBounds at runtime."));
            Description.Add(FText::FromString("Console: Ck_GymInventory_FillBounded / SetBounds"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.Spatial");
            Station.Height = 8.0f;
            Station.Title = FText::FromString("SPATIAL INVENTORY");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("8x6 grid with auto-placement and explicit coordinates."));
            Description.Add(FText::FromString("Uses Get_CanPlaceItemAt and Get_FirstAvailablePlacement."));
            Description.Add(FText::FromString("Console: Ck_GymInventory_AddSword / AddShieldAt x y"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.StackableTrait");
            Station.Height = 8.0f;
            Station.Title = FText::FromString("STACKABLE TRAIT");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Exercises Request_StackItems, Request_SplitStack."));
            Description.Add(FText::FromString("Binds OnStackCountChanged per item."));
            Description.Add(FText::FromString("Console: Ck_GymInventory_StackPotions / SplitStack n"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.TagsTrait");
            Station.Height = 8.0f;
            Station.Title = FText::FromString("TAGS TRAIT");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Runtime tag add/remove via Request_AddTag / Request_RemoveTag."));
            Description.Add(FText::FromString("Binds OnTagsChanged per item."));
            Description.Add(FText::FromString("Console: Ck_GymInventory_AddRareTag / RemoveRareTag"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Inventory.ShelfDesync");
            Station.Height = 8.0f;
            Station.Title = FText::FromString("SHELF LOOT/STOCK DESYNC");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Simulates in-game shelf stock/loot in rapid succession."));
            Description.Add(FText::FromString("Replicated inventories exercise the IFP network path."));
            Description.Add(FText::FromString("Invariant: total potion count stays constant."));
            Description.Add(FText::FromString("Console: Ck_GymInventory_ShelfStock / ShelfLoot / ShelfLoop n / ShelfReset"));
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
        ck::Trace("✅ Inventory Gym - All stations started");
    }

    //------------------------------------------------------------------------
    // STATION STARTUP
    //------------------------------------------------------------------------

    void Request_StartStation_DataOnlyUnbounded()
    {
        auto T = Get_StationTransform("Gym.Inventory.DataOnlyUnbounded");
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.DataOnlyUnbounded"),
            UCk_EntityScript_InvGym_DataOnlyUnbounded,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("✅ DataOnly Unbounded started"); }
        else { ck::Error("❌ Failed to spawn DataOnly Unbounded entity"); }
    }

    void Request_StartStation_DataOnlyBounded()
    {
        auto T = Get_StationTransform("Gym.Inventory.DataOnlyBounded");
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.DataOnlyBounded"),
            UCk_EntityScript_InvGym_DataOnlyBounded,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("✅ DataOnly Bounded started"); }
        else { ck::Error("❌ Failed to spawn DataOnly Bounded entity"); }
    }

    void Request_StartStation_Spatial()
    {
        auto T = Get_StationTransform("Gym.Inventory.Spatial");
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.Spatial"),
            UCk_EntityScript_InvGym_Spatial,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("✅ Spatial started"); }
        else { ck::Error("❌ Failed to spawn Spatial entity"); }
    }

    void Request_StartStation_StackableTrait()
    {
        auto T = Get_StationTransform("Gym.Inventory.StackableTrait");
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.StackableTrait"),
            UCk_EntityScript_InvGym_StackableTrait,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("✅ Stackable Trait started"); }
        else { ck::Error("❌ Failed to spawn Stackable Trait entity"); }
    }

    void Request_StartStation_TagsTrait()
    {
        auto T = Get_StationTransform("Gym.Inventory.TagsTrait");
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.TagsTrait"),
            UCk_EntityScript_InvGym_TagsTrait,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("✅ Tags Trait started"); }
        else { ck::Error("❌ Failed to spawn Tags Trait entity"); }
    }

    void Request_StartStation_ShelfDesync()
    {
        auto T = Get_StationTransform("Gym.Inventory.ShelfDesync");
        auto SpawnParams = FInventoryGymSpawnParams(T);
        auto Req = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Inventory.ShelfDesync"),
            UCk_EntityScript_InvGym_ShelfDesync,
            FInstancedStruct::Make(SpawnParams));
        if (ck::IsValid(Req)) { ck::Trace("✅ Shelf Desync started"); }
        else { ck::Error("❌ Failed to spawn Shelf Desync entity"); }
    }

    //------------------------------------------------------------------------
    // DATA-ONLY UNBOUNDED COMMANDS
    //------------------------------------------------------------------------

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

    UFUNCTION(Exec, DisplayName="Inventory Gym - Remove First Item")
    void Ck_GymInventory_RemoveFirst()
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

    UFUNCTION(Exec, DisplayName="Inventory Gym - Sort All")
    void Ck_GymInventory_SortAll()
    {
        auto Msg = FCk_Message_InvGym_SortInventory();
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_DataOnlyUnbounded");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    //------------------------------------------------------------------------
    // DATA-ONLY BOUNDED COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Inventory Gym - Fill Bounded")
    void Ck_GymInventory_FillBounded()
    {
        auto Msg = FCk_Message_InvGym_AddItemByDef("Potion", 1);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_DataOnlyBounded");
        for (auto i = 0; i < 8; i++)
        {
            for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
        }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Set Bounds")
    void Ck_GymInventory_SetBounds(int32 InNewBound = 10)
    {
        auto Msg = FCk_Message_InvGym_OverrideBounds(InNewBound);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_DataOnlyBounded");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    //------------------------------------------------------------------------
    // SPATIAL COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Inventory Gym - Add Sword (auto-place)")
    void Ck_GymInventory_AddSword()
    {
        auto Msg = FCk_Message_InvGym_AddItemByDef("Sword", 1);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_Spatial");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Add Shield At")
    void Ck_GymInventory_AddShieldAt(int32 InX = 0, int32 InY = 0)
    {
        auto Msg = FCk_Message_InvGym_AddItemAt("Shield", FIntPoint(InX, InY));
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_Spatial");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    //------------------------------------------------------------------------
    // STACKABLE TRAIT COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Inventory Gym - Stack First Two")
    void Ck_GymInventory_StackPotions()
    {
        auto Msg = FCk_Message_InvGym_StackFirstTwo();
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_StackableTrait");
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
    // TAGS TRAIT COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Inventory Gym - Add Rare Tag")
    void Ck_GymInventory_AddRareTag()
    {
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"Item.Rarity.Rare");
        auto Msg = FCk_Message_InvGym_AddTag(Tag);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_TagsTrait");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Remove Rare Tag")
    void Ck_GymInventory_RemoveRareTag()
    {
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"Item.Rarity.Rare");
        auto Msg = FCk_Message_InvGym_RemoveTag(Tag);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_TagsTrait");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    //------------------------------------------------------------------------
    // SHELF LOOT/STOCK DESYNC COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Inventory Gym - Shelf Stock (single)")
    void Ck_GymInventory_ShelfStock()
    {
        auto Msg = FCk_Message_InvGym_ShelfStock();
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_ShelfDesync");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Shelf Loot (single)")
    void Ck_GymInventory_ShelfLoot()
    {
        auto Msg = FCk_Message_InvGym_ShelfLoot();
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_ShelfDesync");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Shelf Start Pump")
    void Ck_GymInventory_ShelfStart()
    {
        auto Msg = FCk_Message_InvGym_ShelfLoop(1);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_ShelfDesync");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Shelf Stop Pump")
    void Ck_GymInventory_ShelfStop()
    {
        auto Msg = FCk_Message_InvGym_ShelfLoop(0);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_ShelfDesync");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Inventory Gym - Shelf Reset")
    void Ck_GymInventory_ShelfReset()
    {
        auto Msg = FCk_Message_InvGym_ShelfReset();
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_InvGym_ShelfDesync");
        for (auto E : Entities) { utils_messaging::Broadcast(E, Msg); }
    }

    //------------------------------------------------------------------------
    // AUTO MODE
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Inventory Gym - Toggle Auto Mode")
    void Ck_GymInventory_Auto()
    {
        auto Msg = FCk_Message_InvGym_AutoToggle();
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

    //------------------------------------------------------------------------
    // RESTART COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Inventory Gym - Restart All")
    void Ck_GymInventory_RestartAll()
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
}
