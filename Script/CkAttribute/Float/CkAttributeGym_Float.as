//============================================================================
// FLOAT ATTRIBUTE GYM - PLAYER CONTROLLER & GAME MODE
//============================================================================

class ACk_FloatAttributeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Float Values Station (6 steps, 0 manual cmds, ~20 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatValues");
            Station.Title = FText::FromString("FLOAT VALUES");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Basic float attribute value operations and display."));
            Description.Add(FText::FromString("Tests Base/Bonus/Final retrieval, percentage, and magnitude calculations."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Clamping Station (1 step, 1 manual cmd, ~16 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatClamping");
            Station.Title = FText::FromString("FLOAT CLAMPING");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Demonstrates automatic value clamping within min/max boundaries."));
            Description.Add(FText::FromString("Cycles fractional values beyond limits to show float-precision clamping."));
            Description.Add(FText::FromString("Armor: 0-200 | Stamina: 50-255 | Health: 0-100 | Shield: 0-150"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Modifiers Station (8 steps, 0 manual cmds, ~14 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatModifiers");
            Station.Title = FText::FromString("FLOAT MODIFIERS");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests attribute modifier system with add/multiply operations."));
            Description.Add(FText::FromString("See how modifiers stack and affect final attribute values."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float MinMaxCurrent Station (6 steps, 0 manual cmds, ~16 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatMinMaxCurrent");
            Station.Title = FText::FromString("FLOAT MIN/MAX/CURRENT");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Displays all three attribute components: Min, Max, and Current."));
            Description.Add(FText::FromString("Watch how they update independently and interact."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Signals Station (6 steps, 0 manual cmds, ~18 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatSignals");
            Station.Title = FText::FromString("FLOAT SIGNALS");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests attribute signal system and callbacks."));
            Description.Add(FText::FromString("Monitors OnValueChanged, OnMinClamped, OnMaxClamped events."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Refill Station (6 steps, 1 manual cmd, ~14 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatRefill");
            Station.Title = FText::FromString("FLOAT REFILL");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests the float-exclusive refill/regeneration system."));
            Description.Add(FText::FromString("Drains energy, then watches it auto-refill. Pause/resume controls."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Increment/Decrement Station (7 steps, 0 manual cmds, ~12 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatIncrementDecrement");
            Station.Title = FText::FromString("FLOAT INC/DEC");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests the float mixin increment/decrement helpers."));
            Description.Add(FText::FromString("Revocable vs non-revocable +1/-1 operations and revocation."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Float Multiple Station (6 steps, 0 manual cmds, ~10 live-data lines)
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Attribute.FloatMultiple");
            Station.Title = FText::FromString("FLOAT MULTIPLE ATTRIBUTES");
            Station.AutoSize = true;
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
    // MANUAL COMMANDS - Values station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Float Gym - Add Modifier")
    void Ck_GymFloat_AddModifier()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatValues"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_AddModifier()); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Clear Modifiers")
    void Ck_GymFloat_ClearModifiers()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatValues"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_ClearModifiers()); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS - Clamping station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Float Gym - Test Boundaries")
    void Ck_GymFloat_TestBoundaries()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatClamping"))
        { utils_messaging::Broadcast(E, FCk_Message_AttributeGym_TestBoundaries()); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Reset Clamping")
    void Ck_GymFloat_ResetClamping()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatClamping"))
        { utils_messaging::Broadcast(E, FCk_Message_AttributeGym_ResetAttributes()); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS - Modifiers station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Float Gym - Add Weapon Modifier")
    void Ck_GymFloat_AddWeapon()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatModifiers"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_AddModifier()); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Remove Weapon Modifier")
    void Ck_GymFloat_RemoveWeapon()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatModifiers"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_RevokeAll()); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Clear All Modifiers")
    void Ck_GymFloat_ClearMods()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatModifiers"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_ClearModifiers()); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS - MinMaxCurrent station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Float Gym - Set Min")
    void Ck_GymFloat_SetMin(float32 InValue = 25.0f)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatMinMaxCurrent"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_SetValue(InValue, ECk_MinMaxCurrent::Min)); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Set Max")
    void Ck_GymFloat_SetMax(float32 InValue = 175.0f)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatMinMaxCurrent"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_SetValue(InValue, ECk_MinMaxCurrent::Max)); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Set Current")
    void Ck_GymFloat_SetCurrent(float32 InValue = 100.0f)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatMinMaxCurrent"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_SetValue(InValue, ECk_MinMaxCurrent::Current)); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS - Signals station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Float Gym - Set Signal Value")
    void Ck_GymFloat_SetSignalValue(float32 InValue = 150.0f)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatSignals"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_SetValue(InValue)); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS - Refill station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Float Gym - Toggle Refill")
    void Ck_GymFloat_ToggleRefill()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatRefill"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_ToggleRefill()); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Drain Energy")
    void Ck_GymFloat_DrainEnergy()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatRefill"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_DrainEnergy()); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Drain Mana")
    void Ck_GymFloat_DrainMana()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatRefill"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_DrainMana()); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS - IncDec station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Float Gym - Increment")
    void Ck_GymFloat_Increment()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatIncrementDecrement"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_Increment()); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Decrement")
    void Ck_GymFloat_Decrement()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatIncrementDecrement"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_Decrement()); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Revoke All")
    void Ck_GymFloat_RevokeAll()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatIncrementDecrement"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_RevokeAll()); }
    }

    //------------------------------------------------------------------------
    // MANUAL COMMANDS - Multiple station
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Float Gym - Add Batch")
    void Ck_GymFloat_AddBatch()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatMultiple"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_AddBatch()); }
    }

    UFUNCTION(Exec, DisplayName="Float Gym - Clear Batch")
    void Ck_GymFloat_ClearBatch()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AttributeGym_FloatMultiple"))
        { utils_messaging::Broadcast(E, FCk_Message_FloatGym_ClearBatch()); }
    }

    //------------------------------------------------------------------------
    // GLOBAL COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Float Gym - Reset All")
    void Ck_GymFloat_ResetAll()
    {
        for (auto Tag : Get_AllStationTags())
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto Entity : Entities)
            {
                utils_messaging::Broadcast(Entity, FCk_Message_AttributeGym_ResetAttributes());
            }
        }
    }

    // Auto mode commands
    UFUNCTION(Exec, DisplayName="Float Gym - Auto All")
    void Ck_GymFloat_Auto(int32 InEnabled = 1) { BroadcastAutoToAll(InEnabled != 0); }

    UFUNCTION(Exec, DisplayName="Float Gym - Auto Values")
    void Ck_GymFloat_AutoValues() { BroadcastAutoToTag(n"TAG_AttributeGym_FloatValues", true); }

    UFUNCTION(Exec, DisplayName="Float Gym - Auto Clamping")
    void Ck_GymFloat_AutoClamping() { BroadcastAutoToTag(n"TAG_AttributeGym_FloatClamping", true); }

    UFUNCTION(Exec, DisplayName="Float Gym - Auto Modifiers")
    void Ck_GymFloat_AutoModifiers() { BroadcastAutoToTag(n"TAG_AttributeGym_FloatModifiers", true); }

    UFUNCTION(Exec, DisplayName="Float Gym - Auto MinMaxCurrent")
    void Ck_GymFloat_AutoMinMaxCurrent() { BroadcastAutoToTag(n"TAG_AttributeGym_FloatMinMaxCurrent", true); }

    UFUNCTION(Exec, DisplayName="Float Gym - Auto Signals")
    void Ck_GymFloat_AutoSignals() { BroadcastAutoToTag(n"TAG_AttributeGym_FloatSignals", true); }

    UFUNCTION(Exec, DisplayName="Float Gym - Auto Refill")
    void Ck_GymFloat_AutoRefill() { BroadcastAutoToTag(n"TAG_AttributeGym_FloatRefill", true); }

    UFUNCTION(Exec, DisplayName="Float Gym - Auto IncDec")
    void Ck_GymFloat_AutoIncDec() { BroadcastAutoToTag(n"TAG_AttributeGym_FloatIncrementDecrement", true); }

    UFUNCTION(Exec, DisplayName="Float Gym - Auto Multiple")
    void Ck_GymFloat_AutoMultiple() { BroadcastAutoToTag(n"TAG_AttributeGym_FloatMultiple", true); }

    // Helpers
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

    private void BroadcastAutoToAll(bool InEnabled)
    {
        auto Msg = FCk_Message_Gym_AutoSet(InEnabled);
        for (auto Tag : Get_AllStationTags())
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto Entity : Entities)
            {
                utils_messaging::Broadcast(Entity, Msg);
            }
        }
    }

    private void BroadcastAutoToTag(FName InTag, bool InEnabled)
    {
        auto Msg = FCk_Message_Gym_AutoSet(InEnabled);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, Msg);
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
