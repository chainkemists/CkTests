// Language=angelscript

//============================================================================
// GOAP EMPIRE GYM — STATION
//============================================================================
//
// Single entity script orchestrating:
//   * Planner bridge — registers all Empire actions + goals, handles
//     OnPlanComplete / OnPlanFailed, advances through the 4 progressive
//     goals (Feudal → Castle → Imperial → Wonder).
//   * Gameplay layer — owns numeric resources (Wood/Food/Gold/Stone/Pop),
//     projects them to HasEnoughX flags the planner reads, decrements on
//     action completion.
//   * Execution layer — walks each plan step through PHASE_TRAVEL (villager
//     moves to location) and PHASE_WORK (timed activity at location),
//     applies the action's GOAP effects on completion, advances to the
//     next step. When the plan is exhausted, requests the next plan.
//   * Visualization — PMG debug shapes for the 5 resource/HQ locations
//     (TownCenter, Forest, GoldMine, StoneQuarry, FarmField) and a moving
//     sphere for the villager. Buildings pop into the world as their
//     corresponding Build action completes.
//
// Everything is automatic; there is no user interaction beyond
// Ck_GymGoapEmpire_Reset to restart the simulation from Dark Age.
//============================================================================

enum ECk_GoapEmpire_Phase
{
	Idle,
	Travel,
	Work
}

