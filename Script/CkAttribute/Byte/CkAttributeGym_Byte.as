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
            Station.Height = 8.0f;
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
            Station.Height = 8.0f;
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
            Station.Height = 8.0f;
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
            Station.Height = 8.0f;
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
            Station.Height = 8.0f;
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
            Station.Height = 8.0f;
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
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteClamping");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteClamping"),
            UCk_EntityScript_AttributeGym_ByteClamping,
            FInstancedStruct::Make(SpawnParams)
        );
	}

    void Request_StartByteModifiers()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteModifiers");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteModifiers"),
            UCk_EntityScript_AttributeGym_ByteModifiers,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteMinMaxCurrent()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteMinMaxCurrent");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteMinMaxCurrent"),
            UCk_EntityScript_AttributeGym_ByteMinMaxCurrent,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteMultiple()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteMultiple");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteMultiple"),
            UCk_EntityScript_AttributeGym_ByteMultiple,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteValues()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteValues");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteValues"),
            UCk_EntityScript_AttributeGym_ByteValues,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartByteSignals()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.ByteSignals");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.ByteSignals"),
            UCk_EntityScript_AttributeGym_ByteSignals,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    // Clamping station commands
    UFUNCTION(Exec, DisplayName="Byte Gym - Test Boundaries")
    void Ck_GymByte_TestBoundaries()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_ByteClamping");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_TestBoundaries());
        }
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

class ACk_ByteAttributeGym_GameMode : ACk_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_ByteAttributeGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}