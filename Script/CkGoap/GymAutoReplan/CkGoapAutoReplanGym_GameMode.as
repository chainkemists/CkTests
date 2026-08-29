// Language=angelscript

//============================================================================
// CkGoapAutoReplan_Gym - Replan-policy showcase
//
// Three stations pinning each of the supported replan policies:
//   A - Explicit            (manual replan only)
//   B - OnWorldStateDirty   (throttled 0.5s)
//   C - OnCostDirty         (auto cost-bump -> plan flips)
//
// Each station auto-flips its Flip WS key 10x/sec and counts plan completions
// vs WS changes. The discrepancy teaches the policy.
//============================================================================

class ACk_GoapAutoReplanGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GoapAutoReplanGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_GoapAutoReplanGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Goap.AutoReplan.Explicit", "STATION A / EXPLICIT",
            "Manual replan only.\nUse the control panel's [R] row."));

        Stations.Add(MakeStationPayload(n"Gym.Goap.AutoReplan.OnWSDirty", "STATION B / OnWSDirty",
            "Throttled to one replan per 0.5s window."));

        Stations.Add(MakeStationPayload(n"Gym.Goap.AutoReplan.OnCostDirty", "STATION C / OnCostDirty",
            "Replan triggered by cost changes."));

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
        Station.Width = 8.0f;
        Station.Height = 6.0f;
        Station.AutoSize = true;
        return Station;
    }

    void Request_StartGym() override
    {
        Spawn_Station("Gym.Goap.AutoReplan.Explicit", 0);
        Spawn_Station("Gym.Goap.AutoReplan.OnWSDirty", 1);
        Spawn_Station("Gym.Goap.AutoReplan.OnCostDirty", 2);
    }

    private void Spawn_Station(FString InTag, int32 InMode)
    {
        auto Params = FCk_GoapGym_AutoReplan_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        Params.Mode = InMode;
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_GoapGym_AutoReplan_Station,
            FInstancedStruct::Make(Params));
    }

    private void DoReplanExplicit()
    {
        auto Entity = Get_StationHandle("Gym.Goap.AutoReplan.Explicit");
        if (ck::Is_NOT_Valid(Entity)) { return; }
        auto Marker = FCk_Fragment_GoapGym_ForceReplanPending();
        Entity.Add_Fragment(Marker);
    }

    //--------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Station A's whole point is that nothing replans it unless a human asks - so the ask has to be
    // visible. B and C need no controls: they replan themselves, which is what is being compared.
    //--------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GOAP: REPLAN POLICIES";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Station A: replan now"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { DoReplanExplicit(); }
    }
}