class UCk_EntityScript_GoapEmpire_Station : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	// ------------------------------------------------------------------------
	// PLANNER + EXECUTION STATE
	// ------------------------------------------------------------------------

	FCk_Handle_Goap GoapEntity;
	FCk_Handle VillagerEntity;
	FCk_Handle_Pmg_DebugShape VillagerShape;
	TArray<FCk_Handle_Pmg_DebugShape> StaticShapes;    // locations drawn at spawn
	TArray<FCk_Handle_Pmg_DebugShape> BuildingShapes;  // drawn as buildings are built

	FCk_Handle_Timer StepTimer;

	TArray<TSubclassOf<UCk_GoapAction_EntityScript>> CurrentPlan;
	int32 CurrentStep = 0;
	float CurrentPlanCost = 0.0f;

	ECk_GoapEmpire_Phase Phase = ECk_GoapEmpire_Phase::Idle;
	FVector PhaseSourcePos = FVector::ZeroVector;
	FVector PhaseTargetPos = FVector::ZeroVector;
	float32 PhaseDuration = 0.0f;
	float32 PhaseElapsed  = 0.0f;
	FName PhaseActionName;

	// ------------------------------------------------------------------------
	// GAMEPLAY-LAYER NUMERIC STATE
	// ------------------------------------------------------------------------

	int32 Wood  = 0;
	int32 Food  = 0;
	int32 Gold  = 0;
	int32 Stone = 0;

	int32 Villagers    = 0;
	int32 PopulationCap = 0;

	// Statistics (displayed)
	int32 PlansRequested = 0;
	int32 PlansCompleted = 0;
	int32 PlansFailed    = 0;
	int32 StepsExecuted  = 0;
	FString LastStatus   = "Idle";

	// ------------------------------------------------------------------------
	// CONSTRUCTION
	// ------------------------------------------------------------------------

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapEmpireGym_Station");

		// Villager — its own entity so its transform can be updated independently
		// as we simulate movement between locations.
		auto VillagerStart = FTransform(InitialTransform.TransformPositionNoScale(empire_layout::TownCenter()));
		VillagerEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
		utils_transform::Add(VillagerEntity, VillagerStart, ECk_Replication::DoesNotReplicate);
		VillagerShape = utils_pmg_basic_shapes::Add_Sphere(
			VillagerEntity, FTransform::Identity,
			40.0f, 16, 16,
			ECk_Plane_Axis::XY,
			FLinearColor(0.12f, 0.55f, 0.96f, 0.9f),
			true, 2.0f, 0.0f);

		// Static location markers
		DrawLocation(InitialTransform, empire_layout::TownCenter(),  FLinearColor(0.18f, 0.73f, 0.95f, 0.4f), FVector(160.0f, 160.0f, 20.0f));
		DrawLocation(InitialTransform, empire_layout::Forest(),      FLinearColor(0.12f, 0.64f, 0.24f, 0.4f), FVector(120.0f, 120.0f, 20.0f));
		DrawLocation(InitialTransform, empire_layout::GoldMine(),    FLinearColor(0.96f, 0.76f, 0.10f, 0.4f), FVector(120.0f, 120.0f, 20.0f));
		DrawLocation(InitialTransform, empire_layout::StoneQuarry(), FLinearColor(0.70f, 0.70f, 0.72f, 0.4f), FVector(120.0f, 120.0f, 20.0f));
		DrawLocation(InitialTransform, empire_layout::FarmField(),   FLinearColor(0.88f, 0.62f, 0.32f, 0.4f), FVector(120.0f, 120.0f, 20.0f));

		// Planner entity
		GoapEntity = utils_goap::Add(InHandle);
		utils_gameplay_label::Add(GoapEntity, goapempire_tags::T(n"Gym.GoapEmpire.Station"));

		RegisterActionsAndGoals();
		SeedInitialState();

		GoapEntity.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
		GoapEntity.BindTo_OnPlanFailed  (FCk_Delegate_Goap_OnPlanFailed  (this, n"OnPlanFailed"));

		// Step timer — ticks every frame, drives PHASE_TRAVEL and PHASE_WORK.
		// ResetOnDone with Time 0 means "fire every tick until we stop it".
		auto StepTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		StepTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		StepTimer = utils_timer::Add(InHandle, StepTimerParams);
		StepTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"StepTick"));

		// Display timer — refreshes the station text panel each tick.
		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapEmpire_ResetWorld,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetWorld"));

		// Kick off the cycle.
		RequestNextPlan();

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void DrawLocation(FTransform InRoot, FVector InLocalPos, FLinearColor InColor, FVector InExtent)
	{
		auto WorldPos = InRoot.TransformPositionNoScale(InLocalPos);
		auto Shape = utils_pmg_basic_shapes::DrawFilledBox(
			WorldPos, InExtent, InColor, true, 2.0f, ECk_Plane_Axis::XY, 0.0f);
		StaticShapes.Add(Shape);
	}

	private void RegisterActionsAndGoals()
	{
		// Resource gathering
		GoapEntity.AddAction(UCk_Empire_Action_GatherWood);
		GoapEntity.AddAction(UCk_Empire_Action_GatherWoodFromCamp);
		GoapEntity.AddAction(UCk_Empire_Action_GatherFood);
		GoapEntity.AddAction(UCk_Empire_Action_GatherFoodFromFarm);
		GoapEntity.AddAction(UCk_Empire_Action_GatherFoodFromMill);
		GoapEntity.AddAction(UCk_Empire_Action_GatherGold);
		GoapEntity.AddAction(UCk_Empire_Action_GatherGoldFromCamp);
		GoapEntity.AddAction(UCk_Empire_Action_GatherStone);
		GoapEntity.AddAction(UCk_Empire_Action_GatherStoneFromCamp);
		// Population
		GoapEntity.AddAction(UCk_Empire_Action_BuildHouse);
		GoapEntity.AddAction(UCk_Empire_Action_TrainVillager);
		// Economy
		GoapEntity.AddAction(UCk_Empire_Action_BuildLumberCamp);
		GoapEntity.AddAction(UCk_Empire_Action_BuildMill);
		GoapEntity.AddAction(UCk_Empire_Action_BuildMiningCamp);
		GoapEntity.AddAction(UCk_Empire_Action_BuildFarm);
		GoapEntity.AddAction(UCk_Empire_Action_BuildDock);
		GoapEntity.AddAction(UCk_Empire_Action_BuildMarket);
		// Military buildings
		GoapEntity.AddAction(UCk_Empire_Action_BuildBarracks);
		GoapEntity.AddAction(UCk_Empire_Action_BuildArchery);
		GoapEntity.AddAction(UCk_Empire_Action_BuildStable);
		GoapEntity.AddAction(UCk_Empire_Action_BuildBlacksmith);
		GoapEntity.AddAction(UCk_Empire_Action_BuildMonastery);
		GoapEntity.AddAction(UCk_Empire_Action_BuildUniversity);
		GoapEntity.AddAction(UCk_Empire_Action_BuildSiegeWorkshop);
		GoapEntity.AddAction(UCk_Empire_Action_BuildCastle);
		GoapEntity.AddAction(UCk_Empire_Action_BuildWonder);
		// Age advances
		GoapEntity.AddAction(UCk_Empire_Action_AdvanceToFeudalAge);
		GoapEntity.AddAction(UCk_Empire_Action_AdvanceToCastleAge);
		GoapEntity.AddAction(UCk_Empire_Action_AdvanceToImperialAge);
		// Research
		GoapEntity.AddAction(UCk_Empire_Action_ResearchLoom);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchWheelbarrow);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchHandCart);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchGoldMining);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchStoneMining);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchCrossbow);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchFletching);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchHusbandry);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchBloodlines);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchEliteSkirmisher);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchChemistry);
		GoapEntity.AddAction(UCk_Empire_Action_ResearchBallistics);
		// Trade
		GoapEntity.AddAction(UCk_Empire_Action_TradeForFood);
		// Training
		GoapEntity.AddAction(UCk_Empire_Action_TrainMilitia);
		GoapEntity.AddAction(UCk_Empire_Action_TrainSpearman);
		GoapEntity.AddAction(UCk_Empire_Action_TrainArcher);
		GoapEntity.AddAction(UCk_Empire_Action_TrainKnight);
		GoapEntity.AddAction(UCk_Empire_Action_TrainMonk);
		GoapEntity.AddAction(UCk_Empire_Action_TrainSiegeRam);
		GoapEntity.AddAction(UCk_Empire_Action_TrainTrebuchet);

		// Goals (highest pri first is picked when unsatisfied)
		GoapEntity.AddGoal(UCk_Empire_Goal_ReachFeudalAge);
		GoapEntity.AddGoal(UCk_Empire_Goal_ReachCastleAge);
		GoapEntity.AddGoal(UCk_Empire_Goal_ReachImperialAge);
		GoapEntity.AddGoal(UCk_Empire_Goal_BuildWonder);
	}

	private void SeedInitialState()
	{
		Wood  = 0;
		Food  = 0;
		Gold  = 0;
		Stone = 0;
		Villagers     = empire_tuning::InitialVillagers;
		PopulationCap = empire_tuning::InitialPopCap;

		// Ages — Dark only at start.
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::IsInDarkAge),      true);
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::IsInFeudalAge),    false);
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::IsInCastleAge),    false);
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::IsInImperialAge),  false);

		// Seed all building/research/army flags to false so they appear in the
		// debugger's world-state panel from the first frame.
		auto AllFlags = TArray<FName>();
		AllFlags.Add(empire_tags::HasHouse);
		AllFlags.Add(empire_tags::HasLumberCamp);
		AllFlags.Add(empire_tags::HasMill);
		AllFlags.Add(empire_tags::HasMiningCamp);
		AllFlags.Add(empire_tags::HasFarm);
		AllFlags.Add(empire_tags::HasDock);
		AllFlags.Add(empire_tags::HasMarket);
		AllFlags.Add(empire_tags::HasBarracks);
		AllFlags.Add(empire_tags::HasArchery);
		AllFlags.Add(empire_tags::HasStable);
		AllFlags.Add(empire_tags::HasBlacksmith);
		AllFlags.Add(empire_tags::HasMonastery);
		AllFlags.Add(empire_tags::HasUniversity);
		AllFlags.Add(empire_tags::HasSiegeWorkshop);
		AllFlags.Add(empire_tags::HasCastle);
		AllFlags.Add(empire_tags::HasWonder);
		AllFlags.Add(empire_tags::HasResearchedLoom);
		AllFlags.Add(empire_tags::HasResearchedWheelbarrow);
		AllFlags.Add(empire_tags::HasResearchedHandCart);
		AllFlags.Add(empire_tags::HasResearchedGoldMining);
		AllFlags.Add(empire_tags::HasResearchedStoneMining);
		AllFlags.Add(empire_tags::HasResearchedCrossbow);
		AllFlags.Add(empire_tags::HasResearchedFletching);
		AllFlags.Add(empire_tags::HasResearchedHusbandry);
		AllFlags.Add(empire_tags::HasResearchedBloodlines);
		AllFlags.Add(empire_tags::HasResearchedEliteSkirmisher);
		AllFlags.Add(empire_tags::HasResearchedChemistry);
		AllFlags.Add(empire_tags::HasResearchedBallistics);
		AllFlags.Add(empire_tags::HasArmyLight);
		AllFlags.Add(empire_tags::HasArmyHeavy);
		AllFlags.Add(empire_tags::HasArmyRanged);
		AllFlags.Add(empire_tags::HasArmyCavalry);
		AllFlags.Add(empire_tags::HasArmySiege);
		AllFlags.Add(empire_tags::HasEnoughVillagers);
		for (auto Tag : AllFlags)
		{
			utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(Tag), false);
		}

		// Resource flags — driven by gameplay each tick, seed them explicitly.
		ProjectGameplayFlags();
	}

	// ------------------------------------------------------------------------
	// GAMEPLAY FLAG PROJECTION — numerics → booleans
	// ------------------------------------------------------------------------
	//
	// Called after every resource / population change. The planner only ever
	// reads these flags; it NEVER sets them (see design doc in Shared.as).

	private void ProjectGameplayFlags()
	{
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::HasEnoughWood),
			Wood >= empire_tuning::ThresholdWood);
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::HasEnoughFood),
			Food >= empire_tuning::ThresholdFood);
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::HasEnoughGold),
			Gold >= empire_tuning::ThresholdGold);
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::HasEnoughStone),
			Stone >= empire_tuning::ThresholdStone);
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::HasFreePopulation),
			(PopulationCap - Villagers) >= 1);
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::HasEnoughVillagers),
			Villagers >= empire_tuning::EnoughVillagersThreshold);
	}

	// ------------------------------------------------------------------------
	// PLAN LIFECYCLE
	// ------------------------------------------------------------------------

	private void RequestNextPlan()
	{
		CurrentPlan.Reset();
		CurrentStep = 0;
		Phase = ECk_GoapEmpire_Phase::Idle;
		GoapEntity.Request_Plan();
		PlansRequested++;
		LastStatus = "Planning";
	}

	UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
	{
		CurrentPlan = InPayload.Get_Actions();
		CurrentPlanCost = InPayload.Get_TotalCost();
		CurrentStep = 0;
		PlansCompleted++;

		if (CurrentPlan.Num() == 0)
		{
			// No-op plan — all goals already satisfied. Reset and try again.
			LastStatus = "All goals satisfied — resetting";
			ResetWorld();
			return;
		}

		LastStatus = f"Plan ({CurrentPlan.Num()} steps, cost {CurrentPlanCost})";
		BeginStep(CurrentStep);
	}

	UFUNCTION() private void OnPlanFailed(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanFailed InPayload)
	{
		PlansFailed++;
		LastStatus = "Plan FAILED — replanning next frame";
		// Try again — world state is continuously projected, so a failure here
		// is typically a transient (gameplay flag momentarily false) and the
		// next request will succeed. If it persists the Failure Analysis panel
		// will explain why.
		Phase = ECk_GoapEmpire_Phase::Idle;
	}

	// ------------------------------------------------------------------------
	// STEP EXECUTION
	// ------------------------------------------------------------------------

	private void BeginStep(int32 InIndex)
	{
		if (InIndex >= CurrentPlan.Num())
		{
			// Plan exhausted — request the next one.
			Phase = ECk_GoapEmpire_Phase::Idle;
			RequestNextPlan();
			return;
		}

		auto ActionClass = CurrentPlan[InIndex];
		if (!ck::IsValid(ActionClass))
		{
			CurrentStep++;
			BeginStep(CurrentStep);
			return;
		}

		auto ActionName = ActionClass.Get().GetName();
		PhaseActionName = FName(ActionName);

		// Choose the target location for this action.
		auto Target = ResolveActionTarget(FName(ActionName));
		PhaseSourcePos = GetVillagerPosition();
		PhaseTargetPos = InitialTransform.TransformPositionNoScale(Target);

		auto Distance = (PhaseTargetPos - PhaseSourcePos).Size();
		PhaseDuration = Distance / empire_tuning::VillagerSpeed;
		PhaseElapsed = 0.0f;

		if (PhaseDuration <= 0.01f)
		{
			// Already at destination — go straight to work.
			EnterWorkPhase();
		}
		else
		{
			Phase = ECk_GoapEmpire_Phase::Travel;
		}
	}

	private void EnterWorkPhase()
	{
		Phase = ECk_GoapEmpire_Phase::Work;
		PhaseDuration = ResolveActionWorkDuration(PhaseActionName);
		PhaseElapsed = 0.0f;
	}

	UFUNCTION() private void StepTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (Phase == ECk_GoapEmpire_Phase::Idle) { return; }

		PhaseElapsed = PhaseElapsed + InDeltaT.Get_Seconds();

		if (Phase == ECk_GoapEmpire_Phase::Travel)
		{
			auto Alpha = PhaseDuration > 0.0f ? Math::Min(PhaseElapsed / PhaseDuration, 1.0f) : 1.0f;
			auto NewPos = PhaseSourcePos + (PhaseTargetPos - PhaseSourcePos) * Alpha;
			SetVillagerPosition(NewPos);

			if (Alpha >= 1.0f) { EnterWorkPhase(); }
			return;
		}

		if (Phase == ECk_GoapEmpire_Phase::Work)
		{
			if (PhaseElapsed >= PhaseDuration)
			{
				ApplyActionCompletion(PhaseActionName);
				StepsExecuted++;
				CurrentStep++;
				BeginStep(CurrentStep);
			}
		}
	}

	// ------------------------------------------------------------------------
	// ACTION → (location, work duration, completion effect) LOOKUP
	// ------------------------------------------------------------------------

	private FVector ResolveActionTarget(FName InActionName)
	{
		auto S = InActionName.ToString();
		if (S.Contains("GatherWood"))  { return empire_layout::Forest(); }
		if (S.Contains("GatherFood"))  { return empire_layout::FarmField(); }
		if (S.Contains("GatherGold"))  { return empire_layout::GoldMine(); }
		if (S.Contains("GatherStone")) { return empire_layout::StoneQuarry(); }
		// Every build / train / research / advance happens near the TownCenter
		// (villager travels back, representing resource delivery + construction).
		return empire_layout::TownCenter();
	}

	private float32 ResolveActionWorkDuration(FName InActionName)
	{
		auto S = InActionName.ToString();
		if (S.Contains("GatherWood"))  { return empire_tuning::WorkGatherWood; }
		if (S.Contains("GatherFood"))  { return empire_tuning::WorkGatherFood; }
		if (S.Contains("GatherGold"))  { return empire_tuning::WorkGatherGold; }
		if (S.Contains("GatherStone")) { return empire_tuning::WorkGatherStone; }
		if (S.Contains("Research"))    { return empire_tuning::WorkResearch; }
		if (S.Contains("Train"))       { return empire_tuning::WorkTrainUnit; }
		if (S.Contains("Advance"))     { return empire_tuning::WorkAdvanceAge; }
		if (S.Contains("Trade"))       { return empire_tuning::WorkTrainUnit; }
		if (S.Contains("Build"))       { return empire_tuning::WorkBuild; }
		return empire_tuning::WorkBuild;
	}

	// Apply the action's EFFECT side on completion:
	//  - Gather actions: add yield to the numeric stockpile, re-project flags.
	//  - Build / Research / Train / Advance: decrement cost(s) from numerics,
	//    then flip the corresponding GOAP-effect flag, spawn building visuals
	//    if applicable, and re-project flags.
	private void ApplyActionCompletion(FName InActionName)
	{
		auto S = InActionName.ToString();

		// Resource gathers — purely additive
		if (S.Contains("GatherWood"))  { Wood  = Wood  + empire_tuning::YieldWood;  ProjectGameplayFlags(); return; }
		if (S.Contains("GatherFood"))  { Food  = Food  + empire_tuning::YieldFood;  ProjectGameplayFlags(); return; }
		if (S.Contains("GatherGold"))  { Gold  = Gold  + empire_tuning::YieldGold;  ProjectGameplayFlags(); return; }
		if (S.Contains("GatherStone")) { Stone = Stone + empire_tuning::YieldStone; ProjectGameplayFlags(); return; }

		// Trade: spend gold → get food
		if (S.Contains("Trade"))
		{
			Gold = Math::Max(0, Gold - empire_tuning::ThresholdGold);
			Food = Food + empire_tuning::YieldFood;
			ProjectGameplayFlags();
			return;
		}

		// Builds — each has its own cost + flag + visual slot.
		if (S == "Ck_Empire_Action_BuildHouse_C")
			{ SpendAndFlag(empire_tags::HasHouse, empire_tuning::CostHouseWood, 0, 0, 0); PopulationCap = PopulationCap + empire_tuning::PopPerHouse; ProjectGameplayFlags(); SpawnBuildingShape(0, FLinearColor(0.92f, 0.85f, 0.62f, 0.7f)); return; }
		if (S == "Ck_Empire_Action_BuildLumberCamp_C")
			{ SpendAndFlag(empire_tags::HasLumberCamp, empire_tuning::CostLumberCampWood, 0, 0, 0); SpawnBuildingNear(empire_layout::Forest(), FLinearColor(0.30f, 0.48f, 0.20f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildMill_C")
			{ SpendAndFlag(empire_tags::HasMill, empire_tuning::CostMillWood, 0, 0, 0); SpawnBuildingShape(6, FLinearColor(0.85f, 0.75f, 0.50f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildMiningCamp_C")
			{ SpendAndFlag(empire_tags::HasMiningCamp, empire_tuning::CostMiningCampWood, 0, 0, 0); SpawnBuildingNear(empire_layout::GoldMine(), FLinearColor(0.70f, 0.55f, 0.18f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildFarm_C")
			{ SpendAndFlag(empire_tags::HasFarm, empire_tuning::CostFarmWood, 0, 0, 0); SpawnBuildingNear(empire_layout::FarmField(), FLinearColor(0.88f, 0.62f, 0.32f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildDock_C")
			{ SpendAndFlag(empire_tags::HasDock, empire_tuning::CostDockWood, 0, 0, 0); SpawnBuildingShape(0, FLinearColor(0.45f, 0.70f, 0.85f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildMarket_C")
			{ SpendAndFlag(empire_tags::HasMarket, empire_tuning::CostMarketWood, 0, 0, 0); SpawnBuildingShape(5, FLinearColor(0.94f, 0.74f, 0.22f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildBarracks_C")
			{ SpendAndFlag(empire_tags::HasBarracks, empire_tuning::CostBarracksWood, 0, 0, 0); SpawnBuildingShape(1, FLinearColor(0.75f, 0.25f, 0.25f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildArchery_C")
			{ SpendAndFlag(empire_tags::HasArchery, empire_tuning::CostArcheryWood, 0, 0, 0); SpawnBuildingShape(2, FLinearColor(0.65f, 0.35f, 0.18f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildStable_C")
			{ SpendAndFlag(empire_tags::HasStable, empire_tuning::CostStableWood, 0, 0, 0); SpawnBuildingShape(3, FLinearColor(0.55f, 0.35f, 0.20f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildBlacksmith_C")
			{ SpendAndFlag(empire_tags::HasBlacksmith, empire_tuning::CostBlacksmithWood, 0, 0, 0); SpawnBuildingShape(4, FLinearColor(0.40f, 0.40f, 0.44f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildMonastery_C")
			{ SpendAndFlag(empire_tags::HasMonastery, empire_tuning::CostMonasteryWood, 0, 0, 0); SpawnBuildingShape(7, FLinearColor(0.92f, 0.92f, 0.98f, 0.8f)); return; }
		if (S == "Ck_Empire_Action_BuildUniversity_C")
			{ SpendAndFlag(empire_tags::HasUniversity, empire_tuning::CostUniversityWood, 0, 0, empire_tuning::CostUniversityStone); SpawnBuildingShape(7, FLinearColor(0.88f, 0.82f, 0.65f, 0.85f)); return; }
		if (S == "Ck_Empire_Action_BuildSiegeWorkshop_C")
			{ SpendAndFlag(empire_tags::HasSiegeWorkshop, empire_tuning::CostSiegeWorkshopWood, 0, 0, 0); SpawnBuildingShape(7, FLinearColor(0.55f, 0.45f, 0.25f, 0.85f)); return; }
		if (S == "Ck_Empire_Action_BuildCastle_C")
			{ SpendAndFlag(empire_tags::HasCastle, 0, 0, 0, empire_tuning::CostCastleStone); SpawnBuildingShape(7, FLinearColor(0.72f, 0.75f, 0.80f, 0.9f)); return; }
		if (S == "Ck_Empire_Action_BuildWonder_C")
			{ SpendAndFlag(empire_tags::HasWonder, empire_tuning::CostWonderWood, 0, empire_tuning::CostWonderGold, empire_tuning::CostWonderStone); SpawnWonderShape(); return; }

		// Age advances — spend food (+ gold on Castle / Imperial), flip flag.
		if (S == "Ck_Empire_Action_AdvanceToFeudalAge_C")
			{ SpendAndFlag(empire_tags::IsInFeudalAge, 0, empire_tuning::CostAdvanceFeudalFood, 0, 0); return; }
		if (S == "Ck_Empire_Action_AdvanceToCastleAge_C")
			{ SpendAndFlag(empire_tags::IsInCastleAge, 0, empire_tuning::CostAdvanceCastleFood, empire_tuning::CostAdvanceCastleGold, 0); return; }
		if (S == "Ck_Empire_Action_AdvanceToImperialAge_C")
			{ SpendAndFlag(empire_tags::IsInImperialAge, 0, empire_tuning::CostAdvanceImperialFood, empire_tuning::CostAdvanceImperialGold, 0); return; }

		// Research — all uniform cost (food + gold, flip flag)
		auto ResearchFlag = FName();
		if      (S == "Ck_Empire_Action_ResearchLoom_C")             { ResearchFlag = empire_tags::HasResearchedLoom; }
		else if (S == "Ck_Empire_Action_ResearchWheelbarrow_C")      { ResearchFlag = empire_tags::HasResearchedWheelbarrow; }
		else if (S == "Ck_Empire_Action_ResearchHandCart_C")         { ResearchFlag = empire_tags::HasResearchedHandCart; }
		else if (S == "Ck_Empire_Action_ResearchGoldMining_C")       { ResearchFlag = empire_tags::HasResearchedGoldMining; }
		else if (S == "Ck_Empire_Action_ResearchStoneMining_C")      { ResearchFlag = empire_tags::HasResearchedStoneMining; }
		else if (S == "Ck_Empire_Action_ResearchCrossbow_C")         { ResearchFlag = empire_tags::HasResearchedCrossbow; }
		else if (S == "Ck_Empire_Action_ResearchFletching_C")        { ResearchFlag = empire_tags::HasResearchedFletching; }
		else if (S == "Ck_Empire_Action_ResearchHusbandry_C")        { ResearchFlag = empire_tags::HasResearchedHusbandry; }
		else if (S == "Ck_Empire_Action_ResearchBloodlines_C")       { ResearchFlag = empire_tags::HasResearchedBloodlines; }
		else if (S == "Ck_Empire_Action_ResearchEliteSkirmisher_C")  { ResearchFlag = empire_tags::HasResearchedEliteSkirmisher; }
		else if (S == "Ck_Empire_Action_ResearchChemistry_C")        { ResearchFlag = empire_tags::HasResearchedChemistry; }
		else if (S == "Ck_Empire_Action_ResearchBallistics_C")       { ResearchFlag = empire_tags::HasResearchedBallistics; }
		if (ResearchFlag.IsValid())
		{
			SpendAndFlag(ResearchFlag, 0, empire_tuning::CostResearchFood, empire_tuning::CostResearchGold, 0);
			return;
		}

		// Unit training — flag effect is on HasArmyXxx (already set by planner
		// via effect); we just spend the numeric cost.
		if (S == "Ck_Empire_Action_TrainVillager_C")
		{
			Food = Math::Max(0, Food - empire_tuning::CostTrainVillagerFood);
			Villagers = Villagers + 1;
			ProjectGameplayFlags();
			return;
		}
		if (S.Contains("Train"))
		{
			// Any non-villager unit: spend food + gold
			Food = Math::Max(0, Food - empire_tuning::CostTrainUnitFood);
			Gold = Math::Max(0, Gold - empire_tuning::CostTrainUnitGold);
			ProjectGameplayFlags();
			return;
		}
	}

	// Decrement numeric costs and set the GOAP-effect flag true. Keeps the
	// caller short for what's essentially the build/research/advance pattern.
	private void SpendAndFlag(FName InFlag, int32 InWoodCost, int32 InFoodCost, int32 InGoldCost, int32 InStoneCost)
	{
		Wood  = Math::Max(0, Wood  - InWoodCost);
		Food  = Math::Max(0, Food  - InFoodCost);
		Gold  = Math::Max(0, Gold  - InGoldCost);
		Stone = Math::Max(0, Stone - InStoneCost);
		utils_goap::Set_WorldStateValue(GoapEntity, goapempire_tags::T(InFlag), true);
		ProjectGameplayFlags();
	}

	// ------------------------------------------------------------------------
	// VISUALS — villager movement + building spawn
	// ------------------------------------------------------------------------

	private FVector GetVillagerPosition()
	{
		return utils_transform::Get_EntityCurrentLocation(VillagerEntity);
	}

	private void SetVillagerPosition(FVector InWorldPos)
	{
		utils_transform::Request_SetLocation(VillagerEntity, InWorldPos, ECk_LocalWorld::World);
	}

	private void SpawnBuildingShape(int32 InSlotIndex, FLinearColor InColor)
	{
		auto LocalPos = empire_layout::BuildingSlot(InSlotIndex);
		auto WorldPos = InitialTransform.TransformPositionNoScale(LocalPos);
		auto Shape = utils_pmg_basic_shapes::DrawFilledBox(
			WorldPos, FVector(80.0f, 80.0f, 120.0f),
			InColor, true, 2.0f, ECk_Plane_Axis::XY, 0.0f);
		BuildingShapes.Add(Shape);
	}

	private void SpawnBuildingNear(FVector InLocal, FLinearColor InColor)
	{
		// Place the building slightly offset so it doesn't occlude the
		// location marker shape below it.
		auto WorldPos = InitialTransform.TransformPositionNoScale(InLocal + FVector(0.0f, 0.0f, 40.0f));
		auto Shape = utils_pmg_basic_shapes::DrawFilledBox(
			WorldPos, FVector(70.0f, 70.0f, 90.0f),
			InColor, true, 2.0f, ECk_Plane_Axis::XY, 0.0f);
		BuildingShapes.Add(Shape);
	}

	private void SpawnWonderShape()
	{
		auto WorldPos = InitialTransform.TransformPositionNoScale(empire_layout::TownCenter() + FVector(0.0f, 0.0f, 200.0f));
		auto Shape = utils_pmg_basic_shapes::DrawFilledPyramid(
			WorldPos, 200.0f, 300.0f,
			FLinearColor(1.00f, 0.85f, 0.20f, 0.9f),
			true, 3.0f, ECk_Plane_Axis::XY, 0.0f);
		BuildingShapes.Add(Shape);
	}

	// ------------------------------------------------------------------------
	// RESET CYCLE — clear all visuals, seed initial state, restart planning
	// ------------------------------------------------------------------------

	private void ResetWorld()
	{
		// Note: we don't destroy building shape entities on reset because PMG
		// typesafe handles don't trivially cast to FCk_Handle for
		// Request_DestroyEntity in AS. The cycler will overdraw — fine for
		// a demo. A followup can add a PMG shape teardown utility.
		BuildingShapes.Reset();

		CurrentPlan.Reset();
		CurrentStep = 0;
		Phase = ECk_GoapEmpire_Phase::Idle;

		SetVillagerPosition(InitialTransform.TransformPositionNoScale(empire_layout::TownCenter()));

		SeedInitialState();
		RequestNextPlan();
	}

	UFUNCTION() private void OnResetWorld(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		ResetWorld();
	}

	// ------------------------------------------------------------------------
	// DISPLAY
	// ------------------------------------------------------------------------

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDt)
	{
		auto SelfEntity = ck::ToEntity(this);

		// Current active goal's class name (best we can do from AS without more bindings)
		auto ActiveAge = "Dark";
		if (utils_goap::Get_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::IsInImperialAge))) { ActiveAge = "Imperial"; }
		else if (utils_goap::Get_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::IsInCastleAge)))  { ActiveAge = "Castle"; }
		else if (utils_goap::Get_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::IsInFeudalAge)))  { ActiveAge = "Feudal"; }

		auto HasWonder = utils_goap::Get_WorldStateValue(GoapEntity, goapempire_tags::T(empire_tags::HasWonder));

		auto PhaseStr = "Idle";
		if (Phase == ECk_GoapEmpire_Phase::Travel) { PhaseStr = f"Travel {int32(PhaseElapsed / Math::Max(0.01f, PhaseDuration) * 100.0f)}%"; }
		if (Phase == ECk_GoapEmpire_Phase::Work)   { PhaseStr = f"Work {int32(PhaseElapsed / Math::Max(0.01f, PhaseDuration) * 100.0f)}%"; }

		auto CurrentAction = CurrentStep < CurrentPlan.Num() && ck::IsValid(CurrentPlan[CurrentStep])
			? CurrentPlan[CurrentStep].Get().GetName()
			: "—";

		auto Text = f"Age: {ActiveAge}    Wonder: {HasWonder}\n";
		Text = Text + f"Plan step: {CurrentStep + 1}/{CurrentPlan.Num()}    Action: {CurrentAction}\n";
		Text = Text + f"Phase: {PhaseStr}\n";
		Text = Text + f"Status: {LastStatus}\n\n";
		Text = Text + f"-- Resources --\n";
		Text = Text + f"  Wood={Wood}  Food={Food}  Gold={Gold}  Stone={Stone}\n";
		Text = Text + f"  Villagers={Villagers}/{PopulationCap}\n\n";
		Text = Text + f"-- Stats --\n";
		Text = Text + f"  Plans: requested={PlansRequested} completed={PlansCompleted} failed={PlansFailed}\n";
		Text = Text + f"  Steps executed: {StepsExecuted}\n";

		CkGym_Common::Update_StationDisplay(SelfEntity, "GOAP EMPIRE — BOOLEAN STRESS TEST", Text, "");
	}
}
