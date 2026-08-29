// Language=angelscript

//============================================================================
// CkGoapEmpire_Gym - compact AoE-style 5-action plan
//============================================================================

class ACk_GoapEmpireGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GoapEmpireGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_GoapEmpireGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        Stations.Add(MakeStationPayload(n"Gym.Goap.Empire.Research", "EMPIRE / FEUDAL RESEARCH",
            "5-step empire plan. Goal: FeudalResearched=true."));
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
        Station.Width = 9.0f;
        Station.Height = 6.0f;
        Station.AutoSize = true;
        return Station;
    }

    void Request_StartGym() override
    {
        auto Params = FCk_GoapGym_Empire_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform("Gym.Goap.Empire.Research",
            ECk_GymStation_Anchor::PanelCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Goap.Empire.Research"),
            UCk_EntityScript_GoapGym_Empire_Station,
            FInstancedStruct::Make(Params));
    }

    private FCk_Handle_Goap_WorldState Find_EmpireWS()
    {
        auto Entity = Get_StationHandle("Gym.Goap.Empire.Research");
        if (ck::Is_NOT_Valid(Entity)) { return FCk_Handle_Goap_WorldState(); }
        return utils_goap_world_state::Find_ByName(Entity,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Empire"));
    }

    private void Flip(FName InKey)
    {
        auto WS = Find_EmpireWS();
        if (ck::Is_NOT_Valid(WS)) { return; }
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(InKey);
        auto Cur = utils_goap_world_state::Get_Value(WS, Tag);
        utils_goap_world_state::Set_Value(WS, Tag, !Cur);
    }

    private void Set(FName InKey, bool InValue)
    {
        auto WS = Find_EmpireWS();
        if (ck::Is_NOT_Valid(WS)) { return; }
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey), InValue);
    }

    private bool Get(FName InKey)
    {
        auto WS = Find_EmpireWS();
        if (ck::Is_NOT_Valid(WS)) { return false; }
        return utils_goap_world_state::Get_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey));
    }

    private void DoReset()
    {
        Set(n"Gym.Goap.WS.Empire.HasFood", false);
        Set(n"Gym.Goap.WS.Empire.HasGold", false);
        Set(n"Gym.Goap.WS.Empire.HasWood", false);
        Set(n"Gym.Goap.WS.Empire.BarracksBuilt", false);
        Set(n"Gym.Goap.WS.Empire.FeudalResearched", false);
    }

    //--------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Each toggle reads its world-state key back live, so the panel doubles as the WS readout the
    // station text used to be the only source of.
    //--------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GOAP: EMPIRE";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("WORLD STATE"));
        Rows.Add(CkGym_Control::Toggle(EKeys::J, "J", "HasFood",           Get(n"Gym.Goap.WS.Empire.HasFood")));
        Rows.Add(CkGym_Control::Toggle(EKeys::K, "K", "HasGold",           Get(n"Gym.Goap.WS.Empire.HasGold")));
        Rows.Add(CkGym_Control::Toggle(EKeys::L, "L", "HasWood",           Get(n"Gym.Goap.WS.Empire.HasWood")));
        Rows.Add(CkGym_Control::Toggle(EKeys::M, "M", "BarracksBuilt",     Get(n"Gym.Goap.WS.Empire.BarracksBuilt")));
        Rows.Add(CkGym_Control::Toggle(EKeys::N, "N", "FeudalResearched",  Get(n"Gym.Goap.WS.Empire.FeudalResearched")));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset all keys to false"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Row 0 is a header, which holds no key and never arrives here.
        if (InRowIndex == 1) { Flip(n"Gym.Goap.WS.Empire.HasFood"); }
        else if (InRowIndex == 2) { Flip(n"Gym.Goap.WS.Empire.HasGold"); }
        else if (InRowIndex == 3) { Flip(n"Gym.Goap.WS.Empire.HasWood"); }
        else if (InRowIndex == 4) { Flip(n"Gym.Goap.WS.Empire.BarracksBuilt"); }
        else if (InRowIndex == 5) { Flip(n"Gym.Goap.WS.Empire.FeudalResearched"); }
        else if (InRowIndex == 6) { DoReset(); }
    }
}
