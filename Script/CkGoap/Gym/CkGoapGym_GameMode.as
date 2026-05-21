// Language=angelscript

//============================================================================
// CkGoap_Gym — Main Gym GameMode + PlayerController
//
// Spawns 5 stations of ascending complexity:
//   1. Open Door         — atomic plan
//   2. Make Tea          — 4-step linear chain
//   3. Cross River       — 3-branch cost selection
//   4. Patrol Route      — composite Action, chain extends to [Root, DoPatrol]
//   5. Survival Decision — two independent ActionSets on one entity
//
// Each station is its own ECS entity tagged with a station identity gameplay
// tag. The exec console commands resolve a station entity by tag, then locate
// its named WorldState (created in DoConstruct with a gym-specific name tag)
// via utils_goap_world_state::Find_ByName and mutate it directly. The Goap
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
            "Composite Action / chain extension.\nGoal: PatrolComplete=true."));

        Stations.Add(MakeStationPayload(n"Gym.Goap.Station.Survival", "STATION 5 / SURVIVAL DECISION",
            "Two independent ActionSets.\nGoals: Hungry=false AND SafeFromThreat=true."));

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

    //--------------------------------------------------------------------------
    // WS lookup helpers — locate the named WorldState child of a station entity.
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

    // ---- Open Door ----
    UFUNCTION(Exec, DisplayName="Goap.Door.Toggle")
    void Goap_Door_Toggle()
    {
        auto WS = Find_StationWS("Gym.Goap.Station.OpenDoor", n"Gym.Goap.WS.Door");
        Flip(WS, n"Gym.Goap.WS.Door.IsOpen");
    }

    // ---- Make Tea ----
    UFUNCTION(Exec, DisplayName="Goap.Tea.ToggleKettle")
    void Goap_Tea_ToggleKettle()
    {
        Flip(Find_StationWS("Gym.Goap.Station.MakeTea", n"Gym.Goap.WS.Tea"),
             n"Gym.Goap.WS.Tea.HasKettle");
    }

    UFUNCTION(Exec, DisplayName="Goap.Tea.ToggleWater")
    void Goap_Tea_ToggleWater()
    {
        Flip(Find_StationWS("Gym.Goap.Station.MakeTea", n"Gym.Goap.WS.Tea"),
             n"Gym.Goap.WS.Tea.HasWater");
    }

    UFUNCTION(Exec, DisplayName="Goap.Tea.ToggleLeaves")
    void Goap_Tea_ToggleLeaves()
    {
        Flip(Find_StationWS("Gym.Goap.Station.MakeTea", n"Gym.Goap.WS.Tea"),
             n"Gym.Goap.WS.Tea.HasTeaLeaves");
    }

    UFUNCTION(Exec, DisplayName="Goap.Tea.ToggleCup")
    void Goap_Tea_ToggleCup()
    {
        Flip(Find_StationWS("Gym.Goap.Station.MakeTea", n"Gym.Goap.WS.Tea"),
             n"Gym.Goap.WS.Tea.HasCup");
    }

    UFUNCTION(Exec, DisplayName="Goap.Tea.Reset")
    void Goap_Tea_Reset()
    {
        auto WS = Find_StationWS("Gym.Goap.Station.MakeTea", n"Gym.Goap.WS.Tea");
        Set(WS, n"Gym.Goap.WS.Tea.HasKettle", true);
        Set(WS, n"Gym.Goap.WS.Tea.HasWater", true);
        Set(WS, n"Gym.Goap.WS.Tea.HasTeaLeaves", true);
        Set(WS, n"Gym.Goap.WS.Tea.HasCup", true);
        Set(WS, n"Gym.Goap.WS.Tea.WaterBoiled", false);
        Set(WS, n"Gym.Goap.WS.Tea.TeaSteeped", false);
        Set(WS, n"Gym.Goap.WS.Tea.TeaPoured", false);
        Set(WS, n"Gym.Goap.WS.Tea.TeaServed", false);
    }

    // ---- Cross River ----
    UFUNCTION(Exec, DisplayName="Goap.River.ToggleBridge")
    void Goap_River_ToggleBridge()
    {
        Flip(Find_StationWS("Gym.Goap.Station.CrossRiver", n"Gym.Goap.WS.CrossRiver"),
             n"Gym.Goap.WS.CrossRiver.BridgeIsOpen");
    }

    UFUNCTION(Exec, DisplayName="Goap.River.SpendCoin")
    void Goap_River_SpendCoin()
    {
        Set(Find_StationWS("Gym.Goap.Station.CrossRiver", n"Gym.Goap.WS.CrossRiver"),
            n"Gym.Goap.WS.CrossRiver.HasCoin", false);
    }

    UFUNCTION(Exec, DisplayName="Goap.River.Reset")
    void Goap_River_Reset()
    {
        auto WS = Find_StationWS("Gym.Goap.Station.CrossRiver", n"Gym.Goap.WS.CrossRiver");
        Set(WS, n"Gym.Goap.WS.CrossRiver.BridgeIsOpen", true);
        Set(WS, n"Gym.Goap.WS.CrossRiver.HasCoin", true);
        Set(WS, n"Gym.Goap.WS.CrossRiver.Crossed", false);
    }

    // ---- Patrol ----
    UFUNCTION(Exec, DisplayName="Goap.Patrol.AdvanceB")
    void Goap_Patrol_AdvanceB()
    {
        Set(Find_StationWS("Gym.Goap.Station.Patrol", n"Gym.Goap.WS.Patrol"),
            n"Gym.Goap.WS.Patrol.AtPostB", true);
    }

    UFUNCTION(Exec, DisplayName="Goap.Patrol.AdvanceC")
    void Goap_Patrol_AdvanceC()
    {
        Set(Find_StationWS("Gym.Goap.Station.Patrol", n"Gym.Goap.WS.Patrol"),
            n"Gym.Goap.WS.Patrol.AtPostC", true);
    }

    UFUNCTION(Exec, DisplayName="Goap.Patrol.Complete")
    void Goap_Patrol_Complete()
    {
        Set(Find_StationWS("Gym.Goap.Station.Patrol", n"Gym.Goap.WS.Patrol"),
            n"Gym.Goap.WS.Patrol.Complete", true);
    }

    UFUNCTION(Exec, DisplayName="Goap.Patrol.Reset")
    void Goap_Patrol_Reset()
    {
        auto WS = Find_StationWS("Gym.Goap.Station.Patrol", n"Gym.Goap.WS.Patrol");
        Set(WS, n"Gym.Goap.WS.Patrol.AtPostA", true);
        Set(WS, n"Gym.Goap.WS.Patrol.AtPostB", false);
        Set(WS, n"Gym.Goap.WS.Patrol.AtPostC", false);
        Set(WS, n"Gym.Goap.WS.Patrol.Complete", false);
    }

    // ---- Survival ----
    UFUNCTION(Exec, DisplayName="Goap.Survival.ToggleHungry")
    void Goap_Survival_ToggleHungry()
    {
        Flip(Find_StationWS("Gym.Goap.Station.Survival", n"Gym.Goap.WS.Survival"),
             n"Gym.Goap.WS.Survival.Hungry");
    }

    UFUNCTION(Exec, DisplayName="Goap.Survival.ToggleHasFood")
    void Goap_Survival_ToggleHasFood()
    {
        Flip(Find_StationWS("Gym.Goap.Station.Survival", n"Gym.Goap.WS.Survival"),
             n"Gym.Goap.WS.Survival.HasFood");
    }

    UFUNCTION(Exec, DisplayName="Goap.Survival.ToggleThreat")
    void Goap_Survival_ToggleThreat()
    {
        Flip(Find_StationWS("Gym.Goap.Station.Survival", n"Gym.Goap.WS.Survival"),
             n"Gym.Goap.WS.Survival.ThreatActive");
    }

    UFUNCTION(Exec, DisplayName="Goap.Survival.ToggleHasWeapon")
    void Goap_Survival_ToggleHasWeapon()
    {
        Flip(Find_StationWS("Gym.Goap.Station.Survival", n"Gym.Goap.WS.Survival"),
             n"Gym.Goap.WS.Survival.HasWeapon");
    }

    UFUNCTION(Exec, DisplayName="Goap.Survival.Reset")
    void Goap_Survival_Reset()
    {
        auto WS = Find_StationWS("Gym.Goap.Station.Survival", n"Gym.Goap.WS.Survival");
        Set(WS, n"Gym.Goap.WS.Survival.Hungry", true);
        Set(WS, n"Gym.Goap.WS.Survival.HasFood", false);
        Set(WS, n"Gym.Goap.WS.Survival.ThreatActive", true);
        Set(WS, n"Gym.Goap.WS.Survival.HasWeapon", true);
        Set(WS, n"Gym.Goap.WS.Survival.SafeFromThreat", false);
    }
}
