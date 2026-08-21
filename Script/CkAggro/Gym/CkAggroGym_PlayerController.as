// Language=angelscript

class ACk_AggroGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Aggro.Chase", "Aggro + Chase",
            "Bursts of threat rotate the active target.\nThe guard eases toward whoever it aggros."));

        Stations.Add(MakeStationPayload(n"Gym.Aggro.Perception", "LoS Cone Perception",
            "An orbiter's threat holds while in the vision cone\nand decays ~5x once it slips out of sight."));

        Stations.Add(MakeStationPayload(n"Gym.Aggro.Stress", "Stress",
            "24 guards x 5 targets each, all selecting.\nThe visual twin of the ScaleSmoke autotest."));

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload MakeStationPayload(FName InTag, FString InTitle, FString InDesc)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString(InDesc));
        Station.Description = Desc;
        return Station;
    }

    void Request_StartGym() override
    {
        SpawnChase("Gym.Aggro.Chase", "AGGRO + CHASE",
            "Three attackers ring one guard. Every 2.5s a fresh burst of threat\nlands on the next attacker, so the active target rotates and the guard\nchases whoever it is currently aggro'd on.");

        SpawnPerception("Gym.Aggro.Perception", "LOS CONE PERCEPTION",
            "An attacker orbits the guard. Inside the vision cone it is perceived\nand keeps its threat; outside, threat decays ~5x faster. Perception is a\ncounted vote toggled on cone entry/exit.");

        SpawnStress("Gym.Aggro.Stress", "STRESS",
            "24 guards, each tracking 5 attackers, all running the pacer -> evaluate\n-> select pipeline. A random guard's active target is nudged each 0.5s.\nThe interactive twin of the ScaleSmoke autotest.");
    }

    private FCkAggroGym_Station_SpawnParams MakeParams(FString InTag, FString InTitle, FString InDesc)
    {
        auto Params = FCkAggroGym_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        Params.StationTitle = InTitle;
        Params.StationDescription = InDesc;
        return Params;
    }

    private void SpawnChase(FString InTag, FString InTitle, FString InDesc)
    {
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_AggroGym_Chase_Station,
            FInstancedStruct::Make(MakeParams(InTag, InTitle, InDesc)));
    }

    private void SpawnPerception(FString InTag, FString InTitle, FString InDesc)
    {
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_AggroGym_Perception_Station,
            FInstancedStruct::Make(MakeParams(InTag, InTitle, InDesc)));
    }

    private void SpawnStress(FString InTag, FString InTitle, FString InDesc)
    {
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_AggroGym_Stress_Station,
            FInstancedStruct::Make(MakeParams(InTag, InTitle, InDesc)));
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // One row. Everything here plays once and is then over, so re-running it IS the gym - and the console
    // command's name was the only documentation that the control existed at all.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "AGGRO";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Re-run every station"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Ck_GymAggro_RestartAll(); }
    }

    UFUNCTION(Exec, DisplayName="Aggro Gym - Restart All")
    void Ck_GymAggro_RestartAll()
    {
        Request_StartGym();
    }
};
