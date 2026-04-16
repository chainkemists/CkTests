// Language=angelscript

//============================================================================
// GOAP GYM — PLAYER CONTROLLER
//============================================================================
// Spawns one station per GOAP scenario and exposes:
//   - a global Ck_GymGoap_Auto [0/1] to toggle auto mode across all stations
//   - per-station Ck_GymGoap_Auto<Station> to re-enable a single station
//   - per-station manual exec commands that mutate state and replan
//============================================================================

class ACk_GoapGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		Stations.Add(MakeStation(n"Gym.Goap.Door", "OPEN DOOR",
			"Trivial GOAP plan — 2 actions.",
			"Auto cycles between empty, pre-unlocked, and key-in-hand starts."));

		Stations.Add(MakeStation(n"Gym.Goap.Tea", "MAKE TEA",
			"Strict linear dependency chain — 4 actions.",
			"Auto cycles progressively-warmer starting states to shrink plan length."));

		Stations.Add(MakeStation(n"Gym.Goap.Combat", "COMBAT: RANGED vs MELEE",
			"Branching graph with cost comparison + dynamic cost update.",
			"Flipping melee cost mid-cycle makes the planner switch paths."));

		Stations.Add(MakeStation(n"Gym.Goap.Priorities", "MULTI-GOAL PRIORITIES",
			"3 goals with priorities 10 / 5 / 3.",
			"Planner picks the highest-priority goal that is actually reachable."));

		Stations.Add(MakeStation(n"Gym.Goap.NoPlan", "NO PLAN POSSIBLE",
			"Actions registered cannot satisfy the goal.",
			"Planner terminates with PlanFailed. Restart to re-observe."));

		Stations.Add(MakeStation(n"Gym.Goap.Empire", "AGE OF EMPIRES",
			"Full AoE-style villager economy — 16 actions, 3 goals.",
			"Auto plays through GatherResources -> BuildMilitary -> ReachFeudalAge timeline."));

		return Stations;
	}

	private FCkGym_Station_SpawnParams_Payload MakeStation(FName InTag, FString InTitle, FString InDesc1, FString InDesc2)
	{
		auto Station = FCkGym_Station_SpawnParams_Payload();
		Station.Tags.Add(InTag);
		Station.Title = FText::FromString(InTitle);
		auto Desc = TArray<FText>();
		Desc.Add(FText::FromString(InDesc1));
		Desc.Add(FText::FromString(InDesc2));
		Station.Description = Desc;
		Station.Height = 9.0f;
		return Station;
	}

	void Request_StartGym() override
	{
		Request_StartDoor();
		Request_StartTea();
		Request_StartCombat();
		Request_StartPriorities();
		Request_StartNoPlan();
		Request_StartEmpire();
		ck::Trace("GOAP Gym - All stations started");
	}

	// ------------------------------------------------------------------------
	// STATION STARTUP
	// ------------------------------------------------------------------------

	void Request_StartDoor()
	{
		auto T = Get_StationTransform("Gym.Goap.Door");
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Goap.Door"),
			UCk_EntityScript_GoapGym_Door,
			FInstancedStruct::Make(FCk_Gym_TransformSpawnParams(T)));
	}

	void Request_StartTea()
	{
		auto T = Get_StationTransform("Gym.Goap.Tea");
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Goap.Tea"),
			UCk_EntityScript_GoapGym_Tea,
			FInstancedStruct::Make(FCk_Gym_TransformSpawnParams(T)));
	}

	void Request_StartCombat()
	{
		auto T = Get_StationTransform("Gym.Goap.Combat");
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Goap.Combat"),
			UCk_EntityScript_GoapGym_Combat,
			FInstancedStruct::Make(FCk_Gym_TransformSpawnParams(T)));
	}

	void Request_StartPriorities()
	{
		auto T = Get_StationTransform("Gym.Goap.Priorities");
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Goap.Priorities"),
			UCk_EntityScript_GoapGym_Priorities,
			FInstancedStruct::Make(FCk_Gym_TransformSpawnParams(T)));
	}

	void Request_StartNoPlan()
	{
		auto T = Get_StationTransform("Gym.Goap.NoPlan");
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Goap.NoPlan"),
			UCk_EntityScript_GoapGym_NoPlan,
			FInstancedStruct::Make(FCk_Gym_TransformSpawnParams(T)));
	}

	void Request_StartEmpire()
	{
		auto T = Get_StationTransform("Gym.Goap.Empire");
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Goap.Empire"),
			UCk_EntityScript_GoapGym_Empire,
			FInstancedStruct::Make(FCk_Gym_TransformSpawnParams(T)));
	}

	// ------------------------------------------------------------------------
	// BROADCAST HELPERS
	// ------------------------------------------------------------------------

	void BroadcastToTag(FName InTag, FInstancedStruct InMessage)
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	void BroadcastAutoToAll(bool InEnabled)
	{
		auto Msg = FCk_Message_Gym_AutoSet(InEnabled);
		auto StationTags = TArray<FName>();
		StationTags.Add(n"TAG_GoapGym_Door");
		StationTags.Add(n"TAG_GoapGym_Tea");
		StationTags.Add(n"TAG_GoapGym_Combat");
		StationTags.Add(n"TAG_GoapGym_Priorities");
		StationTags.Add(n"TAG_GoapGym_NoPlan");
		StationTags.Add(n"TAG_GoapGym_Empire");
		for (auto Tag : StationTags) { BroadcastToTag(Tag, FInstancedStruct::Make(Msg)); }
	}

	void BroadcastAutoToTag(FName InTag, bool InEnabled)
	{
		auto Msg = FCk_Message_Gym_AutoSet(InEnabled);
		BroadcastToTag(InTag, FInstancedStruct::Make(Msg));
	}

	// ------------------------------------------------------------------------
	// RESTART
	// ------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="GOAP Gym - Restart All")
	void Ck_GymGoap_RestartAll() { Request_StartGym(); }

	// ------------------------------------------------------------------------
	// GLOBAL + PER-STATION AUTO CONTROL
	// ------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="GOAP Gym - Auto All")
	void Ck_GymGoap_Auto(int32 InEnabled = 1) { BroadcastAutoToAll(InEnabled != 0); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Auto Door")
	void Ck_GymGoap_AutoDoor() { BroadcastAutoToTag(n"TAG_GoapGym_Door", true); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Auto Tea")
	void Ck_GymGoap_AutoTea() { BroadcastAutoToTag(n"TAG_GoapGym_Tea", true); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Auto Combat")
	void Ck_GymGoap_AutoCombat() { BroadcastAutoToTag(n"TAG_GoapGym_Combat", true); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Auto Priorities")
	void Ck_GymGoap_AutoPriorities() { BroadcastAutoToTag(n"TAG_GoapGym_Priorities", true); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Auto NoPlan")
	void Ck_GymGoap_AutoNoPlan() { BroadcastAutoToTag(n"TAG_GoapGym_NoPlan", true); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Auto Empire")
	void Ck_GymGoap_AutoEmpire() { BroadcastAutoToTag(n"TAG_GoapGym_Empire", true); }

	// ------------------------------------------------------------------------
	// STATION 1: DOOR
	// ------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="GOAP Gym - Door Replan")
	void Ck_GymGoap_Door_Replan()     { BroadcastToTag(n"TAG_GoapGym_Door", FInstancedStruct::Make(FCk_Message_GoapGym_Door_Replan())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Door Give Key")
	void Ck_GymGoap_Door_GiveKey()    { BroadcastToTag(n"TAG_GoapGym_Door", FInstancedStruct::Make(FCk_Message_GoapGym_Door_GiveKey())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Door Lose Key")
	void Ck_GymGoap_Door_LoseKey()    { BroadcastToTag(n"TAG_GoapGym_Door", FInstancedStruct::Make(FCk_Message_GoapGym_Door_LoseKey())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Door Pre-Unlock")
	void Ck_GymGoap_Door_PreUnlock()  { BroadcastToTag(n"TAG_GoapGym_Door", FInstancedStruct::Make(FCk_Message_GoapGym_Door_PreUnlock())); }

	// ------------------------------------------------------------------------
	// STATION 2: TEA
	// ------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="GOAP Gym - Tea Replan")
	void Ck_GymGoap_Tea_Replan()     { BroadcastToTag(n"TAG_GoapGym_Tea", FInstancedStruct::Make(FCk_Message_GoapGym_Tea_Replan())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Tea Fill Water")
	void Ck_GymGoap_Tea_FillWater()  { BroadcastToTag(n"TAG_GoapGym_Tea", FInstancedStruct::Make(FCk_Message_GoapGym_Tea_FillWater())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Tea Boil Water")
	void Ck_GymGoap_Tea_BoilWater()  { BroadcastToTag(n"TAG_GoapGym_Tea", FInstancedStruct::Make(FCk_Message_GoapGym_Tea_BoilWater())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Tea Steep Tea")
	void Ck_GymGoap_Tea_SteepTea()   { BroadcastToTag(n"TAG_GoapGym_Tea", FInstancedStruct::Make(FCk_Message_GoapGym_Tea_SteepTea())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Tea Reset")
	void Ck_GymGoap_Tea_ResetAll()   { BroadcastToTag(n"TAG_GoapGym_Tea", FInstancedStruct::Make(FCk_Message_GoapGym_Tea_ResetAll())); }

	// ------------------------------------------------------------------------
	// STATION 3: COMBAT
	// ------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="GOAP Gym - Combat Replan")
	void Ck_GymGoap_Combat_Replan()              { BroadcastToTag(n"TAG_GoapGym_Combat", FInstancedStruct::Make(FCk_Message_GoapGym_Combat_Replan())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Combat Make Melee Cheap")
	void Ck_GymGoap_Combat_MakeMeleeCheap()      { BroadcastToTag(n"TAG_GoapGym_Combat", FInstancedStruct::Make(FCk_Message_GoapGym_Combat_MakeMeleeCheap())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Combat Make Melee Expensive")
	void Ck_GymGoap_Combat_MakeMeleeExpensive()  { BroadcastToTag(n"TAG_GoapGym_Combat", FInstancedStruct::Make(FCk_Message_GoapGym_Combat_MakeMeleeExpensive())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Combat Remove Weapon")
	void Ck_GymGoap_Combat_RemoveWeapon()        { BroadcastToTag(n"TAG_GoapGym_Combat", FInstancedStruct::Make(FCk_Message_GoapGym_Combat_RemoveWeapon())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Combat Give Weapon")
	void Ck_GymGoap_Combat_GiveWeapon()          { BroadcastToTag(n"TAG_GoapGym_Combat", FInstancedStruct::Make(FCk_Message_GoapGym_Combat_GiveWeapon())); }

	// ------------------------------------------------------------------------
	// STATION 4: PRIORITIES
	// ------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="GOAP Gym - Priorities Replan")
	void Ck_GymGoap_Priorities_Replan()    { BroadcastToTag(n"TAG_GoapGym_Priorities", FInstancedStruct::Make(FCk_Message_GoapGym_Priorities_Replan())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Priorities Take Fire")
	void Ck_GymGoap_Priorities_TakeFire()  { BroadcastToTag(n"TAG_GoapGym_Priorities", FInstancedStruct::Make(FCk_Message_GoapGym_Priorities_TakeFire())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Priorities Get Hungry")
	void Ck_GymGoap_Priorities_GetHungry() { BroadcastToTag(n"TAG_GoapGym_Priorities", FInstancedStruct::Make(FCk_Message_GoapGym_Priorities_GetHungry())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Priorities Spot Enemy")
	void Ck_GymGoap_Priorities_SpotEnemy() { BroadcastToTag(n"TAG_GoapGym_Priorities", FInstancedStruct::Make(FCk_Message_GoapGym_Priorities_SpotEnemy())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Priorities Reset")
	void Ck_GymGoap_Priorities_ResetAll()  { BroadcastToTag(n"TAG_GoapGym_Priorities", FInstancedStruct::Make(FCk_Message_GoapGym_Priorities_ResetAll())); }

	// ------------------------------------------------------------------------
	// STATION 5: NO-PLAN
	// ------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="GOAP Gym - NoPlan Replan")
	void Ck_GymGoap_NoPlan_Replan() { BroadcastToTag(n"TAG_GoapGym_NoPlan", FInstancedStruct::Make(FCk_Message_GoapGym_NoPlan_Replan())); }

	// ------------------------------------------------------------------------
	// STATION 6: EMPIRE
	// ------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="GOAP Gym - Empire Plan GatherResources")
	void Ck_GymGoap_Empire_PlanGatherResources() { BroadcastToTag(n"TAG_GoapGym_Empire", FInstancedStruct::Make(FCk_Message_GoapGym_Empire_PlanGatherResources())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Empire Plan BuildMilitary")
	void Ck_GymGoap_Empire_PlanBuildMilitary()   { BroadcastToTag(n"TAG_GoapGym_Empire", FInstancedStruct::Make(FCk_Message_GoapGym_Empire_PlanBuildMilitary())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Empire Plan FeudalAge")
	void Ck_GymGoap_Empire_PlanFeudalAge()       { BroadcastToTag(n"TAG_GoapGym_Empire", FInstancedStruct::Make(FCk_Message_GoapGym_Empire_PlanFeudalAge())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Empire Apply Plan")
	void Ck_GymGoap_Empire_ApplyPlan()           { BroadcastToTag(n"TAG_GoapGym_Empire", FInstancedStruct::Make(FCk_Message_GoapGym_Empire_ApplyPlan())); }

	UFUNCTION(Exec, DisplayName="GOAP Gym - Empire Reset World")
	void Ck_GymGoap_Empire_ResetWorld()          { BroadcastToTag(n"TAG_GoapGym_Empire", FInstancedStruct::Make(FCk_Message_GoapGym_Empire_ResetWorld())); }
}
