//============================================================================
// BYTE ATTRIBUTE GYM - PLAYER CONTROLLER & GAME MODE
//============================================================================

class ACk_ByteAttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Byte Clamping Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.ByteClamping");
            Station.Title = FText::FromString("BYTE CLAMPING");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Demonstrates automatic value clamping within min/max boundaries."));
            Description.Add(FText::FromString("Watch attributes cycle and clamp when exceeding their limits."));
            Description.Add(FText::FromString("Armor: 0-200 | Stamina: 50-255 | Health: 0-100"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Byte Modifiers Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.ByteModifiers");
            Station.Title = FText::FromString("BYTE MODIFIERS");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests attribute modifier system with add/multiply operations."));
            Description.Add(FText::FromString("See how modifiers stack and affect final attribute values."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Byte MinMaxCurrent Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.ByteMinMaxCurrent");
            Station.Title = FText::FromString("BYTE MIN/MAX/CURRENT");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays all three attribute values: Min, Max, and Current."));
            Description.Add(FText::FromString("Watch how they update independently and interact."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Byte Multiple Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.ByteMultiple");
            Station.Title = FText::FromString("BYTE MULTIPLE ATTRIBUTES");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Entity with multiple byte attributes working simultaneously."));
            Description.Add(FText::FromString("Tests attribute independence and concurrent updates."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Byte Values Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.ByteValues");
            Station.Title = FText::FromString("BYTE VALUES");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Basic attribute value operations and display."));
            Description.Add(FText::FromString("Tests get/set operations and value updates."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Byte Signals Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.ByteSignals");
            Station.Title = FText::FromString("BYTE SIGNALS");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests attribute signal system and callbacks."));
            Description.Add(FText::FromString("Monitors OnValueChanged, OnMinClamped, OnMaxClamped events."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartByteClamping();
        Request_StartByteModifiers();
        Request_StartByteMinMaxCurrent();
        Request_StartByteMultiple();
        Request_StartByteValues();
        Request_StartByteSignals();
    }

    void Request_StartByteClamping()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.ByteClamping", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteClamping"),
            UCk_EntityScript_AttributeGym_ByteClamping,
            FInstancedStruct::Make(SpawnParams)
        );
	}

    void Request_StartByteModifiers()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.ByteModifiers", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteModifiers"),
            UCk_EntityScript_AttributeGym_ByteModifiers,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteMinMaxCurrent()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.ByteMinMaxCurrent", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteMinMaxCurrent"),
            UCk_EntityScript_AttributeGym_ByteMinMaxCurrent,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteMultiple()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.ByteMultiple", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteMultiple"),
            UCk_EntityScript_AttributeGym_ByteMultiple,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteValues()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.ByteValues", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteValues"),
            UCk_EntityScript_AttributeGym_ByteValues,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteSignals()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.ByteSignals", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteSignals"),
            UCk_EntityScript_AttributeGym_ByteSignals,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS — Values station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Byte Gym - Add Modifier")
    void Ck_GymByte_AddModifier()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteValues"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_AddModifier()); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Clear Modifiers")
    void Ck_GymByte_ClearModifiers()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteValues"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_ClearModifiers()); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS — Modifiers station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Byte Gym - Add Modifier (Modifiers)")
    void Ck_GymByte_AddModifierByte()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteModifiers"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_AddModifier()); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Clear Modifiers (Modifiers)")
    void Ck_GymByte_ClearModifiersByte()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteModifiers"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_ClearModifiers()); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS — MinMaxCurrent station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Byte Gym - Set Min")
    void Ck_GymByte_SetMin(uint8 InValue = 20)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteMinMaxCurrent"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_SetValue(InValue, ECk_MinMaxCurrent::Min)); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Set Max")
    void Ck_GymByte_SetMax(uint8 InValue = 180)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteMinMaxCurrent"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_SetValue(InValue, ECk_MinMaxCurrent::Max)); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Set Current")
    void Ck_GymByte_SetCurrent(uint8 InValue = 100)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteMinMaxCurrent"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_SetValue(InValue, ECk_MinMaxCurrent::Current)); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS — Multiple station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Byte Gym - Add Batch")
    void Ck_GymByte_AddBatch()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteMultiple"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_AddBatch()); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Clear Batch")
    void Ck_GymByte_ClearBatch()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteMultiple"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_ClearBatch()); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS — Signals station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Byte Gym - Set Signal Value")
    void Ck_GymByte_SetSignalValue(uint8 InValue = 150)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteSignals"))
        { utils_messaging::Broadcast(E, FCk_Message_ByteGym_SetValue(InValue)); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS — Clamping station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Byte Gym - Test Boundaries")
    void Ck_GymByte_TestBoundaries()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteClamping");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_TestBoundaries());
        }
    }

    // Auto commands
    UFUNCTION(Exec, DisplayName="Byte Gym - Auto")
    void Ck_GymByte_Auto(int32 InEnabled = 1)
    {
        auto AllTags = TArray<FName>();
        AllTags.Add(n"TAG_AttributeGym_ByteClamping");
        AllTags.Add(n"TAG_AttributeGym_ByteModifiers");
        AllTags.Add(n"TAG_AttributeGym_ByteValues");
        AllTags.Add(n"TAG_AttributeGym_ByteMinMaxCurrent");
        AllTags.Add(n"TAG_AttributeGym_ByteMultiple");
        AllTags.Add(n"TAG_AttributeGym_ByteSignals");

        for (auto Tag : AllTags)
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto Entity : Entities)
            {
                utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(InEnabled != 0));
            }
        }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Auto Values")
    void Ck_GymByte_AutoValues()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteValues");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Auto Modifiers")
    void Ck_GymByte_AutoModifiers()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteModifiers");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Auto MinMaxCurrent")
    void Ck_GymByte_AutoMinMaxCurrent()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteMinMaxCurrent");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Auto Multiple")
    void Ck_GymByte_AutoMultiple()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteMultiple");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Auto Signals")
    void Ck_GymByte_AutoSignals()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteSignals");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
    }

    UFUNCTION(Exec, DisplayName="Byte Gym - Auto Clamping")
    void Ck_GymByte_AutoClamping()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteClamping");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, FCk_Message_Gym_AutoSet(true)); }
    }

    // Global commands
    UFUNCTION(Exec, DisplayName="Byte Gym - Reset All")
    void Ck_GymByte_ResetAll()
    {
        auto AllTags = TArray<FName>();
        AllTags.Add(n"TAG_AttributeGym_ByteClamping");
        AllTags.Add(n"TAG_AttributeGym_ByteModifiers");
        AllTags.Add(n"TAG_AttributeGym_ByteValues");
        AllTags.Add(n"TAG_AttributeGym_ByteMinMaxCurrent");
        AllTags.Add(n"TAG_AttributeGym_ByteMultiple");
        AllTags.Add(n"TAG_AttributeGym_ByteSignals");

        for (auto Tag : AllTags)
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto Entity : Entities)
            {
                utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_ResetAttributes());
            }
        }
    }
}

//============================================================================
// GAME MODE
//============================================================================

class ACk_ByteAttributeGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_ByteAttributeGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}