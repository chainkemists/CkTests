//============================================================================
// FLOAT ATTRIBUTE GYM - PLAYER CONTROLLER & GAME MODE
//============================================================================

class ACk_FloatAttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    // Preset-ring positions for the panel rows; each press applies the NEXT value, chosen to
    // exercise the auto-clamping (over-max, below-min) each station demonstrates.
    private int32 _MinPresetIndex = -1;
    private int32 _MaxPresetIndex = -1;
    private int32 _CurrentPresetIndex = -1;
    private int32 _SignalPresetIndex = -1;

    // Action rings - the eight stations carry more knobs than there are legal keys, so the
    // per-station actions share one key each and step through their list.
    private int32 _ValuesActionIndex = -1;
    private int32 _ModifiersActionIndex = -1;
    private int32 _RefillActionIndex = -1;
    private int32 _IncDecActionIndex = -1;
    private int32 _MultipleActionIndex = -1;
    private int32 _ResetActionIndex = -1;

    // Mirrors of each station's auto-cycle state - it lives in the entity scripts behind a
    // broadcast message with no readback, so the panel mirrors it here (all start true: every
    // station auto-runs).
    private bool _AutoAllEnabled = true;
    private bool _AutoValues = true;
    private bool _AutoClamping = true;
    private bool _AutoModifiers = true;
    private bool _AutoMinMaxCurrent = true;
    private bool _AutoSignals = true;
    private bool _AutoRefill = true;
    private bool _AutoIncDec = true;
    private bool _AutoMultiple = true;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Float Values Station (6 steps, ~20 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatValues");
            Station.Title = FText::FromString("FLOAT VALUES");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Basic float attribute value operations and display."));
            Description.Add(FText::FromString("Tests Base/Bonus/Final retrieval, percentage, and magnitude calculations."));
            Description.Add(FText::FromString("Panel: [1] auto - [J] add/clear modifier"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Clamping Station (1 step, ~16 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatClamping");
            Station.Title = FText::FromString("FLOAT CLAMPING");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Demonstrates automatic value clamping within min/max boundaries."));
            Description.Add(FText::FromString("Cycles fractional values beyond limits to show float-precision clamping."));
            Description.Add(FText::FromString("Armor: 0-200 | Stamina: 50-255 | Health: 0-100 | Shield: 0-150"));
            Description.Add(FText::FromString("Panel: [2] auto - [B] test boundaries - [R] reset"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Modifiers Station (8 steps, ~14 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatModifiers");
            Station.Title = FText::FromString("FLOAT MODIFIERS");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests attribute modifier system with add/multiply operations."));
            Description.Add(FText::FromString("See how modifiers stack and affect final attribute values."));
            Description.Add(FText::FromString("Panel: [3] auto - [K] add weapon / revoke weapon / clear all"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float MinMaxCurrent Station (6 steps, ~16 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatMinMaxCurrent");
            Station.Title = FText::FromString("FLOAT MIN/MAX/CURRENT");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays all three attribute components: Min, Max, and Current."));
            Description.Add(FText::FromString("Watch how they update independently and interact."));
            Description.Add(FText::FromString("Panel: [4] auto - [U] Min preset - [I] Max preset - [O] Current preset"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Signals Station (6 steps, ~18 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatSignals");
            Station.Title = FText::FromString("FLOAT SIGNALS");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests attribute signal system and callbacks."));
            Description.Add(FText::FromString("Monitors OnValueChanged, OnMinClamped, OnMaxClamped events."));
            Description.Add(FText::FromString("Panel: [5] auto - [P] signal value preset"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Refill Station (6 steps, ~14 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatRefill");
            Station.Title = FText::FromString("FLOAT REFILL");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests the float-exclusive refill/regeneration system."));
            Description.Add(FText::FromString("Drains energy, then watches it auto-refill. Pause/resume controls."));
            Description.Add(FText::FromString("Panel: [6] auto - [G] toggle refill / drain energy / drain mana"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Increment/Decrement Station (12 steps, ~12 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatIncrementDecrement");
            Station.Title = FText::FromString("FLOAT INC/DEC");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests the float mixin increment/decrement helpers."));
            Description.Add(FText::FromString("Revocable vs non-revocable +1/-1 operations and revocation."));
            Description.Add(FText::FromString("Panel: [7] auto - [N] increment / decrement / revoke all"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Multiple Station (6 steps, ~10 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatMultiple");
            Station.Title = FText::FromString("FLOAT MULTIPLE ATTRIBUTES");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Entity with multiple float attributes working simultaneously."));
            Description.Add(FText::FromString("Tests attribute independence, batch creation, and iteration patterns."));
            Description.Add(FText::FromString("Panel: [8] auto - [M] add batch / clear batch"));
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
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.FloatValues", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatValues"),
            UCk_EntityScript_AttributeGym_FloatValues,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatClamping()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.FloatClamping", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatClamping"),
            UCk_EntityScript_AttributeGym_FloatClamping,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatModifiers()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.FloatModifiers", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatModifiers"),
            UCk_EntityScript_AttributeGym_FloatModifiers,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatMinMaxCurrent()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.FloatMinMaxCurrent", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatMinMaxCurrent"),
            UCk_EntityScript_AttributeGym_FloatMinMaxCurrent,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatSignals()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.FloatSignals", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatSignals"),
            UCk_EntityScript_AttributeGym_FloatSignals,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatRefill()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.FloatRefill", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatRefill"),
            UCk_EntityScript_AttributeGym_FloatRefill,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatIncrementDecrement()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.FloatIncrementDecrement", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatIncrementDecrement"),
            UCk_EntityScript_AttributeGym_FloatIncrementDecrement,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    void Request_StartFloatMultiple()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Attribute.FloatMultiple", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Attribute.FloatMultiple"),
            UCk_EntityScript_AttributeGym_FloatMultiple,
            FInstancedStruct::Make(SpawnParams)
        );
    }

    //------------------------------------------------------------------------
    // Control panel
    //------------------------------------------------------------------------

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("FLOAT ATTRIBUTE GYM"));
        Rows.Add(CkGym_Control::Toggle(EKeys::T, "T", "Auto-cycle all stations", _AutoAllEnabled));

        Rows.Add(CkGym_Control::Header("AUTO PER STATION"));
        Rows.Add(CkGym_Control::Numbered(0, "Values", _AutoValues));
        Rows.Add(CkGym_Control::Numbered(1, "Clamping", _AutoClamping));
        Rows.Add(CkGym_Control::Numbered(2, "Modifiers", _AutoModifiers));
        Rows.Add(CkGym_Control::Numbered(3, "Min/Max/Current", _AutoMinMaxCurrent));
        Rows.Add(CkGym_Control::Numbered(4, "Signals", _AutoSignals));
        Rows.Add(CkGym_Control::Numbered(5, "Refill", _AutoRefill));
        Rows.Add(CkGym_Control::Numbered(6, "Inc/Dec", _AutoIncDec));
        Rows.Add(CkGym_Control::Numbered(7, "Multiple", _AutoMultiple));

        Rows.Add(CkGym_Control::Header("STATION ACTIONS"));
        Rows.Add(CkGym_Control::Cycle(EKeys::J, "J", "Values modifiers",  DoGet_PresetLabel(_ValuesActionIndex,    "add modifier / clear modifiers")));
        Rows.Add(CkGym_Control::Cycle(EKeys::K, "K", "Modifiers station", DoGet_PresetLabel(_ModifiersActionIndex, "add weapon / revoke weapon / clear all")));
        Rows.Add(CkGym_Control::Cycle(EKeys::G, "G", "Refill station",    DoGet_PresetLabel(_RefillActionIndex,    "toggle refill / drain energy / drain mana")));
        Rows.Add(CkGym_Control::Cycle(EKeys::N, "N", "Inc/Dec station",   DoGet_PresetLabel(_IncDecActionIndex,    "increment / decrement / revoke all")));
        Rows.Add(CkGym_Control::Cycle(EKeys::M, "M", "Multiple station",  DoGet_PresetLabel(_MultipleActionIndex,  "add batch / clear batch")));

        Rows.Add(CkGym_Control::Header("PRESETS"));
        Rows.Add(CkGym_Control::Cycle(EKeys::U, "U", "Min preset (Min/Max/Current)",     DoGet_PresetLabel(_MinPresetIndex,     "10 / 25.5 / 60 / 220")));
        Rows.Add(CkGym_Control::Cycle(EKeys::I, "I", "Max preset (Min/Max/Current)",     DoGet_PresetLabel(_MaxPresetIndex,     "200 / 175.75 / 90 / 5")));
        Rows.Add(CkGym_Control::Cycle(EKeys::O, "O", "Current preset (Min/Max/Current)", DoGet_PresetLabel(_CurrentPresetIndex, "100 / 142.3 / 250 / -40")));
        Rows.Add(CkGym_Control::Cycle(EKeys::P, "P", "Signal value preset (Signals)",    DoGet_PresetLabel(_SignalPresetIndex,  "150 / 0 / 300 / -50")));

        Rows.Add(CkGym_Control::Header("GLOBAL"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Test boundaries (Clamping)"));
        Rows.Add(CkGym_Control::Cycle(EKeys::R, "R", "Reset", DoGet_PresetLabel(_ResetActionIndex, "clamping station / all stations")));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1)
        {
            _AutoAllEnabled = !_AutoAllEnabled;
            _AutoValues = _AutoAllEnabled;
            _AutoClamping = _AutoAllEnabled;
            _AutoModifiers = _AutoAllEnabled;
            _AutoMinMaxCurrent = _AutoAllEnabled;
            _AutoSignals = _AutoAllEnabled;
            _AutoRefill = _AutoAllEnabled;
            _AutoIncDec = _AutoAllEnabled;
            _AutoMultiple = _AutoAllEnabled;

            for (auto Tag : Get_AllStationTags())
            {
                DoBroadcastToStation(Tag, FCk_Message_Gym_AutoSet(_AutoAllEnabled));
            }
        }
        else if (InRowIndex == 3)
        {
            _AutoValues = !_AutoValues;
            DoBroadcastToStation(n"TAG_AttributeGym_FloatValues", FCk_Message_Gym_AutoSet(_AutoValues));
        }
        else if (InRowIndex == 4)
        {
            _AutoClamping = !_AutoClamping;
            DoBroadcastToStation(n"TAG_AttributeGym_FloatClamping", FCk_Message_Gym_AutoSet(_AutoClamping));
        }
        else if (InRowIndex == 5)
        {
            _AutoModifiers = !_AutoModifiers;
            DoBroadcastToStation(n"TAG_AttributeGym_FloatModifiers", FCk_Message_Gym_AutoSet(_AutoModifiers));
        }
        else if (InRowIndex == 6)
        {
            _AutoMinMaxCurrent = !_AutoMinMaxCurrent;
            DoBroadcastToStation(n"TAG_AttributeGym_FloatMinMaxCurrent", FCk_Message_Gym_AutoSet(_AutoMinMaxCurrent));
        }
        else if (InRowIndex == 7)
        {
            _AutoSignals = !_AutoSignals;
            DoBroadcastToStation(n"TAG_AttributeGym_FloatSignals", FCk_Message_Gym_AutoSet(_AutoSignals));
        }
        else if (InRowIndex == 8)
        {
            _AutoRefill = !_AutoRefill;
            DoBroadcastToStation(n"TAG_AttributeGym_FloatRefill", FCk_Message_Gym_AutoSet(_AutoRefill));
        }
        else if (InRowIndex == 9)
        {
            _AutoIncDec = !_AutoIncDec;
            DoBroadcastToStation(n"TAG_AttributeGym_FloatIncrementDecrement", FCk_Message_Gym_AutoSet(_AutoIncDec));
        }
        else if (InRowIndex == 10)
        {
            _AutoMultiple = !_AutoMultiple;
            DoBroadcastToStation(n"TAG_AttributeGym_FloatMultiple", FCk_Message_Gym_AutoSet(_AutoMultiple));
        }
        else if (InRowIndex == 12)
        {
            _ValuesActionIndex = (_ValuesActionIndex + 1) % 2;
            if (_ValuesActionIndex == 0)
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatValues", FCk_Message_FloatGym_AddModifier()); }
            else
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatValues", FCk_Message_FloatGym_ClearModifiers()); }
        }
        else if (InRowIndex == 13)
        {
            _ModifiersActionIndex = (_ModifiersActionIndex + 1) % 3;
            if (_ModifiersActionIndex == 0)
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatModifiers", FCk_Message_FloatGym_AddModifier()); }
            else if (_ModifiersActionIndex == 1)
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatModifiers", FCk_Message_FloatGym_RevokeAll()); }
            else
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatModifiers", FCk_Message_FloatGym_ClearModifiers()); }
        }
        else if (InRowIndex == 14)
        {
            _RefillActionIndex = (_RefillActionIndex + 1) % 3;
            if (_RefillActionIndex == 0)
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatRefill", FCk_Message_FloatGym_ToggleRefill()); }
            else if (_RefillActionIndex == 1)
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatRefill", FCk_Message_FloatGym_DrainEnergy()); }
            else
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatRefill", FCk_Message_FloatGym_DrainMana()); }
        }
        else if (InRowIndex == 15)
        {
            _IncDecActionIndex = (_IncDecActionIndex + 1) % 3;
            if (_IncDecActionIndex == 0)
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatIncrementDecrement", FCk_Message_FloatGym_Increment()); }
            else if (_IncDecActionIndex == 1)
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatIncrementDecrement", FCk_Message_FloatGym_Decrement()); }
            else
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatIncrementDecrement", FCk_Message_FloatGym_RevokeAll()); }
        }
        else if (InRowIndex == 16)
        {
            _MultipleActionIndex = (_MultipleActionIndex + 1) % 2;
            if (_MultipleActionIndex == 0)
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatMultiple", FCk_Message_FloatGym_AddBatch()); }
            else
            { DoBroadcastToStation(n"TAG_AttributeGym_FloatMultiple", FCk_Message_FloatGym_ClearBatch()); }
        }
        else if (InRowIndex == 18)
        {
            _MinPresetIndex = (_MinPresetIndex + 1) % 4;
            auto Values = TArray<float32>();
            Values.Add(10.0f); Values.Add(25.5f); Values.Add(60.0f); Values.Add(220.0f);
            DoBroadcastToStation(n"TAG_AttributeGym_FloatMinMaxCurrent", FCk_Message_FloatGym_SetValue(Values[_MinPresetIndex], ECk_MinMaxCurrent::Min));
        }
        else if (InRowIndex == 19)
        {
            _MaxPresetIndex = (_MaxPresetIndex + 1) % 4;
            auto Values = TArray<float32>();
            Values.Add(200.0f); Values.Add(175.75f); Values.Add(90.0f); Values.Add(5.0f);
            DoBroadcastToStation(n"TAG_AttributeGym_FloatMinMaxCurrent", FCk_Message_FloatGym_SetValue(Values[_MaxPresetIndex], ECk_MinMaxCurrent::Max));
        }
        else if (InRowIndex == 20)
        {
            _CurrentPresetIndex = (_CurrentPresetIndex + 1) % 4;
            auto Values = TArray<float32>();
            Values.Add(100.0f); Values.Add(142.3f); Values.Add(250.0f); Values.Add(-40.0f);
            DoBroadcastToStation(n"TAG_AttributeGym_FloatMinMaxCurrent", FCk_Message_FloatGym_SetValue(Values[_CurrentPresetIndex], ECk_MinMaxCurrent::Current));
        }
        else if (InRowIndex == 21)
        {
            _SignalPresetIndex = (_SignalPresetIndex + 1) % 4;
            auto Values = TArray<float32>();
            Values.Add(150.0f); Values.Add(0.0f); Values.Add(300.0f); Values.Add(-50.0f);
            DoBroadcastToStation(n"TAG_AttributeGym_FloatSignals", FCk_Message_FloatGym_SetValue(Values[_SignalPresetIndex], ECk_MinMaxCurrent::Current));
        }
        else if (InRowIndex == 23)
        {
            DoBroadcastToStation(n"TAG_AttributeGym_FloatClamping", FCk_Message_AttributeGym_TestBoundaries());
        }
        else if (InRowIndex == 24)
        {
            _ResetActionIndex = (_ResetActionIndex + 1) % 2;
            if (_ResetActionIndex == 0)
            {
                DoBroadcastToStation(n"TAG_AttributeGym_FloatClamping", FCk_Message_AttributeGym_ResetAttributes());
            }
            else
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
    }

    private FString DoGet_PresetLabel(int32 InIndex, FString InRing)
    {
        return InIndex < 0 ? f"({InRing})" : f"step {InIndex + 1}";
    }

    private TArray<FName> Get_AllStationTags()
    {
        auto StationTags = TArray<FName>();
        StationTags.Add(n"TAG_AttributeGym_FloatValues");
        StationTags.Add(n"TAG_AttributeGym_FloatClamping");
        StationTags.Add(n"TAG_AttributeGym_FloatModifiers");
        StationTags.Add(n"TAG_AttributeGym_FloatMinMaxCurrent");
        StationTags.Add(n"TAG_AttributeGym_FloatSignals");
        StationTags.Add(n"TAG_AttributeGym_FloatRefill");
        StationTags.Add(n"TAG_AttributeGym_FloatIncrementDecrement");
        StationTags.Add(n"TAG_AttributeGym_FloatMultiple");
        return StationTags;
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_Gym_AutoSet InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_AddModifier InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_ClearModifiers InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_RevokeAll InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_SetValue InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_ToggleRefill InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_DrainEnergy InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_DrainMana InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_Increment InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_Decrement InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_AddBatch InMessage)
    {
        for (auto Entity : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag))
        {
            utils_messaging::Broadcast(Entity, InMessage);
        }
    }

    private void DoBroadcastToStation(FName InTag, FCk_Message_FloatGym_ClearBatch InMessage)
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

class ACk_FloatAttributeGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_FloatAttributeGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}
