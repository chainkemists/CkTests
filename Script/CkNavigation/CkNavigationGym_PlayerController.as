class ACk_NavigationGym_PlayerController : ACk_Gym_Base_PlayerController
{
	// Pull stations down so the alcove floor (loc.Z = FloorThickness/2 = 7.5cm,
	// extent = FloorThickness/2 = 7.5cm — total 15cm tall above the station
	// origin) sits flush with the nav floor mesh whose top face is at Z=0. We
	// leave 0.1cm of overhang so the alcove floor + floor description text
	// stay visible from above instead of getting Z-fought into invisibility.
	default DefaultStationGridZ = -14.9f;

	// When true, only the two single-agent stations (Find Path + Moving Agent) spawn.
	// The crowd-stress stations (Ring/CounterFlow/Cluster/Density) are skipped — their
	// 60+ background agents drown out logs when debugging the basic nav loop. The
	// CkNavigationGymSimple_GameMode flips this on; otherwise the full gym spawns.
	UPROPERTY()
	bool _SimpleMode = false;

	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		Stations.Add(MakeStationPayload(n"Gym.Navigation.FindPath", "Find Path",
			"Single agent issues Request_FindPath every 5s.\nWatch the waypoint count and status text — if the level has\na NavMeshBoundsVolume baked, the path resolves on the same frame."));

		Stations.Add(MakeStationPayload(n"Gym.Navigation.Move", "Moving Agent",
			"Single agent ping-pongs between two waypoints.\nDrives the full crowd loop end-to-end:\n  Add → CrowdSetup → CrowdUpdateTarget → CrowdStep → CrowdReadVelocity\n  → script reads velocity, integrates, calls Request_SetTransform.\nWatch the agent visibly move; arrivals count up each leg."));

		if (_SimpleMode)
		{
			return Stations;
		}

		Stations.Add(MakeStationPayload(n"Gym.Navigation.RingAvoidance", "Ring Avoidance",
			"N agents on a circle, each targeting the diametric opposite.\nAll converge through the centre simultaneously — exercises\ndtCrowd's inter-agent avoidance. Loops forever."));

		Stations.Add(MakeStationPayload(n"Gym.Navigation.CounterFlow", "Counter Flow",
			"Two columns walking past each other in opposite directions.\nClassic separation stress — magenta walks +X, yellow walks -X.\nLoops forever."));

		Stations.Add(MakeStationPayload(n"Gym.Navigation.ClusterTarget", "Cluster Target",
			"N agents around a moving target marker.\nDirector picks a new target every 5s and re-issues paths to\nevery agent — tests repeated re-pathing under cluster density."));

		Stations.Add(MakeStationPayload(n"Gym.Navigation.DensityStress", "Density Stress",
			"N agents packed tightly, all targeting one point in +X.\nTests dtCrowd separation under high density.\nOne-shot — agents arrive and idle."));

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
		SpawnFindPathStation("Gym.Navigation.FindPath", "FIND PATH",
			"Spawns a single nav agent at the station origin.\nIssues Request_FindPath to a target 500cm in +X every 5s.\nDisplays waypoint count and last path status.",
			FVector(500.0f, 0.0f, 0.0f),
			5.0f);

		SpawnMovingAgentStation("Gym.Navigation.Move", "MOVING AGENT",
			"Single agent ping-pongs between two waypoints.\nReads CurrentVelocity from dtCrowd each tick and integrates\ninto the entity transform — the agent visibly moves.",
			600.0f,
			25.0f);

		if (_SimpleMode)
		{
			return;
		}

		SpawnRingAvoidanceStation("Gym.Navigation.RingAvoidance", "RING AVOIDANCE",
			"12 agents on a circle of radius 800cm, each targeting the\ndiametric opposite. All converge through the centre at once.",
			12, 800.0f);

		SpawnCounterFlowStation("Gym.Navigation.CounterFlow", "COUNTER FLOW",
			"Two columns of 8 agents each walking past each other.\nClassic dtCrowd separation stress.",
			8, 600.0f, 80.0f);

		SpawnClusterTargetStation("Gym.Navigation.ClusterTarget", "CLUSTER TARGET",
			"12 agents around a moving target marker.\nDirector picks a new target every 5s and re-issues paths.",
			12, 250.0f, 900.0f, 5.0f);

		SpawnDensityStressStation("Gym.Navigation.DensityStress", "DENSITY STRESS",
			"24 agents packed in a 300cm square, all targeting +X 1500cm.\nOne-shot — agents arrive and idle.",
			24, 300.0f, 1500.0f);
	}

	// Returns the station's transform with Z snapped to the navmesh surface (Z=0 in this gym).
	// We intentionally pull stations down via DefaultStationGridZ so the alcove floor sits
	// flush with the world floor, but nav agents themselves must spawn ON the navmesh — not
	// at the station's pulled-down origin — otherwise their transforms (and PMG markers)
	// end up buried below the floor mesh and dtCrowd has to project them up every frame.
	private FTransform Get_NavSurfaceTransform(FString InTag)
	{
		auto T = Get_StationTransform(InTag);
		auto Loc = T.GetLocation();
		Loc.Z = 0.0;
		return FTransform(T.Rotator(), Loc, FVector(1.0, 1.0, 1.0));
	}

	private void SpawnFindPathStation(
		FString InTag,
		FString InTitle,
		FString InDescription,
		FVector InTargetOffset,
		float InRepathInterval)
	{
		auto Params = FCkNavigationGym_StationSpawnParams();
		Params.InitialTransform = Get_NavSurfaceTransform(InTag);
		Params.StationTitle = InTitle;
		Params.StationDescription = InDescription;
		Params.TargetOffset = InTargetOffset;
		Params.RepathIntervalSeconds = InRepathInterval;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InTag),
			UCk_EntityScript_NavigationGym_Station,
			FInstancedStruct::Make(Params));
	}

	private void SpawnMovingAgentStation(
		FString InTag,
		FString InTitle,
		FString InDescription,
		float InPingPongDistance,
		float InArrivalSpeedThreshold)
	{
		auto Params = FCkNavigationGym_MovingAgentSpawnParams();
		Params.InitialTransform = Get_NavSurfaceTransform(InTag);
		Params.StationTitle = InTitle;
		Params.StationDescription = InDescription;
		Params.PingPongDistance = InPingPongDistance;
		Params.ArrivalSpeedThreshold = InArrivalSpeedThreshold;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InTag),
			UCk_EntityScript_NavigationGym_MovingAgent,
			FInstancedStruct::Make(Params));
	}

	private void SpawnRingAvoidanceStation(
		FString InTag,
		FString InTitle,
		FString InDescription,
		int32 InAgentCount,
		float InRingRadius)
	{
		auto Params = FCkNavigationGym_RingAvoidanceSpawnParams();
		Params.InitialTransform = Get_NavSurfaceTransform(InTag);
		Params.StationTitle = InTitle;
		Params.StationDescription = InDescription;
		Params.AgentCount = InAgentCount;
		Params.RingRadius = InRingRadius;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InTag),
			UCk_EntityScript_NavigationGym_RingAvoidance,
			FInstancedStruct::Make(Params));
	}

	private void SpawnCounterFlowStation(
		FString InTag,
		FString InTitle,
		FString InDescription,
		int32 InAgentsPerColumn,
		float InColumnHalfDistance,
		float InColumnSpacing)
	{
		auto Params = FCkNavigationGym_CounterFlowSpawnParams();
		Params.InitialTransform = Get_NavSurfaceTransform(InTag);
		Params.StationTitle = InTitle;
		Params.StationDescription = InDescription;
		Params.AgentsPerColumn = InAgentsPerColumn;
		Params.ColumnHalfDistance = InColumnHalfDistance;
		Params.ColumnSpacing = InColumnSpacing;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InTag),
			UCk_EntityScript_NavigationGym_CounterFlow,
			FInstancedStruct::Make(Params));
	}

	private void SpawnClusterTargetStation(
		FString InTag,
		FString InTitle,
		FString InDescription,
		int32 InAgentCount,
		float InClusterRadius,
		float InTargetMoveDistance,
		float InTargetMoveIntervalSeconds)
	{
		auto Params = FCkNavigationGym_ClusterTargetSpawnParams();
		Params.InitialTransform = Get_NavSurfaceTransform(InTag);
		Params.StationTitle = InTitle;
		Params.StationDescription = InDescription;
		Params.AgentCount = InAgentCount;
		Params.ClusterRadius = InClusterRadius;
		Params.TargetMoveDistance = InTargetMoveDistance;
		Params.TargetMoveIntervalSeconds = InTargetMoveIntervalSeconds;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InTag),
			UCk_EntityScript_NavigationGym_ClusterTarget,
			FInstancedStruct::Make(Params));
	}

	private void SpawnDensityStressStation(
		FString InTag,
		FString InTitle,
		FString InDescription,
		int32 InAgentCount,
		float InSpawnAreaSize,
		float InTargetDistance)
	{
		auto Params = FCkNavigationGym_DensityStressSpawnParams();
		Params.InitialTransform = Get_NavSurfaceTransform(InTag);
		Params.StationTitle = InTitle;
		Params.StationDescription = InDescription;
		Params.AgentCount = InAgentCount;
		Params.SpawnAreaSize = InSpawnAreaSize;
		Params.TargetDistance = InTargetDistance;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InTag),
			UCk_EntityScript_NavigationGym_DensityStress,
			FInstancedStruct::Make(Params));
	}

	UFUNCTION(Exec, DisplayName = "Navigation Gym - Restart All")
	void Ck_GymNavigation_RestartAll()
	{
		Request_StartGym();
	}
};
