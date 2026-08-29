// Language=angelscript

//============================================================================
// CkGoapFEAR_Gym - single-station F.E.A.R. combat AI
//
// Control panel rows (each toggle reads its WS key back live):
//   [J] EnemyVisible   [K] AtCover         [L] BehindEnemy
//   [M] HasAmmo        [N] HasAmmoReserve  [O] HeardSound
//   [R] Reset          - restore initial WS.
//   [B] Ideal ambush   - set up the iconic flank-ambush scenario
//                        (Visible+BehindEnemy+HasAmmo+AtCover all true). Plan
//                        should resolve to [AttackEnemy -> AttackFromFlank]
//                        cost 0.5.
//============================================================================

class ACk_GoapFEARGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GoapFEARGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_GoapFEARGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        Stations.Add(MakeStationPayload(n"Gym.GoapFEAR.Station.Combatant",
            "F.E.A.R. COMBATANT",
            "Canonical GOAP enemy AI - toggle WS from the control panel."));
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
        Station.Height = 7.0f;
        Station.AutoSize = true;
        return Station;
    }

    void Request_StartGym() override
    {
        auto Params = FCk_GoapFEARGym_Combatant_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform("Gym.GoapFEAR.Station.Combatant",
            ECk_GymStation_Anchor::PanelCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.GoapFEAR.Station.Combatant"),
            UCk_EntityScript_GoapFEARGym_Combatant_Station,
            FInstancedStruct::Make(Params));
    }

    private FCk_Handle_Goap_WorldState Find_FEARWS()
    {
        auto Entity = Get_StationHandle("Gym.GoapFEAR.Station.Combatant");
        if (ck::Is_NOT_Valid(Entity)) { return FCk_Handle_Goap_WorldState(); }
        return utils_goap_world_state::Find_ByName(Entity,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapFEAR.WS.Combatant"));
    }

    private void Flip(FName InKey)
    {
        auto WS = Find_FEARWS();
        if (ck::Is_NOT_Valid(WS)) { return; }
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(InKey);
        auto Cur = utils_goap_world_state::Get_Value(WS, Tag);
        utils_goap_world_state::Set_Value(WS, Tag, !Cur);
    }

    private void Set(FName InKey, bool InValue)
    {
        auto WS = Find_FEARWS();
        if (ck::Is_NOT_Valid(WS)) { return; }
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey), InValue);
    }

    private bool Get(FName InKey)
    {
        auto WS = Find_FEARWS();
        if (ck::Is_NOT_Valid(WS)) { return false; }
        return utils_goap_world_state::Get_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey));
    }

    private void DoReset()
    {
        Set(n"Gym.GoapFEAR.WS.Combatant.HasAmmo",          true);
        Set(n"Gym.GoapFEAR.WS.Combatant.HasAmmoReserve",   true);
        Set(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible",     false);
        Set(n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized", false);
        Set(n"Gym.GoapFEAR.WS.Combatant.AtCover",          false);
        Set(n"Gym.GoapFEAR.WS.Combatant.BehindEnemy",      false);
        Set(n"Gym.GoapFEAR.WS.Combatant.HeardSound",       false);
        Set(n"Gym.GoapFEAR.WS.Combatant.Patrolling",       false);
    }

    // The iconic F.E.A.R. flank-ambush moment. Should yield
    //   [AttackEnemy -> AttackFromFlank]   cost 0.5
    // - the cheapest possible plan, where the agent has already maneuvered
    // behind the target before opening fire.
    private void DoIdealAmbush()
    {
        Set(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible",   true);
        Set(n"Gym.GoapFEAR.WS.Combatant.BehindEnemy",    true);
        Set(n"Gym.GoapFEAR.WS.Combatant.HasAmmo",        true);
        Set(n"Gym.GoapFEAR.WS.Combatant.AtCover",        true);
    }

    //--------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // The plan the station prints is a function of these six keys, so they belong beside it rather
    // than behind a list of command names. The Set/Clear command pairs collapse into one toggle each -
    // the key reads back live, so there is nothing a separate Clear could say that the toggle cannot.
    //--------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GOAP: F.E.A.R. COMBATANT";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("WORLD STATE"));
        Rows.Add(CkGym_Control::Toggle(EKeys::J, "J", "EnemyVisible",   Get(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible")));
        Rows.Add(CkGym_Control::Toggle(EKeys::K, "K", "AtCover",        Get(n"Gym.GoapFEAR.WS.Combatant.AtCover")));
        Rows.Add(CkGym_Control::Toggle(EKeys::L, "L", "BehindEnemy",    Get(n"Gym.GoapFEAR.WS.Combatant.BehindEnemy")));
        Rows.Add(CkGym_Control::Toggle(EKeys::M, "M", "HasAmmo",        Get(n"Gym.GoapFEAR.WS.Combatant.HasAmmo")));
        Rows.Add(CkGym_Control::Toggle(EKeys::N, "N", "HasAmmoReserve", Get(n"Gym.GoapFEAR.WS.Combatant.HasAmmoReserve")));
        Rows.Add(CkGym_Control::Toggle(EKeys::O, "O", "HeardSound",     Get(n"Gym.GoapFEAR.WS.Combatant.HeardSound")));

        Rows.Add(CkGym_Control::Header("SCENARIOS"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Ideal ambush (flank, cost 0.5)"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset to the initial WS"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Rows 0 and 7 are headers, which hold no key and never arrive here.
        if (InRowIndex == 1) { Flip(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible"); }
        else if (InRowIndex == 2) { Flip(n"Gym.GoapFEAR.WS.Combatant.AtCover"); }
        else if (InRowIndex == 3) { Flip(n"Gym.GoapFEAR.WS.Combatant.BehindEnemy"); }
        else if (InRowIndex == 4) { Flip(n"Gym.GoapFEAR.WS.Combatant.HasAmmo"); }
        else if (InRowIndex == 5) { Flip(n"Gym.GoapFEAR.WS.Combatant.HasAmmoReserve"); }
        else if (InRowIndex == 6) { Flip(n"Gym.GoapFEAR.WS.Combatant.HeardSound"); }
        else if (InRowIndex == 8) { DoIdealAmbush(); }
        else if (InRowIndex == 9) { DoReset(); }
    }
}
