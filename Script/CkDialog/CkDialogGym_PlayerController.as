//============================================================================
// DIALOG GYM - PLAYER CONTROLLER
//============================================================================

class ACk_DialogGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		// Station 1: Basics
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Dialog.Basics");
			Station.Title = FText::FromString("DIALOG BASICS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("A runtime mini-bank of lines on one ENTER tag."));
			Description.Add(FText::FromString("Auto-cycled query lists every line with its pass/fail state."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 2: Filters
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Dialog.Filters");
			Station.Title = FText::FromString("DIALOG TAG FILTERS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("Two emitters (Townie vs NamedNpc), same event, different lines."));
			Description.Add(FText::FromString("Shows tag-overlap visibility filtering per emitter."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 3: Cooldowns
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Dialog.Cooldowns");
			Station.Title = FText::FromString("DIALOG COOLDOWNS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("1s query cadence vs a 3s cooldown; live countdown."));
			Description.Add(FText::FromString("A second emitter proves per-emitter cooldown isolation."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 4: Chains
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Dialog.Chains");
			Station.Title = FText::FromString("DIALOG EXIT CHAINS");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("A 3-line EXIT->ENTER chain auto-walked via QueryFollowUp."));
			Description.Add(FText::FromString("Watch the chain advance from line to line."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		// Station 5: Graph (live PMG dialog-tree visualization)
		{
			auto Station = FCkGym_Station_SpawnParams_Payload();
			Station.Tags.Add(n"Gym.Dialog.Graph");
			Station.Title = FText::FromString("DIALOG GRAPH (LIVE)");
			auto Description = TArray<FText>();
			Description.Add(FText::FromString("A branching dialog tree drawn in-world with CkPmg."));
			Description.Add(FText::FromString("Green=passable, red=blocked edge, yellow=active node."));
			Station.Description = Description;
			Stations.Add(Station);
		}

		return Stations;
	}

	void Request_StartGym() override
	{
		Request_StartBasics();
		Request_StartFilters();
		Request_StartCooldowns();
		Request_StartChains();
		Request_StartGraph();
		ck::Trace("✅ Dialog Gym - All stations started");
	}

	//------------------------------------------------------------------------
	// STATION STARTUP
	//------------------------------------------------------------------------

	void Request_StartBasics()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Dialog.Basics", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Dialog.Basics"),
			UCk_EntityScript_DialogGym_Basics,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartFilters()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Dialog.Filters", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Dialog.Filters"),
			UCk_EntityScript_DialogGym_Filters,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartCooldowns()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Dialog.Cooldowns", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Dialog.Cooldowns"),
			UCk_EntityScript_DialogGym_Cooldowns,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartChains()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Dialog.Chains", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Dialog.Chains"),
			UCk_EntityScript_DialogGym_Chains,
			FInstancedStruct::Make(SpawnParams));
	}

	void Request_StartGraph()
	{
		auto SpawnParams = FCk_Gym_TransformSpawnParams(Get_StationAnchorTransform("Gym.Dialog.Graph", ECk_GymStation_Anchor::PanelCenter));
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Dialog.Graph"),
			UCk_EntityScript_DialogGym_Graph,
			FInstancedStruct::Make(SpawnParams));
	}

	//------------------------------------------------------------------------
	// CONSOLE COMMANDS
	//------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="Dialog Gym - Restart Basics")
	void Ck_GymDialog_RestartBasics()
	{
		Request_DestroyStationEntities(n"TAG_DialogGym_Basics");
		Request_StartBasics();
	}

	UFUNCTION(Exec, DisplayName="Dialog Gym - Restart Filters")
	void Ck_GymDialog_RestartFilters()
	{
		Request_DestroyStationEntities(n"TAG_DialogGym_Filters");
		Request_StartFilters();
	}

	UFUNCTION(Exec, DisplayName="Dialog Gym - Restart Cooldowns")
	void Ck_GymDialog_RestartCooldowns()
	{
		Request_DestroyStationEntities(n"TAG_DialogGym_Cooldowns");
		Request_StartCooldowns();
	}

	UFUNCTION(Exec, DisplayName="Dialog Gym - Restart Chains")
	void Ck_GymDialog_RestartChains()
	{
		Request_DestroyStationEntities(n"TAG_DialogGym_Chains");
		Request_StartChains();
	}

	UFUNCTION(Exec, DisplayName="Dialog Gym - Restart Graph")
	void Ck_GymDialog_RestartGraph()
	{
		Request_DestroyStationEntities(n"TAG_DialogGym_Graph");
		Request_StartGraph();
	}

	UFUNCTION(Exec, DisplayName="Dialog Gym - Reset All")
	void Ck_GymDialog_ResetAll()
	{
		Request_DestroyStationEntities(n"TAG_DialogGym_Basics");
		Request_DestroyStationEntities(n"TAG_DialogGym_Filters");
		Request_DestroyStationEntities(n"TAG_DialogGym_Cooldowns");
		Request_DestroyStationEntities(n"TAG_DialogGym_Chains");
		Request_DestroyStationEntities(n"TAG_DialogGym_Graph");

		Request_StartGym();
	}

	//------------------------------------------------------------------------
	// UTILITY
	//------------------------------------------------------------------------

	void Request_DestroyStationEntities(FName InTag)
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
		for (auto Entity : Entities)
		{
			utils_entity_lifetime::Request_DestroyEntity(Entity);
		}
	}
}
