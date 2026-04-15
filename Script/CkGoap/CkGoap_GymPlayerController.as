class ACk_GoapGym_PlayerController : ACk_Gym_Base_PlayerController
{
	TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
	{
		auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

		Stations.Add(MakeStationPayload(n"Gym.Goap.SimplePlan", "Simple Plan",
			"1 goal, 2 actions.\nAgent has nothing, goal is ArmUp.\nPlan: PickUpWeapon -> LoadAmmo."));

		Stations.Add(MakeStationPayload(n"Gym.Goap.MultiStepPlan", "Multi-Step Plan",
			"Kill enemy from scratch.\nAgent starts with nothing.\nPlanner finds cheapest action chain."));

		Stations.Add(MakeStationPayload(n"Gym.Goap.NoPlanPossible", "No Plan Possible",
			"Goal requires EnemyAlive=false.\nNo Attack action registered.\nDemonstrates PlanFailed status."));

		Stations.Add(MakeStationPayload(n"Gym.Goap.GoalAlreadySatisfied", "Goal Already Satisfied",
			"World state already satisfies goal.\nPlanner returns immediately."));

		Stations.Add(MakeStationPayload(n"Gym.Goap.CostComparison", "Cost Comparison",
			"Two paths to kill enemy:\nRanged (cost 7) vs Melee (cost 8).\nPlanner picks cheapest."));

		Stations.Add(MakeStationPayload(n"Gym.Goap.DynamicCostUpdate", "Dynamic Cost Update",
			"Same as CostComparison but\nmelee cost updated to 3 before planning.\nPlanner now picks melee (5 < 7)."));

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

	private FGameplayTag Tag(FName InName)
	{
		return GameplayTags::ResolveGameplayTag(InName);
	}

	void Request_StartGym() override
	{
		// ------------------------------------------------------------------------------------------
		// Station 1: Simple Plan — two actions, one goal
		// ------------------------------------------------------------------------------------------
		{
			auto WS = TMap<FGameplayTag, bool>();
			WS.Add(Tag(n"Goap.WS.HasWeapon"), false);
			WS.Add(Tag(n"Goap.WS.HasAmmo"), false);

			auto Actions = TArray<TSubclassOf<UCk_GoapAction_EntityScript>>();
			Actions.Add(UCk_GoapTest_Action_PickUpWeapon);
			Actions.Add(UCk_GoapTest_Action_LoadAmmo);

			auto Goals = TArray<TSubclassOf<UCk_GoapGoal_EntityScript>>();
			Goals.Add(UCk_GoapTest_Goal_ArmUp);

			SpawnStation("Gym.Goap.SimplePlan", "SIMPLE PLAN",
				"Goal: HasWeapon+HasAmmo. Two actions available.\nExpected plan: PickUpWeapon -> LoadAmmo (cost 3).",
				Actions, Goals, WS);
		}

		// ------------------------------------------------------------------------------------------
		// Station 2: Multi-Step Plan — full kill chain
		// ------------------------------------------------------------------------------------------
		{
			auto WS = TMap<FGameplayTag, bool>();
			WS.Add(Tag(n"Goap.WS.HasWeapon"), false);
			WS.Add(Tag(n"Goap.WS.HasAmmo"), false);
			WS.Add(Tag(n"Goap.WS.EnemyVisible"), false);
			WS.Add(Tag(n"Goap.WS.EnemyInRange"), false);
			WS.Add(Tag(n"Goap.WS.EnemyAlive"), true);

			auto Actions = TArray<TSubclassOf<UCk_GoapAction_EntityScript>>();
			Actions.Add(UCk_GoapTest_Action_PickUpWeapon);
			Actions.Add(UCk_GoapTest_Action_LoadAmmo);
			Actions.Add(UCk_GoapTest_Action_Scout);
			Actions.Add(UCk_GoapTest_Action_Approach);
			Actions.Add(UCk_GoapTest_Action_Attack);

			auto Goals = TArray<TSubclassOf<UCk_GoapGoal_EntityScript>>();
			Goals.Add(UCk_GoapTest_Goal_KillEnemy);

			SpawnStation("Gym.Goap.MultiStepPlan", "MULTI-STEP PLAN",
				"Goal: EnemyAlive=false. Starting from nothing.\nExpected plan: PickUpWeapon -> LoadAmmo -> Scout -> Approach -> Attack\nTotal cost: 2+1+3+2+4 = 12.",
				Actions, Goals, WS);
		}

		// ------------------------------------------------------------------------------------------
		// Station 3: No Plan Possible
		// ------------------------------------------------------------------------------------------
		{
			auto WS = TMap<FGameplayTag, bool>();
			WS.Add(Tag(n"Goap.WS.EnemyAlive"), true);

			auto Actions = TArray<TSubclassOf<UCk_GoapAction_EntityScript>>();
			Actions.Add(UCk_GoapTest_Action_Scout);
			Actions.Add(UCk_GoapTest_Action_TakeCover);

			auto Goals = TArray<TSubclassOf<UCk_GoapGoal_EntityScript>>();
			Goals.Add(UCk_GoapTest_Goal_KillEnemy);

			SpawnStation("Gym.Goap.NoPlanPossible", "NO PLAN POSSIBLE",
				"Goal: EnemyAlive=false. Only Scout and TakeCover available.\nNeither can kill the enemy. Expected: PlanFailed.",
				Actions, Goals, WS);
		}

		// ------------------------------------------------------------------------------------------
		// Station 4: Goal Already Satisfied
		// ------------------------------------------------------------------------------------------
		{
			auto WS = TMap<FGameplayTag, bool>();
			WS.Add(Tag(n"Goap.WS.HasWeapon"), true);
			WS.Add(Tag(n"Goap.WS.HasAmmo"), true);

			auto Actions = TArray<TSubclassOf<UCk_GoapAction_EntityScript>>();
			Actions.Add(UCk_GoapTest_Action_PickUpWeapon);
			Actions.Add(UCk_GoapTest_Action_LoadAmmo);

			auto Goals = TArray<TSubclassOf<UCk_GoapGoal_EntityScript>>();
			Goals.Add(UCk_GoapTest_Goal_ArmUp);

			SpawnStation("Gym.Goap.GoalAlreadySatisfied", "GOAL ALREADY SATISFIED",
				"Goal: HasWeapon+HasAmmo. World state already has both.\nExpected: PlanFound with 0 actions (already satisfied).",
				Actions, Goals, WS);
		}

		// ------------------------------------------------------------------------------------------
		// Station 5: Cost Comparison — ranged vs melee
		// ------------------------------------------------------------------------------------------
		{
			auto WS = TMap<FGameplayTag, bool>();
			WS.Add(Tag(n"Goap.WS.HasWeapon"), false);
			WS.Add(Tag(n"Goap.WS.HasAmmo"), false);
			WS.Add(Tag(n"Goap.WS.EnemyInRange"), true);
			WS.Add(Tag(n"Goap.WS.EnemyAlive"), true);

			auto Actions = TArray<TSubclassOf<UCk_GoapAction_EntityScript>>();
			Actions.Add(UCk_GoapTest_Action_PickUpWeapon);
			Actions.Add(UCk_GoapTest_Action_LoadAmmo);
			Actions.Add(UCk_GoapTest_Action_Attack);
			Actions.Add(UCk_GoapTest_Action_MeleeAttack);

			auto Goals = TArray<TSubclassOf<UCk_GoapGoal_EntityScript>>();
			Goals.Add(UCk_GoapTest_Goal_KillEnemy);

			SpawnStation("Gym.Goap.CostComparison", "COST COMPARISON",
				"Two paths: Ranged (PickUp+Load+Attack = 2+1+4=7)\nvs Melee (PickUp+Melee = 2+6=8).\nExpected: Ranged path (cost 7).",
				Actions, Goals, WS);
		}

		// ------------------------------------------------------------------------------------------
		// Station 6: Dynamic Cost Update — melee becomes cheaper
		// ------------------------------------------------------------------------------------------
		{
			auto WS = TMap<FGameplayTag, bool>();
			WS.Add(Tag(n"Goap.WS.HasWeapon"), false);
			WS.Add(Tag(n"Goap.WS.HasAmmo"), false);
			WS.Add(Tag(n"Goap.WS.EnemyInRange"), true);
			WS.Add(Tag(n"Goap.WS.EnemyAlive"), true);

			auto Actions = TArray<TSubclassOf<UCk_GoapAction_EntityScript>>();
			Actions.Add(UCk_GoapTest_Action_PickUpWeapon);
			Actions.Add(UCk_GoapTest_Action_LoadAmmo);
			Actions.Add(UCk_GoapTest_Action_Attack);
			Actions.Add(UCk_GoapTest_Action_MeleeAttack);

			auto Goals = TArray<TSubclassOf<UCk_GoapGoal_EntityScript>>();
			Goals.Add(UCk_GoapTest_Goal_KillEnemy);

			SpawnStation("Gym.Goap.DynamicCostUpdate", "DYNAMIC COST UPDATE",
				"Same actions as CostComparison but MeleeAttack cost\nupdated to 3.0 before planning.\nExpected: Melee path (PickUp+Melee = 2+3=5).",
				Actions, Goals, WS,
				UCk_GoapTest_Action_MeleeAttack, 3.0f);
		}
	}

	// ================================================================================================================

	private void SpawnStation(
		FString InTag,
		FString InTitle,
		FString InDescription,
		TArray<TSubclassOf<UCk_GoapAction_EntityScript>> InActions,
		TArray<TSubclassOf<UCk_GoapGoal_EntityScript>> InGoals,
		TMap<FGameplayTag, bool> InWorldState,
		TSubclassOf<UCk_GoapAction_EntityScript> InCostOverrideAction = nullptr,
		float InCostOverrideValue = -1.0f)
	{
		auto Params = FCkGoap_GymStationSpawnParams();
		Params.InitialTransform = Get_StationTransform(InTag);
		Params.StationTitle = InTitle;
		Params.StationDescription = InDescription;
		Params.ActionClasses = InActions;
		Params.GoalClasses = InGoals;
		Params.InitialWorldState = InWorldState;
		Params.CostOverrideAction = InCostOverrideAction;
		Params.CostOverrideValue = InCostOverrideValue;

		utils_entity_script::Request_SpawnEntity(
			Get_StationHandle(InTag),
			UCk_EntityScript_GoapGym_Station,
			FInstancedStruct::Make(Params));
	}

	UFUNCTION(Exec, DisplayName="GOAP Gym - Restart All")
	void Ck_GymGoap_RestartAll()
	{
		Request_StartGym();
	}
};
