//============================================================================
// BYTE ATTRIBUTE GYM - PLAYER CONTROLLER & GAME MODE
//============================================================================

class ACk_ByteAttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    // Preset-ring positions for the panel rows; each press applies the NEXT value, chosen to
    // exercise the auto-clamping (over-max, below-min) each station demonstrates.
    private int32 _MinPresetIndex = -1;
    private int32 _MaxPresetIndex = -1;
    private int32 _CurrentPresetIndex = -1;
    private int32 _SignalPresetIndex = -1;

    // Mirrors of each station's auto-cycle state - it lives in the entity scripts behind a
    // broadcast message with no readback, so the panel mirrors it here (all start true: every
    // station auto-runs).
    private bool _AutoAllEnabled = true;
    private bool _AutoClamping = true;
    private bool _AutoModifiers = true;
    private bool _AutoValues = true;
    private bool _AutoMinMaxCurrent = true;
    private bool _AutoMultiple = true;
    private bool _AutoSignals = true;

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
            Description.Add(FText::FromString("Panel: [1] auto - [B] test boundaries - [R] reset all"));
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
            Description.Add(FText::FromString("Panel: [2] auto - [G] add modifier - [N] clear modifiers"));
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
            Description.Add(FText::FromString("Panel: [4] auto - [7] Min - [8] Max - [9] Current"));
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
            Description.Add(FText::FromString("Panel: [5] auto - [M] add batch - [U] clear batch"));
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
            Description.Add(FText::FromString("Panel: [3] auto - [J] add modifier - [K] clear modifiers"));
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
            Description.Add(FText::FromString("Panel: [6] auto - [0] signal value preset"));
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
    // Control panel
    //------------------------------------------------------------------------

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("BYTE ATTRIBUTE GYM"));
        Rows.Add(CkGym_Control::Toggle(EKeys::T, "T", "Auto-cycle all stations", _AutoAllEnabled));

        Rows.Add(CkGym_Control::Header("AUTO PER STATION"));
        Rows.Add(CkGym_Control::Numbered(0, "Clamping", _AutoClamping));
        Rows.Add(CkGym_Control::Numbered(1, "Modifiers", _AutoModifiers));
        Rows.Add(CkGym_Control::Numbered(2, "Values", _AutoValues));
        Rows.Add(CkGym_Control::Numbered(3, "Min/Max/Current", _AutoMinMaxCurrent));
        Rows.Add(CkGym_Control::Numbered(4, "Multiple", _AutoMultiple));
        Rows.Add(CkGym_Control::Numbered(5, "Signals", _AutoSignals));

        Rows.Add(CkGym_Control::Header("MIN/MAX/CURRENT STATION"));
        Rows.Add(CkGym_Control::Cycle(EKeys::Seven, "7", "Min preset",     DoGet_PresetLabel(_MinPresetIndex,     "10 / 20 / 120 / 220")));
        Rows.Add(CkGym_Control::Cycle(EKeys::Eight, "8", "Max preset",     DoGet_PresetLabel(_MaxPresetIndex,     "200 / 180 / 80 / 5")));
        Rows.Add(CkGym_Control::Cycle(EKeys::Nine,  "9", "Current preset", DoGet_PresetLabel(_CurrentPresetIndex, "100 / 150 / 255 / 0")));

        // The Signals attribute spans 0-255, which IS the whole uint8 domain, so no argument can
        // land outside the band - this ring walks the band ends instead of provoking a clamp.
        Rows.Add(CkGym_Control::Header("SIGNALS STATION"));
        Rows.Add(CkGym_Control::Cycle(EKeys::Zero, "0", "Signal value preset", DoGet_PresetLabel(_SignalPresetIndex, "150 / 0 / 255 / 200")));

        Rows.Add(CkGym_Control::Header("VALUES STATION"));
        Rows.Add(CkGym_Control::Action(EKeys::J, "J", "Add modifier"));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Clear modifiers"));

        Rows.Add(CkGym_Control::Header("MODIFIERS STATION"));
        Rows.Add(CkGym_Control::Action(EKeys::G, "G", "Add modifier"));
        Rows.Add(CkGym_Control::Action(EKeys::N, "N", "Clear modifiers"));

        Rows.Add(CkGym_Control::Header("MULTIPLE STATION"));
        Rows.Add(CkGym_Control::Action(EKeys::M, "M", "Add batch"));
        Rows.Add(CkGym_Control::Action(EKeys::U, "U", "Clear batch"));

        Rows.Add(CkGym_Control::Header("CLAMPING STATION"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Test boundaries"));

        Rows.Add(CkGym_Control::Header("GLOBAL"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset all stations"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1)
        {
            _AutoAllEnabled = !_AutoAllEnabled;
            _AutoClamping = _AutoAllEnabled;
            _AutoModifiers = _AutoAllEnabled;
            _AutoValues = _AutoAllEnabled;
            _AutoMinMaxCurrent = _AutoAllEnabled;
            _AutoMultiple = _AutoAllEnabled;
            _AutoSignals = _AutoAllEnabled;

            for (auto Tag : Get_AllStationTags())
            {
                DoBroadcastToStation(Tag, FCk_Message_Gym_AutoSet(_AutoAllEnabled));
            }
        }
        else if (InRowIndex == 3)
        {
            _AutoClamping = !_AutoClamping;
            DoBroadcastToStation(n"TAG_AttributeGym_ByteClamping", FCk_Message_Gym_AutoSet(_AutoClamping));
        }
        else if (InRowIndex == 4)
        {
            _AutoModifiers = !_AutoModifiers;
            DoBroadcastToStation(n"TAG_AttributeGym_ByteModifiers", FCk_Message_Gym_AutoSet(_AutoModifiers));
        }
        else if (InRowIndex == 5)
        {
            _AutoValues = !_AutoValues;
            DoBroadcastToStation(n"TAG_AttributeGym_ByteValues", FCk_Message_Gym_AutoSet(_AutoValues));
        }
        else if (InRowIndex == 6)
        {
            _AutoMinMaxCurrent = !_AutoMinMaxCurrent;
            DoBroadcastToStation(n"TAG_AttributeGym_ByteMinMaxCurrent", FCk_Message_Gym_AutoSet(_AutoMinMaxCurrent));
        }
        else if (InRowIndex == 7)
        {
            _AutoMultiple = !_AutoMultiple;
            DoBroadcastToStation(n"TAG_AttributeGym_ByteMultiple", FCk_Message_Gym_AutoSet(_AutoMultiple));
        }
        else if (InRowIndex == 8)
        {
            _AutoSignals = !_AutoSignals;
            DoBroadcastToStation(n"TAG_AttributeGym_ByteSignals", FCk_Message_Gym_AutoSet(_AutoSignals));
        }
        else if (InRowIndex == 10)
        {
            _MinPresetIndex = (_MinPresetIndex + 1) % 4;
            auto Values = TArray<uint8>();
            Values.Add(uint8(10)); Values.Add(uint8(20)); Values.Add(uint8(120)); Values.Add(uint8(220));
            DoBroadcastToStation(n"TAG_AttributeGym_ByteMinMaxCurrent", FCk_Message_ByteGym_SetValue(Values[_MinPresetIndex], ECk_MinMaxCurrent::Min));
        }
        else if (InRowIndex == 11)
        {
            _MaxPresetIndex = (_MaxPresetIndex + 1) % 4;
            auto Values = TArray<uint8>();
            Values.Add(uint8(200)); Values.Add(uint8(180)); Values.Add(uint8(80)); Values.Add(uint8(5));
            DoBroadcastToStation(n"TAG_AttributeGym_ByteMinMaxCurrent", FCk_Message_ByteGym_SetValue(Values[_MaxPresetIndex], ECk_MinMaxCurrent::Max));
        }
        else if (InRowIndex == 12)
        {
            _CurrentPresetIndex = (_CurrentPresetIndex + 1) % 4;
            auto Values = TArray<uint8>();
            Values.Add(uint8(100)); Values.Add(uint8(150)); Values.Add(uint8(255)); Values.Add(uint8(0));
            DoBroadcastToStation(n"TAG_AttributeGym_ByteMinMaxCurrent", FCk_Message_ByteGym_SetValue(Values[_CurrentPresetIndex], ECk_MinMaxCurrent::Current));
        }
        else if (InRowIndex == 14)
        {
            _SignalPresetIndex = (_SignalPresetIndex + 1) % 4;
            auto Values = TArray<uint8>();
            Values.Add(uint8(150)); Values.Add(uint8(0)); Values.Add(uint8(255)); Values.Add(uint8(200));
            DoBroadcastToStation(n"TAG_AttributeGym_ByteSignals", FCk_Message_ByteGym_SetValue(Values[_SignalPresetIndex], ECk_MinMaxCurrent::Current));
        }
        else if (InRowIndex == 16)
        {
            DoBroadcastToStation(n"TAG_AttributeGym_ByteValues", FCk_Message_ByteGym_AddModifier());
        }
        else if (InRowIndex == 17)
        {
            DoBroadcastToStation(n"TAG_AttributeGym_ByteValues", FCk_Message_ByteGym_ClearModifiers());
        }
        else if (InRowIndex == 19)
        {
            DoBroadcastToStation(n"TAG_AttributeGym_ByteModifiers", FCk_Message_ByteGym_AddModifier());
        }
        else if (InRowIndex == 20)
        {
            DoBroadcastToStation(n"TAG_AttributeGym_ByteModifiers", FCk_Message_ByteGym_ClearModifiers());
        }
        else if (InRowIndex == 22)
        {
            DoBroadcastToStation(n"TAG_AttributeGym_ByteMultiple", FCk_Message_ByteGym_AddBatch());
        }
        else if (InRowIndex == 23)
        {
            DoBroadcastToStation(n"TAG_AttributeGym_ByteMultiple", FCk_Message_ByteGym_ClearBatch());
        }
        else if (InRowIndex == 25)
        {
            DoBroadcastToStation(n"TAG_AttributeGym_ByteClamping", FCk_Message_AttributeGym_TestBoundaries());
        }
        else if (InRowIndex == 27)
        {
            for (auto Tag : Get_AllStationTags())
            {
                DoBroadcastToStation(Tag, FCk_Message_AttributeGym_ResetAttributes());
            }

            _MinPresetIndex = -1;
            _MaxPresetIndex = -1;
            _CurrentPresetIndex = -1;
            _SignalPresetIndex = -1;
        }
    }

    private FString DoGet_PresetLabel(int32 InIndex, FString InRing)
    {
        return InIndex < 0 ? f"({InRing})" : f"step {InIndex + 1}";
    }

    private TArray<FName> Get_AllStationTags()
    {
        auto StationTags = TArray<FName>();
        StationTags.Add(n"TAG_AttributeGym_ByteClamping");
        StationTags.Add(n"TAG_AttributeGym_ByteModifiers");
        StationTags.Add(n"TAG_AttributeGym_ByteValues");
        StationTags.Add(n"TAG_AttributeGym_ByteMinMaxCurrent");
        StationTags.Add(n"TAG_AttributeGym_ByteMultiple");
        StationTags.Add(n"TAG_AttributeGym_ByteSignals");
        return StationTags;
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_Gym_AutoSet InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_ByteGym_SetValue InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_ByteGym_AddModifier InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_ByteGym_ClearModifiers InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_ByteGym_AddBatch InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_ByteGym_ClearBatch InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_AttributeGym_TestBoundaries InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_AttributeGym_ResetAttributes InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
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
