// Language=angelscript

class ACk_VatGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Vat.ClipCycle", "Clip Cycle",
            "Single VAT instance auto-cycling every baked clip\n(crossfade), rates, freeze/resume. OnClipFinished counter."));
        Stations.Add(MakeStationPayload(n"Gym.Vat.Turntable", "Turntable (Normals)",
            "Rotating instance looping one clip.\nLighting must stay consistent while it turns."));
        Stations.Add(MakeStationPayload(n"Gym.Vat.CrowdField", "Crowd Field",
            "100 instances, per-instance random phase.\nCustom data written on clip change only."));

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload MakeStationPayload(FName InTag, FString InTitle, FString InDesc)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        Station.AutoSize = true;
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString(InDesc));
        Station.Description = Desc;
        return Station;
    }

    void Request_StartGym() override
    {
        SpawnStation("Gym.Vat.ClipCycle",  UCk_EntityScript_VatGym_ClipCycle);
        SpawnStation("Gym.Vat.Turntable",  UCk_EntityScript_VatGym_Turntable);
        SpawnStation("Gym.Vat.CrowdField", UCk_EntityScript_VatGym_CrowdField);
    }

    private void SpawnStation(FString InTag, TSubclassOf<UCk_EntityScript_UE> InScriptClass)
    {
        auto Params = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter));

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            InScriptClass,
            FInstancedStruct::Make(Params));
    }

    //------------------------------------------------------------------------
    // Broadcast plumbing (messages travel as raw structs - mirror the
    // inventory gym PC; utils_messaging::Broadcast handles the wrapping)
    //------------------------------------------------------------------------

    private TArray<FName> Get_AllStationTags()
    {
        auto StationTags = TArray<FName>();
        StationTags.Add(n"TAG_VatGym_ClipCycle");
        StationTags.Add(n"TAG_VatGym_Turntable");
        StationTags.Add(n"TAG_VatGym_CrowdField");
        return StationTags;
    }

    // The last play rate broadcast to the clip-cycle station, panel or console. Not a mirror of station
    // state - the stations have no readback - so it is named for what it honestly is.
    private float32 _LastRateSent = 1.0f;

    // Same contract for the auto row. It reports the last value BROADCAST, not what the stations are
    // doing: each one calls gym_auto::StopAuto the moment a manual message arrives, so a true mirror
    // is impossible. Its two states are named "sent ON" / "sent off" so nobody reads it as station
    // state - and it exists as a Toggle at all because the enable-only row could never send the 0.
    private bool _LastAutoSent = true;

    // Panel-owned knobs. Nothing but these rows ever writes the crowd count or the turn rate - no auto
    // step touches either - so unlike the two above, these ARE the stations' live values.
    private int32 _FieldCount = 100;
    private float32 _TurnRateDegreesPerSecond = 30.0f;

    //------------------------------------------------------------------------
    // Console commands
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Vat Gym - Set Collection Path")
    void Ck_GymVat_SetCollection(FString InPath)
    {
        auto Msg = FCk_Message_VatGym_SetCollection(InPath);
        for (auto Tag : Get_AllStationTags())
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
        }
    }

    UFUNCTION(Exec, DisplayName="Vat Gym - Play Clip (loop)")
    void Ck_GymVat_PlayClip(FString InClipName, float32 InRate = 1.0f, float32 InFadeSeconds = 0.4f)
    {
        auto Msg = FCk_Message_VatGym_PlayClip();
        Msg.ClipName = FName(InClipName);
        Msg.Rate = InRate;
        Msg.FadeSeconds = InFadeSeconds;
        Msg.Once = false;
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_ClipCycle");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Vat Gym - Play Clip Once")
    void Ck_GymVat_PlayOnce(FString InClipName, float32 InRate = 1.0f)
    {
        auto Msg = FCk_Message_VatGym_PlayClip();
        Msg.ClipName = FName(InClipName);
        Msg.Rate = InRate;
        Msg.FadeSeconds = 0.0f;
        Msg.Once = true;
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_ClipCycle");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Vat Gym - Set Play Rate")
    void Ck_GymVat_SetRate(float32 InRate = 1.0f)
    {
        // Every send goes through here, panel and console alike, so the panel's readout can never
        // disagree with the rate the stations were actually told to run at.
        _LastRateSent = InRate;

        auto Msg = FCk_Message_VatGym_SetRate(InRate);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_ClipCycle");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Vat Gym - Stop (freeze)")
    void Ck_GymVat_Stop()
    {
        auto Msg = FCk_Message_VatGym_Stop();
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_ClipCycle");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Vat Gym - Auto All [0/1]")
    void Ck_GymVat_Auto(int32 InEnabled = 1)
    {
        auto Msg = FCk_Message_Gym_AutoSet(InEnabled != 0);
        for (auto Tag : Get_AllStationTags())
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
        }
    }

    private void Request_AutoClipCycle()
    {
        auto Msg = FCk_Message_Gym_AutoSet(true);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_ClipCycle");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    private void Request_AutoCrowdField()
    {
        auto Msg = FCk_Message_Gym_AutoSet(true);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_CrowdField");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // The numeric knobs are preset rings: a crowd count and a turn rate have three or four interesting
    // values each, and typing one was never the point. What genuinely needs typing is a NAME - an
    // asset path or a baked clip - so those three commands stay on the console and get a Status row
    // that spells out the arguments, rather than leaving a reader to conclude the gym cannot do it.
    //--------------------------------------------------------------------------------------------------------------------------

    private void Request_StepRate()
    {
        if (_LastRateSent < 0.4f)      { Ck_GymVat_SetRate(0.5f); }
        else if (_LastRateSent < 0.9f) { Ck_GymVat_SetRate(1.0f); }
        else if (_LastRateSent < 1.9f) { Ck_GymVat_SetRate(2.0f); }
        else                           { Ck_GymVat_SetRate(0.25f); }
    }

    // 100 is the authored field size the placard talks about; 25 reads as individuals, 400 and 1000
    // are the stress steps (the station clamps at 2000).
    private void Request_StepFieldCount()
    {
        _FieldCount = _FieldCount == 25 ? 100 : _FieldCount == 100 ? 400 : _FieldCount == 400 ? 1000 : 25;

        auto Msg = FCk_Message_VatGym_FieldCount(_FieldCount);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_CrowdField");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    // 30 is the authored rate; 0 parks the turntable so a still frame can be compared against the
    // turning one, which is the whole point of the normals check.
    private void Request_StepTurnRate()
    {
        _TurnRateDegreesPerSecond = _TurnRateDegreesPerSecond < 1.0f ? 30.0f
            : _TurnRateDegreesPerSecond < 31.0f ? 90.0f
            : _TurnRateDegreesPerSecond < 91.0f ? 180.0f
            : 0.0f;

        auto Msg = FCk_Message_VatGym_TurnRate(_TurnRateDegreesPerSecond);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_Turntable");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    FString Get_ControlPanelTitle() override
    {
        return "VERTEX ANIMATION TEXTURES";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("CLIP CYCLE"));
        Rows.Add(CkGym_Control::Action(EKeys::Z, "Z", "Stop (freeze on frame)"));
        Rows.Add(CkGym_Control::Cycle(EKeys::T, "T", "Play rate", f"{_LastRateSent :.2}x"));
        Rows.Add(CkGym_Control::Action(EKeys::U, "U", "Auto-drive clip cycle"));

        Rows.Add(CkGym_Control::Header("EVERY STATION"));
        Rows.Add(CkGym_Control::Action(EKeys::F, "F", "Auto-drive crowd field"));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::I, "I", "Auto-drive everything", _LastAutoSent, "sent ON", "sent off"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Restart all stations"));

        Rows.Add(CkGym_Control::Header("CROWD FIELD AND TURNTABLE"));
        Rows.Add(CkGym_Control::Cycle(EKeys::N, "N", "Crowd field count", f"{_FieldCount}"));
        Rows.Add(CkGym_Control::Cycle(EKeys::G, "G", "Turntable rate", f"{_TurnRateDegreesPerSecond} deg/s"));

        Rows.Add(CkGym_Control::Header("CONSOLE (free-range input the panel cannot express)"));
        Rows.Add(CkGym_Control::Status("Swap the VAT collection", "Ck_GymVat_SetCollection <path|AUTO>"));
        Rows.Add(CkGym_Control::Status("Loop a named clip", "Ck_GymVat_PlayClip <name> [rate] [fade]"));
        Rows.Add(CkGym_Control::Status("Play a named clip once", "Ck_GymVat_PlayOnce <name> [rate]"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Rows 0, 4, 8 and 11 are headers, which hold no key and never arrive here.
        if (InRowIndex == 1) { Ck_GymVat_Stop(); }
        else if (InRowIndex == 2) { Request_StepRate(); }
        else if (InRowIndex == 3) { Request_AutoClipCycle(); }
        else if (InRowIndex == 5) { Request_AutoCrowdField(); }
        else if (InRowIndex == 6)
        {
            _LastAutoSent = !_LastAutoSent;
            Ck_GymVat_Auto(_LastAutoSent ? 1 : 0);
        }
        else if (InRowIndex == 7) { Ck_GymVat_RestartAll(); }
        else if (InRowIndex == 9) { Request_StepFieldCount(); }
        else if (InRowIndex == 10) { Request_StepTurnRate(); }
    }

    UFUNCTION(Exec, DisplayName="Vat Gym - Restart All")
    void Ck_GymVat_RestartAll()
    {
        Request_StartGym();
    }
}
