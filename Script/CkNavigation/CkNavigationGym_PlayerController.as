class ACk_NavigationGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		Stations.Add(MakeStationPayload(n"Gym.Navigation.FindPath", "Find Path",
			"Single agent issues Request_FindPath every 5s.\nWatch the waypoint count and status text — if the level has\na NavMeshBoundsVolume baked, the path resolves on the same frame."));

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
		return Station;
	}

	void Request_StartGym() override
	{
		SpawnStation("Gym.Navigation.FindPath", "FIND PATH",
			"Spawns a single nav agent at the station origin.\nIssues Request_FindPath to a target 500cm in +X every 5s.\nDisplays waypoint count and last path status.",
			FVector(500.0f, 0.0f, 0.0f),
			5.0f);
	}

	private void SpawnStation(
		FString InTag,
		FString InTitle,
		FString InDescription,
		FVector InTargetOffset,
		float InRepathInterval)
	{
		auto Params = FCkNavigationGym_StationSpawnParams();
		Params.InitialTransform = Get_StationTransform(InTag);
		Params.StationTitle = InTitle;
		Params.StationDescription = InDescription;
		Params.TargetOffset = InTargetOffset;
		Params.RepathIntervalSeconds = InRepathInterval;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InTag),
			UCk_EntityScript_NavigationGym_Station,
			FInstancedStruct::Make(Params));
	}

	UFUNCTION(Exec, DisplayName = "Navigation Gym - Restart All")
	void Ck_GymNavigation_RestartAll()
	{
		Request_StartGym();
	}
};
