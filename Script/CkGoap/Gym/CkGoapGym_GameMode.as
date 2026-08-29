// Language=angelscript

//============================================================================
// CkGoap_Gym - Main Gym GameMode + PlayerController
//
// Spawns 7 stations of ascending complexity:
//   1. Open Door         - atomic plan
//   2. Make Tea          - 4-step linear chain (intentional PlanFailed demo
//                          ingredient drop; opts out of always-valid-plan tenet)
//   3. Cross River       - 3-branch cost selection
//   4. Patrol Route      - composite Action, chain extends to [Root, DoPatrol]
//   5. Survival Decision - two independent ActionSets on one entity
//   6. Combat Brain      - 4-tier canonical hierarchy (spec 2.2)
//   7. Opt-Out Demo      - intentional permanent PlanFailed via
//                          _AllowPlanFailed=true; counterpart to MakeTea
//
// Each station is its own ECS entity tagged with a station identity gameplay
// tag. The control-panel rows resolve a station entity by tag, then locate its
// named WorldState (created in DoConstruct with a gym-specific name tag) via
// utils_goap_world_state::Find_ByName and read or mutate it directly. The Goap
// runtime reacts via OnWorldStateDirty replan policies on each root.
//============================================================================

class ACk_GoapGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_GoapGym_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_GoapGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Goap.Station.OpenDoor", "STATION 1 / OPEN DOOR",
            "Atomic plan.\nGoal: Door.IsOpen=true."));

        Stations.Add(MakeStationPayload(n"Gym.Goap.Station.MakeTea", "STATION 2 / MAKE TEA",
            "4-step dependency chain.\nGoal: TeaServed=true."));

        Stations.Add(MakeStationPayload(n"Gym.Goap.Station.CrossRiver", "STATION 3 / CROSS RIVER",
            "Branching cost-sensitive plan.\nGoal: Crossed=true."));

        Stations.Add(MakeStationPayload(n"Gym.Goap.Station.Patrol", "STATION 4 / PATROL ROUTE",
            "Multi-tier Planner (U11.6).\nGoToWaypoint + Observe promoted to Planners.\nChain: [Root, Composite, Leaf]."));

        Stations.Add(MakeStationPayload(n"Gym.Goap.Station.Survival", "STATION 5 / SURVIVAL DECISION",
            "Two independent ActionSets.\nGoals: Hungry=false AND SafeFromThreat=true."));

        Stations.Add(MakeStationPayload(n"Gym.Goap.Station.CombatBrain", "STATION 6 / COMBAT BRAIN",
            "4-tier canonical Planner (spec 2.2).\nAlive -> Engage -> Light/Heavy -> leaves.\nSibling promotions at tier 3."));

        Stations.Add(MakeStationPayload(n"Gym.Goap.Station.OptOutDemo", "STATION 7 / OPT-OUT DEMO",
            "Intentional _AllowPlanFailed=true.\nGoal is structurally unreachable.\nDebugger should show OPT-OUT indicator."));

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
        Spawn_OpenDoor("Gym.Goap.Station.OpenDoor");
        Spawn_MakeTea("Gym.Goap.Station.MakeTea");
        Spawn_CrossRiver("Gym.Goap.Station.CrossRiver");
        Spawn_Patrol("Gym.Goap.Station.Patrol");
        Spawn_Survival("Gym.Goap.Station.Survival");
        Spawn_CombatBrain("Gym.Goap.Station.CombatBrain");
        Spawn_OptOutDemo("Gym.Goap.Station.OptOutDemo");
    }

    private void Spawn_OpenDoor(FString InTag)
    {
        auto Params = FCk_GoapGym_OpenDoor_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_GoapGym_OpenDoor_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_MakeTea(FString InTag)
    {
        auto Params = FCk_GoapGym_MakeTea_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_GoapGym_MakeTea_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_CrossRiver(FString InTag)
    {
        auto Params = FCk_GoapGym_CrossRiver_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_GoapGym_CrossRiver_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_Patrol(FString InTag)
    {
        auto Params = FCk_GoapGym_Patrol_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_GoapGym_Patrol_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_Survival(FString InTag)
    {
        auto Params = FCk_GoapGym_Survival_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_GoapGym_Survival_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_CombatBrain(FString InTag)
    {
        auto Params = FCk_GoapGym_CombatBrain_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_GoapGym_CombatBrain_Station,
            FInstancedStruct::Make(Params));
    }

    private void Spawn_OptOutDemo(FString InTag)
    {
        auto Params = FCk_GoapGym_OptOutDemo_Station_SpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_GoapGym_OptOutDemo_Station,
            FInstancedStruct::Make(Params));
    }

    //--------------------------------------------------------------------------
    // WS lookup helpers - locate the named WorldState child of a station entity.
    // Each station creates its WS in DoConstruct with a name tag matching the
    // station's domain (Door / Tea / CrossRiver / Patrol / Survival).
    //--------------------------------------------------------------------------

    private FCk_Handle_Goap_WorldState
    Find_StationWS(FString InStationTag, FName InWsName)
    {
        auto Entity = Get_StationHandle(InStationTag);
        if (ck::Is_NOT_Valid(Entity)) { return FCk_Handle_Goap_WorldState(); }
        return utils_goap_world_state::Find_ByName(Entity,
            utils_gameplay_tag::ResolveGameplayTag(InWsName));
    }

    private void Flip(FCk_Handle_Goap_WorldState InWS, FName InKey)
    {
        if (ck::Is_NOT_Valid(InWS)) { return; }
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(InKey);
        auto Cur = utils_goap_world_state::Get_Value(InWS, Tag);
        utils_goap_world_state::Set_Value(InWS, Tag, !Cur);
    }

    private void Set(FCk_Handle_Goap_WorldState InWS, FName InKey, bool InValue)
    {
        if (ck::Is_NOT_Valid(InWS)) { return; }
        utils_goap_world_state::Set_Value(InWS,
            utils_gameplay_tag::ResolveGameplayTag(InKey), InValue);
    }

    private bool Get(FCk_Handle_Goap_WorldState InWS, FName InKey)
    {
        if (ck::Is_NOT_Valid(InWS)) { return false; }
        return utils_goap_world_state::Get_Value(InWS,
            utils_gameplay_tag::ResolveGameplayTag(InKey));
    }

    //--------------------------------------------------------------------------
    // Per-station WS lookups - one call site each, so the row builder and the
    // dispatch cannot drift on which WS a station owns.
    //--------------------------------------------------------------------------

    private FCk_Handle_Goap_WorldState Find_DoorWS()
    { return Find_StationWS("Gym.Goap.Station.OpenDoor", n"Gym.Goap.WS.Door"); }

    private FCk_Handle_Goap_WorldState Find_TeaWS()
    { return Find_StationWS("Gym.Goap.Station.MakeTea", n"Gym.Goap.WS.Tea"); }

    private FCk_Handle_Goap_WorldState Find_RiverWS()
    { return Find_StationWS("Gym.Goap.Station.CrossRiver", n"Gym.Goap.WS.CrossRiver"); }

    private FCk_Handle_Goap_WorldState Find_PatrolWS()
    { return Find_StationWS("Gym.Goap.Station.Patrol", n"Gym.Goap.WS.Patrol"); }

    private FCk_Handle_Goap_WorldState Find_SurvivalWS()
    { return Find_StationWS("Gym.Goap.Station.Survival", n"Gym.Goap.WS.Survival"); }

    private FCk_Handle_Goap_WorldState Find_CombatBrainWS()
    { return Find_StationWS("Gym.Goap.Station.CombatBrain", n"Gym.Goap.WS.CombatBrain"); }

    //--------------------------------------------------------------------------
    // Station resets and scripted scenarios
    //--------------------------------------------------------------------------

    private void DoResetTea()
    {
        auto WS = Find_TeaWS();
        Set(WS, n"Gym.Goap.WS.Tea.HasKettle", true);
        Set(WS, n"Gym.Goap.WS.Tea.HasWater", true);
        Set(WS, n"Gym.Goap.WS.Tea.HasTeaLeaves", true);
        Set(WS, n"Gym.Goap.WS.Tea.HasCup", true);
        Set(WS, n"Gym.Goap.WS.Tea.WaterBoiled", false);
        Set(WS, n"Gym.Goap.WS.Tea.TeaSteeped", false);
        Set(WS, n"Gym.Goap.WS.Tea.TeaPoured", false);
        Set(WS, n"Gym.Goap.WS.Tea.TeaServed", false);
    }

    private void DoResetRiver()
    {
        auto WS = Find_RiverWS();
        Set(WS, n"Gym.Goap.WS.CrossRiver.BridgeIsOpen", true);
        Set(WS, n"Gym.Goap.WS.CrossRiver.HasCoin", true);
        Set(WS, n"Gym.Goap.WS.CrossRiver.Crossed", false);
    }

    private void DoResetPatrol()
    {
        auto WS = Find_PatrolWS();
        Set(WS, n"Gym.Goap.WS.Patrol.AtWaypoint", false);
        Set(WS, n"Gym.Goap.WS.Patrol.AreaScanned", false);
        Set(WS, n"Gym.Goap.WS.Patrol.AreaPatrolled", false);
    }

    private void DoResetSurvival()
    {
        auto WS = Find_SurvivalWS();
        Set(WS, n"Gym.Goap.WS.Survival.Hungry", true);
        Set(WS, n"Gym.Goap.WS.Survival.HasFood", false);
        Set(WS, n"Gym.Goap.WS.Survival.ThreatActive", true);
        Set(WS, n"Gym.Goap.WS.Survival.HasWeapon", true);
        Set(WS, n"Gym.Goap.WS.Survival.SafeFromThreat", false);
    }

    private void DoResetCombatBrain()
    {
        auto WS = Find_CombatBrainWS();
        Set(WS, n"Gym.Goap.WS.CombatBrain.EnemyVisible", false);
        Set(WS, n"Gym.Goap.WS.CombatBrain.WeaponEquipped", false);
        Set(WS, n"Gym.Goap.WS.CombatBrain.StaminaHigh", false);
        Set(WS, n"Gym.Goap.WS.CombatBrain.EnemyHit", false);
        Set(WS, n"Gym.Goap.WS.CombatBrain.EnemyAttacked", false);
        Set(WS, n"Gym.Goap.WS.CombatBrain.EnemyDead", false);
    }

    // Drive the entire chain to terminal state - useful for showing the
    // plan running to completion without manually flipping every key.
    private void DoCompleteCombatBrain()
    {
        auto WS = Find_CombatBrainWS();
        Set(WS, n"Gym.Goap.WS.CombatBrain.EnemyVisible", true);
        Set(WS, n"Gym.Goap.WS.CombatBrain.WeaponEquipped", true);
        Set(WS, n"Gym.Goap.WS.CombatBrain.StaminaHigh", true);
        Set(WS, n"Gym.Goap.WS.CombatBrain.EnemyHit", true);
        Set(WS, n"Gym.Goap.WS.CombatBrain.EnemyAttacked", true);
        Set(WS, n"Gym.Goap.WS.CombatBrain.EnemyDead", true);
    }

    //--------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Seven stations replan off these keys, so the panel is grouped by station and every toggle
    // reads its key back from the world state - the panel is the WS view as much as it is the input.
    //
    // The one-way setters (the coin, the three Patrol keys) stay Actions rather than becoming
    // toggles, because the plan being demonstrated depends on them being irreversible except through
    // the station's Reset. Their live value shows as the row greying out once it is spent.
    //
    // Station 7 (Opt-Out Demo) has no controls: its goal is structurally unreachable by design.
    //--------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GOAP: STATIONS 1-7";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        auto DoorWS = Find_DoorWS();
        Rows.Add(CkGym_Control::Header("1 / OPEN DOOR"));
        Rows.Add(CkGym_Control::Toggle(EKeys::J, "J", "Door.IsOpen", Get(DoorWS, n"Gym.Goap.WS.Door.IsOpen")));

        auto TeaWS = Find_TeaWS();
        Rows.Add(CkGym_Control::Header("2 / MAKE TEA"));
        Rows.Add(CkGym_Control::Toggle(EKeys::K, "K", "HasKettle",    Get(TeaWS, n"Gym.Goap.WS.Tea.HasKettle")));
        Rows.Add(CkGym_Control::Toggle(EKeys::L, "L", "HasWater",     Get(TeaWS, n"Gym.Goap.WS.Tea.HasWater")));
        Rows.Add(CkGym_Control::Toggle(EKeys::M, "M", "HasTeaLeaves", Get(TeaWS, n"Gym.Goap.WS.Tea.HasTeaLeaves")));
        Rows.Add(CkGym_Control::Toggle(EKeys::N, "N", "HasCup",       Get(TeaWS, n"Gym.Goap.WS.Tea.HasCup")));
        Rows.Add(CkGym_Control::Action(EKeys::One, "1", "Reset the tea WS"));

        auto RiverWS = Find_RiverWS();
        auto HasCoin = Get(RiverWS, n"Gym.Goap.WS.CrossRiver.HasCoin");
        Rows.Add(CkGym_Control::Header("3 / CROSS RIVER"));
        Rows.Add(CkGym_Control::Toggle(EKeys::B, "B", "BridgeIsOpen", Get(RiverWS, n"Gym.Goap.WS.CrossRiver.BridgeIsOpen")));
        Rows.Add(CkGym_Control::Action(EKeys::F, "F", "Spend the coin (one-way)", HasCoin));
        Rows.Add(CkGym_Control::Action(EKeys::Two, "2", "Reset the river WS"));

        auto PatrolWS = Find_PatrolWS();
        Rows.Add(CkGym_Control::Header("4 / PATROL ROUTE"));
        Rows.Add(CkGym_Control::Action(EKeys::G, "G", "Set AtWaypoint",
            Get(PatrolWS, n"Gym.Goap.WS.Patrol.AtWaypoint") == false));
        Rows.Add(CkGym_Control::Action(EKeys::I, "I", "Set AreaScanned",
            Get(PatrolWS, n"Gym.Goap.WS.Patrol.AreaScanned") == false));
        Rows.Add(CkGym_Control::Action(EKeys::O, "O", "Set AreaPatrolled",
            Get(PatrolWS, n"Gym.Goap.WS.Patrol.AreaPatrolled") == false));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3", "Reset the patrol WS"));

        auto SurvivalWS = Find_SurvivalWS();
        Rows.Add(CkGym_Control::Header("5 / SURVIVAL DECISION"));
        Rows.Add(CkGym_Control::Toggle(EKeys::P, "P", "Hungry",       Get(SurvivalWS, n"Gym.Goap.WS.Survival.Hungry")));
        Rows.Add(CkGym_Control::Toggle(EKeys::T, "T", "HasFood",      Get(SurvivalWS, n"Gym.Goap.WS.Survival.HasFood")));
        Rows.Add(CkGym_Control::Toggle(EKeys::U, "U", "ThreatActive", Get(SurvivalWS, n"Gym.Goap.WS.Survival.ThreatActive")));
        Rows.Add(CkGym_Control::Toggle(EKeys::V, "V", "HasWeapon",    Get(SurvivalWS, n"Gym.Goap.WS.Survival.HasWeapon")));
        Rows.Add(CkGym_Control::Action(EKeys::Four, "4", "Reset the survival WS"));

        auto CombatWS = Find_CombatBrainWS();
        Rows.Add(CkGym_Control::Header("6 / COMBAT BRAIN"));
        Rows.Add(CkGym_Control::Toggle(EKeys::X, "X", "EnemyVisible",   Get(CombatWS, n"Gym.Goap.WS.CombatBrain.EnemyVisible")));
        Rows.Add(CkGym_Control::Toggle(EKeys::Y, "Y", "WeaponEquipped", Get(CombatWS, n"Gym.Goap.WS.CombatBrain.WeaponEquipped")));
        Rows.Add(CkGym_Control::Toggle(EKeys::Z, "Z", "StaminaHigh",    Get(CombatWS, n"Gym.Goap.WS.CombatBrain.StaminaHigh")));
        Rows.Add(CkGym_Control::Action(EKeys::Five, "5", "Drive the chain to EnemyDead"));
        Rows.Add(CkGym_Control::Action(EKeys::Six,  "6", "Reset the combat WS"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Rows 0, 2, 8, 12, 17 and 23 are headers - no key, never dispatched, but they DO occupy an
        // index. Keep this branch list in the same order as Get_ControlRows above.
        if (InRowIndex == 1) { Flip(Find_DoorWS(), n"Gym.Goap.WS.Door.IsOpen"); }

        else if (InRowIndex == 3) { Flip(Find_TeaWS(), n"Gym.Goap.WS.Tea.HasKettle"); }
        else if (InRowIndex == 4) { Flip(Find_TeaWS(), n"Gym.Goap.WS.Tea.HasWater"); }
        else if (InRowIndex == 5) { Flip(Find_TeaWS(), n"Gym.Goap.WS.Tea.HasTeaLeaves"); }
        else if (InRowIndex == 6) { Flip(Find_TeaWS(), n"Gym.Goap.WS.Tea.HasCup"); }
        else if (InRowIndex == 7) { DoResetTea(); }

        else if (InRowIndex == 9)  { Flip(Find_RiverWS(), n"Gym.Goap.WS.CrossRiver.BridgeIsOpen"); }
        else if (InRowIndex == 10) { Set(Find_RiverWS(), n"Gym.Goap.WS.CrossRiver.HasCoin", false); }
        else if (InRowIndex == 11) { DoResetRiver(); }

        else if (InRowIndex == 13) { Set(Find_PatrolWS(), n"Gym.Goap.WS.Patrol.AtWaypoint", true); }
        else if (InRowIndex == 14) { Set(Find_PatrolWS(), n"Gym.Goap.WS.Patrol.AreaScanned", true); }
        else if (InRowIndex == 15) { Set(Find_PatrolWS(), n"Gym.Goap.WS.Patrol.AreaPatrolled", true); }
        else if (InRowIndex == 16) { DoResetPatrol(); }

        else if (InRowIndex == 18) { Flip(Find_SurvivalWS(), n"Gym.Goap.WS.Survival.Hungry"); }
        else if (InRowIndex == 19) { Flip(Find_SurvivalWS(), n"Gym.Goap.WS.Survival.HasFood"); }
        else if (InRowIndex == 20) { Flip(Find_SurvivalWS(), n"Gym.Goap.WS.Survival.ThreatActive"); }
        else if (InRowIndex == 21) { Flip(Find_SurvivalWS(), n"Gym.Goap.WS.Survival.HasWeapon"); }
        else if (InRowIndex == 22) { DoResetSurvival(); }

        else if (InRowIndex == 24) { Flip(Find_CombatBrainWS(), n"Gym.Goap.WS.CombatBrain.EnemyVisible"); }
        else if (InRowIndex == 25) { Flip(Find_CombatBrainWS(), n"Gym.Goap.WS.CombatBrain.WeaponEquipped"); }
        else if (InRowIndex == 26) { Flip(Find_CombatBrainWS(), n"Gym.Goap.WS.CombatBrain.StaminaHigh"); }
        else if (InRowIndex == 27) { DoCompleteCombatBrain(); }
        else if (InRowIndex == 28) { DoResetCombatBrain(); }
    }
}
