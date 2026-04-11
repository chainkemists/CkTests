//============================================================================
// FLOAT ATTRIBUTE GYM - PLAYER CONTROLLER & GAME MODE
//============================================================================

class ACk_FloatAttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Float Values Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatValues");
            Station.Title = FText::FromString("FLOAT VALUES");
            Station.Height = 8.0f;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Basic float attribute value operations and display."));
            Description.Add(FText::FromString("Tests Base/Bonus/Final retrieval, percentage, and magnitude calculations."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Clamping Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatClamping");
            Station.Title = FText::FromString("FLOAT CLAMPING");
            Station.Height = 8.0f;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Demonstrates automatic value clamping within min/max boundaries."));
            Description.Add(FText::FromString("Cycles fractional values beyond limits to show float-precision clamping."));
            Description.Add(FText::FromString("Armor: 0-200 | Stamina: 50-255 | Health: 0-100 | Shield: 0-150"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Modifiers Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatModifiers");
            Station.Title = FText::FromString("FLOAT MODIFIERS");
            Station.Height = 8.0f;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests attribute modifier system with add/multiply operations."));
            Description.Add(FText::FromString("See how modifiers stack and affect final attribute values."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float MinMaxCurrent Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatMinMaxCurrent");
            Station.Title = FText::FromString("FLOAT MIN/MAX/CURRENT");
            Station.Height = 8.0f;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays all three attribute components: Min, Max, and Current."));
            Description.Add(FText::FromString("Watch how they update independently and interact."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Signals Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatSignals");
            Station.Title = FText::FromString("FLOAT SIGNALS");
            Station.Height = 8.0f;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests attribute signal system and callbacks."));
            Description.Add(FText::FromString("Monitors OnValueChanged, OnMinClamped, OnMaxClamped events."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Refill Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatRefill");
            Station.Title = FText::FromString("FLOAT REFILL");
            Station.Height = 8.0f;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests the float-exclusive refill/regeneration system."));
            Description.Add(FText::FromString("Drains energy, then watches it auto-refill. Pause/resume controls."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Increment/Decrement Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatIncrementDecrement");
            Station.Title = FText::FromString("FLOAT INC/DEC");
            Station.Height = 8.0f;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests the float mixin increment/decrement helpers."));
            Description.Add(FText::FromString("Revocable vs non-revocable +1/-1 operations and revocation."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Multiple Station
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatMultiple");
            Station.Title = FText::FromString("FLOAT MULTIPLE ATTRIBUTES");
            Station.Height = 8.0f;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Entity with multiple float attributes working simultaneously."));
            Description.Add(FText::FromString("Tests attribute independence, batch creation, and iteration patterns."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartFloatValues();
        Request_StartFloatClamping();
        Request_StartFloatModifiers();
        Request_StartFloatMinMaxCurrent();
        Request_StartFloatSignals();
        Request_StartFloatRefill();
        Request_StartFloatIncrementDecrement();
        Request_StartFloatMultiple();
    }

    void Request_StartFloatValues()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.FloatValues");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatValues"),
            UCk_EntityScript_AttributeGym_FloatValues,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatClamping()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.FloatClamping");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatClamping"),
            UCk_EntityScript_AttributeGym_FloatClamping,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatModifiers()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.FloatModifiers");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatModifiers"),
            UCk_EntityScript_AttributeGym_FloatModifiers,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatMinMaxCurrent()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.FloatMinMaxCurrent");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatMinMaxCurrent"),
            UCk_EntityScript_AttributeGym_FloatMinMaxCurrent,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatSignals()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.FloatSignals");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatSignals"),
            UCk_EntityScript_AttributeGym_FloatSignals,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatRefill()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.FloatRefill");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatRefill"),
            UCk_EntityScript_AttributeGym_FloatRefill,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatIncrementDecrement()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.FloatIncrementDecrement");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatIncrementDecrement"),
            UCk_EntityScript_AttributeGym_FloatIncrementDecrement,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatMultiple()
    {
        auto StationTransform = Get_StationTransform("Gym.Attribute.FloatMultiple");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatMultiple"),
            UCk_EntityScript_AttributeGym_FloatMultiple,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    // Clamping station commands
    UFUNCTION(Exec, DisplayName="Float Gym - Test Boundaries")
    void Ck_GymFloat_TestBoundaries()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatClamping");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_TestBoundaries());
        }
    }

    // Refill station commands
    UFUNCTION(Exec, DisplayName="Float Gym - Toggle Refill")
    void Ck_GymFloat_ToggleRefill()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatRefill");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_FloatGym_ToggleRefill());
        }
    }

    // Global commands
    UFUNCTION(Exec, DisplayName="Float Gym - Reset All")
    void Ck_GymFloat_ResetAll()
    {
        auto AllTags = TArray<FName>();
        AllTags.Add(n"TAG_AttributeGym_FloatClamping");
        AllTags.Add(n"TAG_AttributeGym_FloatModifiers");
        AllTags.Add(n"TAG_AttributeGym_FloatValues");
        AllTags.Add(n"TAG_AttributeGym_FloatMinMaxCurrent");
        AllTags.Add(n"TAG_AttributeGym_FloatSignals");
        AllTags.Add(n"TAG_AttributeGym_FloatRefill");
        AllTags.Add(n"TAG_AttributeGym_FloatIncrementDecrement");
        AllTags.Add(n"TAG_AttributeGym_FloatMultiple");

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

class ACk_FloatAttributeGym_GameMode : ACk_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_FloatAttributeGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
