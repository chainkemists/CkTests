class ACk_AStarGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		Stations.Add(MakeStationPayload(n"Gym.AStar.CompleteSearch", "Complete Search",
			"10x10 grid, unlimited budget.\nRuns to completion in one frame."));

		Stations.Add(MakeStationPayload(n"Gym.AStar.TimeSliced", "Time-Sliced Search",
			"50x50 grid, 50us budget/frame.\nCompletes over multiple frames."));

		Stations.Add(MakeStationPayload(n"Gym.AStar.PlanRepair", "Plan Repair",
			"20x20 grid. Blocks a path cell.\nWarm-start repair from break."));

		Stations.Add(MakeStationPayload(n"Gym.AStar.CostThreshold", "Cost Threshold",
			"10x10 grid with wall, threshold=25.\nTerminates if f-score exceeds limit."));

		Stations.Add(MakeStationPayload(n"Gym.AStar.LargeGrid", "Large Grid Stress",
			"1000x1000 grid, 10us budget/frame.\nStress test — runs for many seconds."));

		Stations.Add(MakeStationPayload(n"Gym.AStar.FailedSearch", "Failed Search",
			"15x15 grid with impassable wall.\nDemonstrates Failed status."));

		Stations.Add(MakeStationPayload(n"Gym.AStar.DenseObstacles", "Dense Obstacles",
			"30x30 grid, ~25% cells blocked.\nFinds path through dense obstacles."));

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
		SpawnStation("Gym.AStar.CompleteSearch", "COMPLETE SEARCH",
			"10x10 grid, no budget limit.\nA* finds the shortest path in a single frame.\nOptimal cost = Manhattan distance (18).",
			10, 10, 0, 0, 9, 9, 0, 0.0f, TArray<FIntPoint>());

		SpawnStation("Gym.AStar.TimeSliced", "TIME-SLICED SEARCH",
			"50x50 grid with 50us budget per frame.\nSearch spreads across many frames.\nWatch iterations climb each tick.",
			50, 50, 0, 0, 49, 49, 50, 0.0f, TArray<FIntPoint>());

		SpawnStation("Gym.AStar.PlanRepair", "PLAN REPAIR",
			"20x20 grid, no obstacles.\nSearch completes, then restarts.\nTests fresh search restart cycle.",
			20, 20, 0, 0, 19, 19, 0, 0.0f, TArray<FIntPoint>());

		auto ThresholdWall = TArray<FIntPoint>();
		for (int32 Y = 2; Y < 8; Y++)
		{
			ThresholdWall.Add(FIntPoint(5, Y));
		}
		SpawnStation("Gym.AStar.CostThreshold", "COST THRESHOLD",
			"10x10 grid with vertical wall at x=5.\nCost threshold = 25. Manhattan h = 18.\nWall forces detour; threshold may cut search short.",
			10, 10, 0, 0, 9, 9, 0, 25.0f, ThresholdWall);

		SpawnStation("Gym.AStar.LargeGrid", "LARGE GRID STRESS",
			"1000x1000 grid (1M cells), 10us budget.\nSearch takes many seconds to complete.\nStress tests time-slicing and memory.",
			1000, 1000, 0, 0, 999, 999, 10, 0.0f, TArray<FIntPoint>());

		auto FailWall = TArray<FIntPoint>();
		for (int32 X = 0; X < 15; X++)
		{
			FailWall.Add(FIntPoint(X, 7));
		}
		SpawnStation("Gym.AStar.FailedSearch", "FAILED SEARCH",
			"15x15 grid with full horizontal wall at y=7.\nNo path can reach the goal.\nDemonstrates Failed termination status.",
			15, 15, 0, 0, 14, 14, 0, 0.0f, FailWall);

		auto DenseBlocked = TArray<FIntPoint>();
		auto Seed = 42;
		for (int32 Y = 0; Y < 30; Y++)
		{
			for (int32 X = 0; X < 30; X++)
			{
				if (X == 0 && Y == 0) { continue; }
				if (X == 29 && Y == 29) { continue; }

				Seed = (Seed * 1103515245 + 12345) & 0x7fffffff;
				if (Seed % 100 < 25)
				{
					DenseBlocked.Add(FIntPoint(X, Y));
				}
			}
		}
		SpawnStation("Gym.AStar.DenseObstacles", "DENSE OBSTACLES",
			"30x30 grid with ~25% random obstacles.\nPath must navigate around dense blockages.\nPath cost >> Manhattan distance.",
			30, 30, 0, 0, 29, 29, 0, 0.0f, DenseBlocked);
	}

	private void SpawnStation(
		FString InTag,
		FString InTitle,
		FString InDescription,
		int32 InGridW, int32 InGridH,
		int32 InStartX, int32 InStartY,
		int32 InGoalX, int32 InGoalY,
		int64 InBudget,
		float InCostThreshold,
		TArray<FIntPoint> InBlockedCells)
	{
		auto Params = FCkAStar_GymStationSpawnParams();
		Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
		Params.StationTitle = InTitle;
		Params.StationDescription = InDescription;
		Params.GridWidth = InGridW;
		Params.GridHeight = InGridH;
		Params.StartX = InStartX;
		Params.StartY = InStartY;
		Params.GoalX = InGoalX;
		Params.GoalY = InGoalY;
		Params.BudgetMicroseconds = InBudget;
		Params.CostThreshold = InCostThreshold;
		Params.BlockedCells = InBlockedCells;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InTag),
			UCk_EntityScript_AStarGym_Station,
			FInstancedStruct::Make(Params));
	}

	//--------------------------------------------------------------------------------------------------------------------------
	// CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
	//
	// One row. Everything here plays once and is then over, so re-running it IS the gym - and the console
	// command's name was the only documentation that the control existed at all.
	//--------------------------------------------------------------------------------------------------------------------------

	FString Get_ControlPanelTitle() override
	{
		return "A-STAR";
	}

	TArray<FCkGym_ControlRow> Get_ControlRows() override
	{
		auto Rows = TArray<FCkGym_ControlRow>();
		Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Re-run every search"));
		return Rows;
	}

	void Request_ControlActivated(int32 InRowIndex) override
	{
		if (InRowIndex == 0) { Ck_GymAStar_RestartAll(); }
	}

	UFUNCTION(Exec, DisplayName="AStar Gym - Restart All")
	void Ck_GymAStar_RestartAll()
	{
		Request_StartGym();
	}
};
