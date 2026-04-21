USTRUCT()
struct FCkAStar_GymStationSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FString StationTitle;

	UPROPERTY()
	int32 GridWidth = 10;

	UPROPERTY()
	int32 GridHeight = 10;

	UPROPERTY()
	int32 StartX = 0;

	UPROPERTY()
	int32 StartY = 0;

	UPROPERTY()
	int32 GoalX = 9;

	UPROPERTY()
	int32 GoalY = 9;

	UPROPERTY()
	int64 BudgetMicroseconds = 0;

	UPROPERTY()
	float CostThreshold = 0.0f;

	UPROPERTY()
	TArray<FIntPoint> BlockedCells;

	UPROPERTY()
	float RestartIntervalSeconds = 5.0f;

	UPROPERTY()
	FString StationDescription;
}

// ====================================================================================================================

class UCk_EntityScript_AStarGym_Station : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	FString StationTitle;

	UPROPERTY(ExposeOnSpawn)
	FString StationDescription;

	UPROPERTY(ExposeOnSpawn)
	int32 GridWidth = 10;

	UPROPERTY(ExposeOnSpawn)
	int32 GridHeight = 10;

	UPROPERTY(ExposeOnSpawn)
	int32 StartX = 0;

	UPROPERTY(ExposeOnSpawn)
	int32 StartY = 0;

	UPROPERTY(ExposeOnSpawn)
	int32 GoalX = 9;

	UPROPERTY(ExposeOnSpawn)
	int32 GoalY = 9;

	UPROPERTY(ExposeOnSpawn)
	int64 BudgetMicroseconds = 0;

	UPROPERTY(ExposeOnSpawn)
	float32 CostThreshold = 0.0f;

	UPROPERTY(ExposeOnSpawn)
	TArray<FIntPoint> BlockedCells;

	UPROPERTY(ExposeOnSpawn)
	float RestartIntervalSeconds = 5.0f;

	FCk_Handle_AStarTest SearchEntity;
	float TimeSinceCompletion = 0.0f;
	bool IsWaitingToRestart = false;
	int32 SearchCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

		Request_CreateAndStartSearch();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void Request_CreateAndStartSearch()
	{
		auto SelfEntity = ck::ToEntity(this);
		SearchEntity = utils_a_star_test::Add(SelfEntity, GridWidth, GridHeight, StartX, StartY, GoalX, GoalY, BudgetMicroseconds);

		if (CostThreshold > 0.0f)
		{
			utils_a_star_test::Set_CostThreshold(SearchEntity, CostThreshold);
		}

		for (auto Cell : BlockedCells)
		{
			utils_a_star_test::Request_BlockCell(SearchEntity, Cell.X, Cell.Y);
		}

		utils_a_star_test::Request_StartSearch(SearchEntity);
		SearchCount++;
		IsWaitingToRestart = false;
		TimeSinceCompletion = 0.0f;
	}

	UFUNCTION()
	private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::IsValid(SearchEntity) == false)
		{ return; }

		auto DeltaSeconds = float(InDeltaT.Get_Seconds());
		auto Status = utils_a_star_test::Get_SearchStatus(SearchEntity);

		auto IsTerminal = Status != ECk_AStarSearchStatus::InProgress
			&& Status != ECk_AStarSearchStatus::Idle;

		if (IsTerminal)
		{
			if (IsWaitingToRestart == false)
			{
				IsWaitingToRestart = true;
				TimeSinceCompletion = 0.0f;
			}

			TimeSinceCompletion += DeltaSeconds;

			if (TimeSinceCompletion >= RestartIntervalSeconds)
			{
				utils_a_star_test::Request_StartSearch(SearchEntity);
				SearchCount++;
				IsWaitingToRestart = false;
				TimeSinceCompletion = 0.0f;
			}
		}

		Request_UpdateDisplay(Status, IsTerminal);
	}

	private void Request_UpdateDisplay(ECk_AStarSearchStatus InStatus, bool IsTerminal)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto StatusStr = GetStatusString(InStatus);

		auto Iterations = utils_a_star_test::Get_TotalIterations(SearchEntity);
		auto OpenSize = utils_a_star_test::Get_OpenSetSize(SearchEntity);
		auto ClosedSize = utils_a_star_test::Get_ClosedSetSize(SearchEntity);
		auto Path = utils_a_star_test::Get_Path(SearchEntity);
		auto TotalCost = utils_a_star_test::Get_TotalCost(SearchEntity);

		auto Display = f"Status: {StatusStr}    Run #{SearchCount}\n";
		Display = f"{Display}Grid: {GridWidth}x{GridHeight}\n";
		Display = f"{Display}Iterations: {Iterations}\n";
		Display = f"{Display}Open: {OpenSize}   Closed: {ClosedSize}\n";

		if (InStatus == ECk_AStarSearchStatus::Complete)
		{
			Display = f"{Display}Path: {Path.Num()} nodes   Cost: {TotalCost}\n";
		}
		else if (InStatus == ECk_AStarSearchStatus::CostThresholdReached)
		{
			Display = f"{Display}Threshold {CostThreshold} reached\n";
		}
		else if (InStatus == ECk_AStarSearchStatus::Failed)
		{
			Display = f"{Display}No path found\n";
		}

		if (BudgetMicroseconds > 0)
		{
			Display = f"{Display}Budget: {BudgetMicroseconds}us/frame\n";
		}

		if (IsTerminal)
		{
			auto SecondsLeft = int(RestartIntervalSeconds - TimeSinceCompletion) + 1;
			Display = f"{Display}\nRestarting in {SecondsLeft}s...";
		}
		else if (InStatus == ECk_AStarSearchStatus::InProgress)
		{
			Display = f"{Display}\nSearching...";
		}

		CkGym_Common::Update_StationDisplay(SelfEntity, StationTitle, Display, StationDescription);
	}

	private FString GetStatusString(ECk_AStarSearchStatus InStatus)
	{
		if (InStatus == ECk_AStarSearchStatus::Idle)                 { return "IDLE"; }
		if (InStatus == ECk_AStarSearchStatus::InProgress)           { return "IN PROGRESS"; }
		if (InStatus == ECk_AStarSearchStatus::Complete)             { return "COMPLETE"; }
		if (InStatus == ECk_AStarSearchStatus::Failed)               { return "FAILED"; }
		if (InStatus == ECk_AStarSearchStatus::CostThresholdReached) { return "COST THRESHOLD"; }
		return "UNKNOWN";
	}
}
