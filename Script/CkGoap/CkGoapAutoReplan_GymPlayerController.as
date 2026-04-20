// Language=angelscript

//============================================================================
// GOAP AUTO-REPLAN GYM — PLAYER CONTROLLER
//============================================================================
// Single-station gym. Spawns one AI with 8 drifting enemies and exposes
// exec commands for manual kill/revive/replan.
//============================================================================

class ACk_GoapAutoReplanGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		auto Station = FCkGym_Station_SpawnParams_Payload();
		Station.Tags.Add(n"Gym.Goap.AutoReplan");
		Station.Title = FText::FromString("GOAP AUTO-REPLAN");
		auto Desc = TArray<FText>();
		Desc.Add(FText::FromString("Spatial demo: 1 AI capsule + 8 drifting enemy capsules."));
		Desc.Add(FText::FromString("Auto-replan on world-state/cost dirty (0.25s throttle). Enemies die/revive randomly."));
		Station.Description = Desc;
		Station.Width = 15.0f;
		Station.Depth = 15.0f;
		Station.Height = 9.0f;
		Stations.Add(Station);

		return Stations;
	}

	void Request_StartGym() override
	{
		auto T = Get_StationTransform("Gym.Goap.AutoReplan");
		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle("Gym.Goap.AutoReplan"),
			UCk_EntityScript_GoapGym_AutoReplan,
			FInstancedStruct::Make(FCk_Gym_TransformSpawnParams(T)));
		ck::Trace("GOAP Auto-Replan Gym - Station started");
	}

	//------------------------------------------------------------------------
	// BROADCAST HELPERS
	//------------------------------------------------------------------------

	void BroadcastToTag(FName InTag, FInstancedStruct InMessage)
	{
		auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
		for (auto Entity : Entities)
		{
			utils_messaging::Broadcast(Entity, InMessage);
		}
	}

	//------------------------------------------------------------------------
	// CONSOLE COMMANDS
	//------------------------------------------------------------------------

	UFUNCTION(Exec, DisplayName="GOAP Auto-Replan - Restart")
	void Ck_GymGoapAutoReplan_Restart() { Request_StartGym(); }

	UFUNCTION(Exec, DisplayName="GOAP Auto-Replan - Manual Replan")
	void Ck_GymGoapAutoReplan_Replan()
	{
		BroadcastToTag(n"TAG_GoapGym_AutoReplan", FInstancedStruct::Make(FCk_Message_GoapGym_AutoReplan_Replan()));
	}

	UFUNCTION(Exec, DisplayName="GOAP Auto-Replan - Kill Random Enemy")
	void Ck_GymGoapAutoReplan_KillRandom()
	{
		BroadcastToTag(n"TAG_GoapGym_AutoReplan", FInstancedStruct::Make(FCk_Message_GoapGym_AutoReplan_KillRandom()));
	}

	UFUNCTION(Exec, DisplayName="GOAP Auto-Replan - Revive All Enemies")
	void Ck_GymGoapAutoReplan_ReviveAll()
	{
		BroadcastToTag(n"TAG_GoapGym_AutoReplan", FInstancedStruct::Make(FCk_Message_GoapGym_AutoReplan_ReviveAll()));
	}
}
