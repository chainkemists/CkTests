USTRUCT()
struct FCkGoap_GymStationSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FString StationTitle;

	UPROPERTY()
	FString StationDescription;

	UPROPERTY()
	TArray<TSubclassOf<UCk_GoapAction_EntityScript>> ActionClasses;

	UPROPERTY()
	TArray<TSubclassOf<UCk_GoapGoal_EntityScript>> GoalClasses;

	UPROPERTY()
	TSubclassOf<UCk_GoapGoal_EntityScript> SpecificGoalClass;

	UPROPERTY()
	TMap<FGameplayTag, bool> InitialWorldState;

	UPROPERTY()
	int64 BudgetMicroseconds = 0;

	UPROPERTY()
	float RestartIntervalSeconds = 5.0f;

	UPROPERTY()
	TSubclassOf<UCk_GoapAction_EntityScript> CostOverrideAction;

	UPROPERTY()
	float CostOverrideValue = -1.0f;
}

// ====================================================================================================================

class UCk_EntityScript_GoapGym_Station : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	FString StationTitle;

	UPROPERTY(ExposeOnSpawn)
	FString StationDescription;

	UPROPERTY(ExposeOnSpawn)
	TArray<TSubclassOf<UCk_GoapAction_EntityScript>> ActionClasses;

	UPROPERTY(ExposeOnSpawn)
	TArray<TSubclassOf<UCk_GoapGoal_EntityScript>> GoalClasses;

	UPROPERTY(ExposeOnSpawn)
	TSubclassOf<UCk_GoapGoal_EntityScript> SpecificGoalClass;

	UPROPERTY(ExposeOnSpawn)
	TMap<FGameplayTag, bool> InitialWorldState;

	UPROPERTY(ExposeOnSpawn)
	int64 BudgetMicroseconds = 0;

	UPROPERTY(ExposeOnSpawn)
	float RestartIntervalSeconds = 5.0f;

	UPROPERTY(ExposeOnSpawn)
	TSubclassOf<UCk_GoapAction_EntityScript> CostOverrideAction;

	UPROPERTY(ExposeOnSpawn)
	float CostOverrideValue = -1.0f;

	FCk_Handle_Goap GoapEntity;
	float TimeSinceCompletion = 0.0f;
	bool IsWaitingToRestart = false;
	int32 PlanCount = 0;

	// ================================================================================================================

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

		utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

		Request_CreateAndPlan();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	// ================================================================================================================

	private void Request_CreateAndPlan()
	{
		auto SelfEntity = ck::ToEntity(this);

		GoapEntity = utils_goap::Add(SelfEntity);

		// Register actions
		for (auto ActionClass : ActionClasses)
		{
			GoapEntity.AddAction(ActionClass);
		}

		// Register goals
		for (auto GoalClass : GoalClasses)
		{
			GoapEntity.AddGoal(GoalClass);
		}

		// Set initial world state
		for (auto Entry : InitialWorldState)
		{
			GoapEntity.Set_WorldStateValue(Entry.Key, Entry.Value);
		}

		// Apply dynamic cost override if specified
		if (ck::IsValid(CostOverrideAction) && CostOverrideValue >= 0.0f)
		{
			GoapEntity.Set_ActionCost(CostOverrideAction, CostOverrideValue);
		}

		// Request plan
		if (ck::IsValid(SpecificGoalClass))
		{
			GoapEntity.Request_PlanForGoal(SpecificGoalClass);
		}
		else
		{
			GoapEntity.Request_Plan();
		}

		PlanCount++;
		IsWaitingToRestart = false;
		TimeSinceCompletion = 0.0f;
	}

	// ================================================================================================================

	UFUNCTION()
	private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::IsValid(GoapEntity) == false)
		{ return; }

		auto DeltaSeconds = float(InDeltaT.Get_Seconds());
		auto Status = GoapEntity.Get_PlanStatus();

		auto IsTerminal = Status != ECk_GoapPlanStatus::Planning
			&& Status != ECk_GoapPlanStatus::Idle;

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
				// Re-plan
				if (ck::IsValid(SpecificGoalClass))
				{
					GoapEntity.Request_PlanForGoal(SpecificGoalClass);
				}
				else
				{
					GoapEntity.Request_Plan();
				}
				PlanCount++;
				IsWaitingToRestart = false;
				TimeSinceCompletion = 0.0f;
			}
		}

		Request_UpdateDisplay(Status, IsTerminal);
	}

	// ================================================================================================================

	private void Request_UpdateDisplay(ECk_GoapPlanStatus InStatus, bool IsTerminal)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto StatusStr = GetStatusString(InStatus);

		auto Display = f"Status: {StatusStr}    Plan #{PlanCount}\n";
		Display = f"{Display}Actions: {ActionClasses.Num()}   Goals: {GoalClasses.Num()}\n";
		Display = f"{Display}World State: {InitialWorldState.Num()} keys\n";

		if (InStatus == ECk_GoapPlanStatus::PlanFound)
		{
			auto Plan = GoapEntity.Get_Plan();
			auto Cost = GoapEntity.Get_PlanCost();

			Display = f"{Display}\nPlan ({Plan.Num()} steps, cost {Cost}):\n";
			for (int32 Index = 0; Index < Plan.Num(); Index++)
			{
				auto ActionName = Plan[Index].Get().GetName();
				Display = f"{Display}  {Index + 1}. {ActionName}\n";
			}
		}
		else if (InStatus == ECk_GoapPlanStatus::PlanFailed)
		{
			Display = f"{Display}\nNo valid plan found.\n";
		}
		else if (InStatus == ECk_GoapPlanStatus::CostThresholdReached)
		{
			Display = f"{Display}\nCost threshold exceeded.\n";
		}
		else if (InStatus == ECk_GoapPlanStatus::Planning)
		{
			Display = f"{Display}\nPlanning...";
		}

		if (IsTerminal && IsWaitingToRestart)
		{
			auto SecondsLeft = int(RestartIntervalSeconds - TimeSinceCompletion) + 1;
			Display = f"{Display}\nRestarting in {SecondsLeft}s...";
		}

		CkGym_Common::Update_StationDisplay(SelfEntity, StationTitle, Display, StationDescription);
	}

	// ================================================================================================================

	private FString GetStatusString(ECk_GoapPlanStatus InStatus)
	{
		if (InStatus == ECk_GoapPlanStatus::Idle)                 { return "IDLE"; }
		if (InStatus == ECk_GoapPlanStatus::Planning)             { return "PLANNING"; }
		if (InStatus == ECk_GoapPlanStatus::PlanFound)            { return "PLAN FOUND"; }
		if (InStatus == ECk_GoapPlanStatus::PlanFailed)           { return "PLAN FAILED"; }
		if (InStatus == ECk_GoapPlanStatus::CostThresholdReached) { return "COST THRESHOLD"; }
		return "UNKNOWN";
	}
}
