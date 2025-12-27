// Language=angelscript

//============================================================================
// INTEGER ATTRIBUTE GYM - PLAYER CONTROLLER
//============================================================================

class ACk_IntegerAttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Basic Integer Attributes Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.IntegerBasic");
            Station.Title = FText::FromString("INTEGER BASIC ATTRIBUTES");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Demonstrates basic integer attribute operations."));
            Description.Add(FText::FromString("Tests get/set operations for Health, Armor, and Experience."));
            Description.Add(FText::FromString("Console: Ck_GymInteger_SetHealth/SetArmor/SetExperience"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Min/Max/Current Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.IntegerMinMaxCurrent");
            Station.Title = FText::FromString("INTEGER MIN/MAX/CURRENT");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays all three attribute components independently."));
            Description.Add(FText::FromString("Shows how Min, Max, and Current values interact and update."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Modifiers Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.IntegerModifiers");
            Station.Title = FText::FromString("INTEGER MODIFIERS");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests attribute modifier system with add/remove operations."));
            Description.Add(FText::FromString("Demonstrates weapon and buff modifier stacking."));
            Description.Add(FText::FromString("Console: Ck_GymInteger_Add/Remove WeaponBonus/BuffBonus"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Clamping & Signals Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.IntegerClamping");
            Station.Title = FText::FromString("INTEGER CLAMPING & SIGNALS");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests automatic value clamping and signal callbacks."));
            Description.Add(FText::FromString("Monitors OnValueChanged, OnMinClamped, OnMaxClamped events."));
            Description.Add(FText::FromString("Console: Ck_GymInteger_TestBoundaries"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartBasicStation();
        Request_StartMinMaxCurrentStation();
        Request_StartModifiersStation();
        Request_StartClampingStation();
        ck::Trace("✅ Integer Attribute Gym - All stations started");
    }

    //------------------------------------------------------------------------
    // STATION STARTUP FUNCTIONS
    //------------------------------------------------------------------------

    void Request_StartBasicStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.IntegerBasic");
        auto SpawnParams = FIntegerGymSpawnParams(StationTransform, "Basic");

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.IntegerBasic"),
            UCk_EntityScript_IntegerGym_Basic,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("✅ Basic Integer Attributes station started");
        }
        else
        {
            ck::Error("❌ Failed to spawn Basic Integer Attributes entity");
        }
    }

    void Request_StartMinMaxCurrentStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.IntegerMinMaxCurrent");
        auto SpawnParams = FIntegerGymSpawnParams(StationTransform, "MinMaxCurrent");

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.IntegerMinMaxCurrent"),
            UCk_EntityScript_IntegerGym_MinMaxCurrent,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("✅ Min/Max/Current Components station started");
        }
        else
        {
            ck::Error("❌ Failed to spawn Min/Max/Current entity");
        }
    }

    void Request_StartModifiersStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.IntegerModifiers");
        auto SpawnParams = FIntegerGymSpawnParams(StationTransform, "Modifiers");

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.IntegerModifiers"),
            UCk_EntityScript_IntegerGym_Modifiers,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("✅ Integer Modifiers station started");
        }
        else
        {
            ck::Error("❌ Failed to spawn Modifiers entity");
        }
    }

    void Request_StartClampingStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.IntegerClamping");
        auto SpawnParams = FIntegerGymSpawnParams(StationTransform, "Clamping");

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.IntegerClamping"),
            UCk_EntityScript_IntegerGym_Clamping,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("✅ Clamping & Signals station started");
        }
        else
        {
            ck::Error("❌ Failed to spawn Clamping entity");
        }
    }

    //------------------------------------------------------------------------
    // BASIC STATION COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Integer Gym - Set Health")
    void Ck_GymInteger_SetHealth(int32 InValue)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Basic");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_SetHealth(InValue));
        }
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Set Armor")
    void Ck_GymInteger_SetArmor(int32 InValue)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Basic");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_SetArmor(InValue));
        }
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Set Experience")
    void Ck_GymInteger_SetExperience(int32 InValue)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Basic");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_SetExperience(InValue));
        }
    }

    //------------------------------------------------------------------------
    // MODIFIER STATION COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Integer Gym - Add Weapon Bonus")
    void Ck_GymInteger_AddWeaponBonus(int32 InDelta)
    {
        auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon");
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_AddModifier(ModifierTag, InDelta, ECk_MinMaxCurrent::Current));
        }
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Add Buff Bonus")
    void Ck_GymInteger_AddBuffBonus(int32 InDelta)
    {
        auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff");
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_AddModifier(ModifierTag, InDelta, ECk_MinMaxCurrent::Current));
        }
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Remove Weapon Bonus")
    void Ck_GymInteger_RemoveWeaponBonus()
    {
        auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon");
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_RemoveModifier(ModifierTag, ECk_MinMaxCurrent::Current));
        }
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Remove Buff Bonus")
    void Ck_GymInteger_RemoveBuffBonus()
    {
        auto ModifierTag = utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff");
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_RemoveModifier(ModifierTag, ECk_MinMaxCurrent::Current));
        }
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Clear All Modifiers")
    void Ck_GymInteger_ClearAllModifiers()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_ClearModifiers());
        }
    }

    //------------------------------------------------------------------------
    // CLAMPING STATION COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Integer Gym - Test Boundaries")
    void Ck_GymInteger_TestBoundaries()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Clamping");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_TestBoundaries());
        }
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Reset Clamping")
    void Ck_GymInteger_ResetClamping()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Clamping");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_ResetAttributes());
        }
    }

    //------------------------------------------------------------------------
    // GLOBAL COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Integer Gym - Reset All Stations")
    void Ck_GymInteger_ResetAll()
    {
        // Reset all stations
        auto AllTags = TArray<FName>();
        AllTags.Add(n"TAG_IntegerGym_Basic");
        AllTags.Add(n"TAG_IntegerGym_MinMaxCurrent");
        AllTags.Add(n"TAG_IntegerGym_Modifiers");
        AllTags.Add(n"TAG_IntegerGym_Clamping");

        for (auto Tag : AllTags)
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto Entity : Entities)
            {
                utils_messaging::Broadcast(Entity, FCk_Message_IntegerGym_ResetAttributes());
            }
        }

        ck::Trace("✅ All Integer Attribute stations reset");
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Restart Station (Basic)")
    void Ck_GymInteger_RestartBasic()
    {
        // Destroy existing entities
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Basic");
        for (auto Entity : Entities)
        {
            utils_entity_lifetime::Request_DestroyEntity(Entity);
        }

        // Restart the station
        Request_StartBasicStation();
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Restart Station (MinMaxCurrent)")
    void Ck_GymInteger_RestartMinMaxCurrent()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_MinMaxCurrent");
        for (auto Entity : Entities)
        {
            utils_entity_lifetime::Request_DestroyEntity(Entity);
        }
        Request_StartMinMaxCurrentStation();
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Restart Station (Modifiers)")
    void Ck_GymInteger_RestartModifiers()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Modifiers");
        for (auto Entity : Entities)
        {
            utils_entity_lifetime::Request_DestroyEntity(Entity);
        }
        Request_StartModifiersStation();
    }

    UFUNCTION(Exec, DisplayName="Integer Gym - Restart Station (Clamping)")
    void Ck_GymInteger_RestartClamping()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_IntegerGym_Clamping");
        for (auto Entity : Entities)
        {
            utils_entity_lifetime::Request_DestroyEntity(Entity);
        }
        Request_StartClampingStation();
    }
}