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
    // Broadcast plumbing (messages travel as raw structs — mirror the
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

    UFUNCTION(Exec, DisplayName="Vat Gym - Crowd Field Count")
    void Ck_GymVat_FieldCount(int32 InCount = 100)
    {
        auto Msg = FCk_Message_VatGym_FieldCount(InCount);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_CrowdField");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Vat Gym - Turntable Rate (deg/s)")
    void Ck_GymVat_TurnRate(float32 InDegreesPerSecond = 30.0f)
    {
        auto Msg = FCk_Message_VatGym_TurnRate(InDegreesPerSecond);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_Turntable");
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

    UFUNCTION(Exec, DisplayName="Vat Gym - Auto Clip Cycle On")
    void Ck_GymVat_AutoClipCycle()
    {
        auto Msg = FCk_Message_Gym_AutoSet(true);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_ClipCycle");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Vat Gym - Auto Crowd Field On")
    void Ck_GymVat_AutoCrowdField()
    {
        auto Msg = FCk_Message_Gym_AutoSet(true);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_VatGym_CrowdField");
        for (auto Entity : Entities) { utils_messaging::Broadcast(Entity, Msg); }
    }

    UFUNCTION(Exec, DisplayName="Vat Gym - Restart All")
    void Ck_GymVat_RestartAll()
    {
        Request_StartGym();
    }
}
