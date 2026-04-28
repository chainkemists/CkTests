// Language=angelscript

//============================================================================
// GOAP EMPIRE GYM — PLAYER CONTROLLER
//============================================================================
// Single-station gym: spawns the Empire station, exposes a Reset exec.
// Everything else is automatic — the station drives itself through the
// 4 progressive goals and recycles.
//============================================================================

class ACk_GoapEmpireGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		auto Station = FCkGym_Station_SpawnParams_Payload();
		Station.Tags.Add(n"Gym.GoapEmpire.Station");
		Station.Title = FText::FromString("AGE OF EMPIRES — BOOLEAN GOAP STRESS TEST");
		auto Desc = TArray<FText>();
		Desc.Add(FText::FromString("~45 actions, 4 progressive goals, one villager. Planner drives the tech tree; gameplay owns numeric resources."));
		Desc.Add(FText::FromString("Auto-cycles Feudal -> Castle -> Imperial -> Wonder, then resets."));
		Station.Description = Desc;
		Station.AutoSize = true;
		Stations.Add(Station);

		return Stations;
	}

	void Request_StartGym() override
	{
		Request_StartEmpire();
		ck::Trace("GOAP Empire Gym - Station started");
	}

	void Request_StartEmpire()
	{
		auto T = Get_StationAnchorTransform("Gym.GoapEmpire.Station", ECk_GymStation_Anchor::PanelCenter);
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.GoapEmpire.Station"),
			UCk_EntityScript_GoapEmpire_Station,
			FInstancedStruct::Make(FCk_Gym_TransformSpawnParams(T)));
	}

	// Broadcast helpers
	void BroadcastToTag(FName InTag, FInstancedStruct InMessage)
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	UFUNCTION(Exec, DisplayName="GOAP Empire Gym - Restart")
	void Ck_GymGoapEmpire_Restart() { Request_StartGym(); }

	UFUNCTION(Exec, DisplayName="GOAP Empire Gym - Reset World")
	void Ck_GymGoapEmpire_Reset()
	{
		BroadcastToTag(n"TAG_GoapEmpireGym_Station",
			FInstancedStruct::Make(FCk_Message_GoapEmpire_ResetWorld()));
	}
}
