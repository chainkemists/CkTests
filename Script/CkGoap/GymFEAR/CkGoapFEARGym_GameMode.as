// Language=angelscript

//============================================================================
// CkGoapFEAR_Gym - single-station F.E.A.R. combat AI
//
// Console commands (Goap.FEAR.*):
//   SetTargetVisible / ClearTargetVisible  - flips EnemyVisible.
//   ToggleAtCover                          - flips AtCover.
//   ToggleBehindEnemy                      - flips BehindEnemy.
//   ToggleHasAmmo                          - flips HasAmmo.
//   ToggleHasAmmoReserve                   - flips HasAmmoReserve.
//   SetHeardSound / ClearHeardSound        - flips HeardSound.
//   Reset                                  - restore initial WS.
//   IdealAmbush                            - set up the iconic flank-ambush
//                                            scenario (Visible+BehindEnemy+
//                                            HasAmmo+AtCover all true). Plan
//                                            should resolve to
//                                            [AttackEnemy -> AttackFromFlank]
//                                            cost 0.5.
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
            "Canonical GOAP enemy AI - toggle WS via Goap.FEAR.* commands."));
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

    UFUNCTION(Exec, DisplayName="Goap.FEAR.SetTargetVisible")
    void Goap_FEAR_SetTargetVisible() { Set(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible", true); }

    UFUNCTION(Exec, DisplayName="Goap.FEAR.ClearTargetVisible")
    void Goap_FEAR_ClearTargetVisible() { Set(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible", false); }

    UFUNCTION(Exec, DisplayName="Goap.FEAR.ToggleAtCover")
    void Goap_FEAR_ToggleAtCover() { Flip(n"Gym.GoapFEAR.WS.Combatant.AtCover"); }

    UFUNCTION(Exec, DisplayName="Goap.FEAR.ToggleBehindEnemy")
    void Goap_FEAR_ToggleBehindEnemy() { Flip(n"Gym.GoapFEAR.WS.Combatant.BehindEnemy"); }

    UFUNCTION(Exec, DisplayName="Goap.FEAR.ToggleHasAmmo")
    void Goap_FEAR_ToggleHasAmmo() { Flip(n"Gym.GoapFEAR.WS.Combatant.HasAmmo"); }

    UFUNCTION(Exec, DisplayName="Goap.FEAR.ToggleHasAmmoReserve")
    void Goap_FEAR_ToggleHasAmmoReserve() { Flip(n"Gym.GoapFEAR.WS.Combatant.HasAmmoReserve"); }

    UFUNCTION(Exec, DisplayName="Goap.FEAR.SetHeardSound")
    void Goap_FEAR_SetHeardSound() { Set(n"Gym.GoapFEAR.WS.Combatant.HeardSound", true); }

    UFUNCTION(Exec, DisplayName="Goap.FEAR.ClearHeardSound")
    void Goap_FEAR_ClearHeardSound() { Set(n"Gym.GoapFEAR.WS.Combatant.HeardSound", false); }

    UFUNCTION(Exec, DisplayName="Goap.FEAR.Reset")
    void Goap_FEAR_Reset()
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
    UFUNCTION(Exec, DisplayName="Goap.FEAR.IdealAmbush")
    void Goap_FEAR_IdealAmbush()
    {
        Set(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible",   true);
        Set(n"Gym.GoapFEAR.WS.Combatant.BehindEnemy",    true);
        Set(n"Gym.GoapFEAR.WS.Combatant.HasAmmo",        true);
        Set(n"Gym.GoapFEAR.WS.Combatant.AtCover",        true);
    }
}
