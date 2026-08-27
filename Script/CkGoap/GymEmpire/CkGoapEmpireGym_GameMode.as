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

    UFUNCTION(Exec, DisplayName="Goap.Empire.ToggleFood")
    void Goap_Empire_ToggleFood() { Flip(n"Gym.Goap.WS.Empire.HasFood"); }

    UFUNCTION(Exec, DisplayName="Goap.Empire.ToggleGold")
    void Goap_Empire_ToggleGold() { Flip(n"Gym.Goap.WS.Empire.HasGold"); }

    UFUNCTION(Exec, DisplayName="Goap.Empire.ToggleWood")
    void Goap_Empire_ToggleWood() { Flip(n"Gym.Goap.WS.Empire.HasWood"); }

    UFUNCTION(Exec, DisplayName="Goap.Empire.ToggleBarracks")
    void Goap_Empire_ToggleBarracks() { Flip(n"Gym.Goap.WS.Empire.BarracksBuilt"); }

    UFUNCTION(Exec, DisplayName="Goap.Empire.ToggleFeudal")
    void Goap_Empire_ToggleFeudal() { Flip(n"Gym.Goap.WS.Empire.FeudalResearched"); }

    UFUNCTION(Exec, DisplayName="Goap.Empire.Reset")
    void Goap_Empire_Reset()
    {
        Set(n"Gym.Goap.WS.Empire.HasFood", false);
        Set(n"Gym.Goap.WS.Empire.HasGold", false);
        Set(n"Gym.Goap.WS.Empire.HasWood", false);
        Set(n"Gym.Goap.WS.Empire.BarracksBuilt", false);
        Set(n"Gym.Goap.WS.Empire.FeudalResearched", false);
    }
}
