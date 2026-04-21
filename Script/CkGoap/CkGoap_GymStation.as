// Language=angelscript

//============================================================================
// GOAP GYM — STATION ENTITY SCRIPTS
//============================================================================
// One entity script per station. Each station owns:
//   - a GOAP planner entity with its own actions / goals / world state
//   - an AutoTimer that cycles through a scripted sequence of replan scenarios
//   - message bindings for manual exec commands
//   - a display timer that paints the station text each frame
//
// Auto cycle semantics: GOAP only plans once per request, so each AutoTick
// step MUTATES inputs (world state, costs, goal) and then re-plans. This
// reproduces the mockup's timeline (see goap_debugger_D.html) where the
// planner reacts to an evolving world over time.
//
// Patterns mirror CkInteractionGym and CkInventoryGym per
// CkGym_CreationSpecification.txt §12.
//============================================================================

namespace goap_gym_util
{
	FGameplayTag T(FName InName) { return GameplayTags::ResolveGameplayTag(InName); }

	FString StatusString(ECk_GoapPlanStatus InStatus)
	{
		if (InStatus == ECk_GoapPlanStatus::Idle)                 { return "IDLE"; }
		if (InStatus == ECk_GoapPlanStatus::Planning)             { return "PLANNING"; }
		if (InStatus == ECk_GoapPlanStatus::PlanFound)            { return "PLAN FOUND"; }
		if (InStatus == ECk_GoapPlanStatus::PlanFailed)           { return "PLAN FAILED"; }
		if (InStatus == ECk_GoapPlanStatus::CostThresholdReached) { return "COST THRESHOLD"; }
		return "UNKNOWN";
	}

	FString FormatPlan(FCk_Handle_Goap InGoap)
	{
		auto Status = utils_goap::Get_PlanStatus(InGoap);

		if (Status == ECk_GoapPlanStatus::PlanFailed)  { return "Plan: <failed>\n"; }
		if (Status == ECk_GoapPlanStatus::Planning)    { return "Plan: ...\n"; }
		if (Status == ECk_GoapPlanStatus::Idle)        { return "Plan: <idle>\n"; }

		auto Plan = utils_goap::Get_Plan(InGoap);
		auto Cost = utils_goap::Get_PlanCost(InGoap);

		if (Plan.Num() == 0) { return f"Plan: <goal already satisfied> cost={Cost}\n"; }

		auto Text = f"Plan: {Plan.Num()} step(s), cost={Cost}\n";
		for (int32 i = 0; i < Plan.Num(); i++)
		{
			auto ActionName = Plan[i].Get().GetName();
			Text = f"{Text}  {i + 1}. {ActionName}\n";
		}
		return Text;
	}
}

//============================================================================
// STATION 1 — OPEN DOOR (trivial: 2 actions, 1 goal)
//============================================================================

class UCk_EntityScript_GoapGym_Door : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FCk_Handle_Timer AutoTimer;

	int32 AutoStep = 0;
	bool AutoRunning = true;
	int32 PlanCount = 0;

	FCkGym_AutoConfig AutoConfig;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_Door");

		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.Door"));
		GoapEntity.AddAction(UCk_GoapTest_Action_FindKey);
		GoapEntity.AddAction(UCk_GoapTest_Action_UnlockDoor);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_OpenDoor);

		ResetWorldState(false, false);
		RequestPlan();


		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.0f));

		AutoConfig.TotalSteps = 4;
		AutoConfig.Description = "Trivial 2-action chain. Replans the OpenDoor goal under varying inputs.";
		AutoConfig.GlobalAutoCommand = "Ck_GymGoap_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymGoap_AutoDoor";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Start empty: FindKey -> UnlockDoor", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Already unlocked: 0 steps", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Key in hand: just UnlockDoor", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Reset and loop", 3, 3));
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Door_Replan");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Door_GiveKey");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Door_LoseKey");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Door_PreUnlock");

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Door_Replan,     FCk_Delegate_Messaging_OnBroadcast(this, n"OnReplan"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Door_GiveKey,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnGiveKey"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Door_LoseKey,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnLoseKey"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Door_PreUnlock,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnPreUnlock"));


		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void ResetWorldState(bool InHasKey, bool InUnlocked)
	{
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Door.HasKey"), InHasKey);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Door.Unlocked"), InUnlocked);
	}

	private void RequestPlan()
	{
		GoapEntity.Request_Plan();
		PlanCount++;
	}

	UFUNCTION() private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto Step = AutoStep % AutoConfig.TotalSteps;
		if      (Step == 0) { ResetWorldState(false, false); }
		else if (Step == 1) { ResetWorldState(false, true); }
		else if (Step == 2) { ResetWorldState(true,  false); }
		else if (Step == 3) { ResetWorldState(false, false); }
		RequestPlan();
		AutoStep++;
	}

	UFUNCTION() private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning); }
	UFUNCTION() private void OnReplan   (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); RequestPlan(); }
	UFUNCTION() private void OnGiveKey  (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Door.HasKey"),   true);  RequestPlan(); }
	UFUNCTION() private void OnLoseKey  (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Door.HasKey"),   false); RequestPlan(); }
	UFUNCTION() private void OnPreUnlock(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Door.Unlocked"), true);  RequestPlan(); }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto SelfEntity = ck::ToEntity(this);
		auto Status = utils_goap::Get_PlanStatus(GoapEntity);
		auto HasKey    = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Door.HasKey"));
		auto Unlocked  = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Door.Unlocked"));

		auto Text = gym_auto::FormatHeader(AutoConfig, AutoRunning);
		Text = f"{Text}===== World State =====\n";
		Text = f"{Text}HasKey: {HasKey}   Unlocked: {Unlocked}\n\n";
		Text = f"{Text}===== Planner =====\n";
		Text = f"{Text}Status: {goap_gym_util::StatusString(Status)}   Plan #{PlanCount}\n";
		Text = f"{Text}{goap_gym_util::FormatPlan(GoapEntity)}\n";
		Text = Text + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		auto Mode = AutoRunning ? "[AUTO]" : "[MANUAL]";
		CkGym_Common::Update_StationDisplay(SelfEntity, f"OPEN DOOR {Mode}", Text, "");
	}
}

//============================================================================
// STATION 2 — MAKE TEA (strict linear 4-step chain)
//============================================================================

class UCk_EntityScript_GoapGym_Tea : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FCk_Handle_Timer AutoTimer;

	int32 AutoStep = 0;
	bool AutoRunning = true;
	int32 PlanCount = 0;

	FCkGym_AutoConfig AutoConfig;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_Tea");

		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.Tea"));
		GoapEntity.AddAction(UCk_GoapTest_Action_FillKettle);
		GoapEntity.AddAction(UCk_GoapTest_Action_BoilKettle);
		GoapEntity.AddAction(UCk_GoapTest_Action_SteepTea);
		GoapEntity.AddAction(UCk_GoapTest_Action_PourTea);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_ServeTea);

		SetWS(false, false, false, false);
		RequestPlan();


		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.0f));

		AutoConfig.TotalSteps = 5;
		AutoConfig.Description = "Linear 4-step chain. Replans from progressively warmer starts.";
		AutoConfig.GlobalAutoCommand = "Ck_GymGoap_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymGoap_AutoTea";
		AutoConfig.Steps.Add(FCkGym_AutoStep("From scratch: 4 steps (Fill->Boil->Steep->Pour)", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Water in kettle: 3 steps", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Water hot: 2 steps", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Tea steeped: 1 step", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Reset and loop", 4, 4));
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Tea_Replan");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Tea_FillWater");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Tea_BoilWater");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Tea_SteepTea");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Tea_ResetAll");

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Tea_Replan,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnReplan"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Tea_FillWater, FCk_Delegate_Messaging_OnBroadcast(this, n"OnFillWater"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Tea_BoilWater, FCk_Delegate_Messaging_OnBroadcast(this, n"OnBoilWater"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Tea_SteepTea,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnSteepTea"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Tea_ResetAll,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAll"));


		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void SetWS(bool InHasWater, bool InWaterHot, bool InTeaSteeped, bool InTeaReady)
	{
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.HasWater"),   InHasWater);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.WaterHot"),   InWaterHot);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.TeaSteeped"), InTeaSteeped);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.TeaReady"),   InTeaReady);
	}

	private void RequestPlan() { GoapEntity.Request_Plan(); PlanCount++; }

	UFUNCTION() private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto Step = AutoStep % AutoConfig.TotalSteps;
		if      (Step == 0) { SetWS(false, false, false, false); }
		else if (Step == 1) { SetWS(true,  false, false, false); }
		else if (Step == 2) { SetWS(true,  true,  false, false); }
		else if (Step == 3) { SetWS(true,  true,  true,  false); }
		else if (Step == 4) { SetWS(false, false, false, false); }
		RequestPlan();
		AutoStep++;
	}

	UFUNCTION() private void OnAutoSet (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning); }
	UFUNCTION() private void OnReplan  (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); RequestPlan(); }
	UFUNCTION() private void OnFillWater(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.HasWater"),   true); RequestPlan(); }
	UFUNCTION() private void OnBoilWater(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.WaterHot"),   true); RequestPlan(); }
	UFUNCTION() private void OnSteepTea (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.TeaSteeped"), true); RequestPlan(); }
	UFUNCTION() private void OnResetAll (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); SetWS(false, false, false, false); RequestPlan(); }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto SelfEntity = ck::ToEntity(this);
		auto Status = utils_goap::Get_PlanStatus(GoapEntity);
		auto HasWater   = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.HasWater"));
		auto WaterHot   = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.WaterHot"));
		auto TeaSteeped = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.TeaSteeped"));
		auto TeaReady   = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Tea.TeaReady"));

		auto Text = gym_auto::FormatHeader(AutoConfig, AutoRunning);
		Text = f"{Text}===== World State =====\n";
		Text = f"{Text}HasWater: {HasWater}   WaterHot: {WaterHot}\n";
		Text = f"{Text}TeaSteeped: {TeaSteeped}   TeaReady: {TeaReady}\n\n";
		Text = f"{Text}===== Planner =====\n";
		Text = f"{Text}Status: {goap_gym_util::StatusString(Status)}   Plan #{PlanCount}\n";
		Text = f"{Text}{goap_gym_util::FormatPlan(GoapEntity)}\n";
		Text = Text + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		auto Mode = AutoRunning ? "[AUTO]" : "[MANUAL]";
		CkGym_Common::Update_StationDisplay(SelfEntity, f"MAKE TEA {Mode}", Text, "");
	}
}

//============================================================================
// STATION 3 — COMBAT (ranged vs melee + dynamic cost flipping)
//============================================================================

class UCk_EntityScript_GoapGym_Combat : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FCk_Handle_Timer AutoTimer;

	int32 AutoStep = 0;
	bool AutoRunning = true;
	int32 PlanCount = 0;
	float CurrentMeleeCost = 6.0f;

	FCkGym_AutoConfig AutoConfig;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_Combat");

		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.Combat"));
		GoapEntity.AddAction(UCk_GoapTest_Action_PickUpWeapon);
		GoapEntity.AddAction(UCk_GoapTest_Action_LoadAmmo);
		GoapEntity.AddAction(UCk_GoapTest_Action_RangedAttack);
		GoapEntity.AddAction(UCk_GoapTest_Action_MeleeAttack);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_KillEnemy);

		ResetScenario();
		RequestPlan();


		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.5f));

		AutoConfig.TotalSteps = 4;
		AutoConfig.Description = "Ranged vs Melee cost comparison. Step 2 flips melee cost, planner switches path.";
		AutoConfig.GlobalAutoCommand = "Ck_GymGoap_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymGoap_AutoCombat";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Default costs: Ranged wins (2+1+4=7 < 2+6=8)", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Melee cost -> 3.0: Melee wins (2+3=5)", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Restore melee cost: Ranged wins again", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Start with weapon: skip PickUpWeapon", 3, 3));
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Combat_Replan");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Combat_MakeMeleeCheap");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Combat_MakeMeleeExpensive");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Combat_RemoveWeapon");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Combat_GiveWeapon");

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Combat_Replan,               FCk_Delegate_Messaging_OnBroadcast(this, n"OnReplan"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Combat_MakeMeleeCheap,       FCk_Delegate_Messaging_OnBroadcast(this, n"OnMeleeCheap"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Combat_MakeMeleeExpensive,   FCk_Delegate_Messaging_OnBroadcast(this, n"OnMeleeExpensive"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Combat_RemoveWeapon,         FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveWeapon"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Combat_GiveWeapon,           FCk_Delegate_Messaging_OnBroadcast(this, n"OnGiveWeapon"));


		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void ResetScenario()
	{
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.HasWeapon"),    false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.HasAmmo"),      false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.EnemyInRange"), true);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.EnemyAlive"),   true);
	}

	private void SetMeleeCost(float InCost)
	{
		CurrentMeleeCost = InCost;
		GoapEntity.Set_ActionCost(UCk_GoapTest_Action_MeleeAttack, InCost);
	}

	private void RequestPlan() { GoapEntity.Request_Plan(); PlanCount++; }

	UFUNCTION() private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto Step = AutoStep % AutoConfig.TotalSteps;
		if      (Step == 0) { ResetScenario(); SetMeleeCost(6.0f); }
		else if (Step == 1) { ResetScenario(); SetMeleeCost(3.0f); }
		else if (Step == 2) { ResetScenario(); SetMeleeCost(6.0f); }
		else if (Step == 3) { ResetScenario(); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.HasWeapon"), true); SetMeleeCost(6.0f); }
		RequestPlan();
		AutoStep++;
	}

	UFUNCTION() private void OnAutoSet        (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning); }
	UFUNCTION() private void OnReplan         (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); RequestPlan(); }
	UFUNCTION() private void OnMeleeCheap     (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); SetMeleeCost(3.0f); RequestPlan(); }
	UFUNCTION() private void OnMeleeExpensive (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); SetMeleeCost(6.0f); RequestPlan(); }
	UFUNCTION() private void OnRemoveWeapon   (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.HasWeapon"), false); RequestPlan(); }
	UFUNCTION() private void OnGiveWeapon     (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.HasWeapon"), true);  RequestPlan(); }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto SelfEntity = ck::ToEntity(this);
		auto Status = utils_goap::Get_PlanStatus(GoapEntity);
		auto HasWeapon    = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.HasWeapon"));
		auto HasAmmo      = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.HasAmmo"));
		auto EnemyInRange = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.EnemyInRange"));
		auto EnemyAlive   = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.EnemyAlive"));

		auto Text = gym_auto::FormatHeader(AutoConfig, AutoRunning);
		Text = f"{Text}===== World State =====\n";
		Text = f"{Text}HasWeapon: {HasWeapon}   HasAmmo: {HasAmmo}\n";
		Text = f"{Text}EnemyInRange: {EnemyInRange}   EnemyAlive: {EnemyAlive}\n";
		Text = f"{Text}Melee cost: {CurrentMeleeCost} (Ranged: 4.0)\n\n";
		Text = f"{Text}===== Planner =====\n";
		Text = f"{Text}Status: {goap_gym_util::StatusString(Status)}   Plan #{PlanCount}\n";
		Text = f"{Text}{goap_gym_util::FormatPlan(GoapEntity)}\n";
		Text = Text + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		auto Mode = AutoRunning ? "[AUTO]" : "[MANUAL]";
		CkGym_Common::Update_StationDisplay(SelfEntity, f"COMBAT: RANGED vs MELEE {Mode}", Text, "");
	}
}

//============================================================================
// STATION 4 — PRIORITIES (3 goals, highest-priority achievable wins)
//============================================================================

class UCk_EntityScript_GoapGym_Priorities : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FCk_Handle_Timer AutoTimer;

	int32 AutoStep = 0;
	bool AutoRunning = true;
	int32 PlanCount = 0;

	FCkGym_AutoConfig AutoConfig;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_Priorities");

		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.Priorities"));
		GoapEntity.AddAction(UCk_GoapTest_Action_Hide);
		GoapEntity.AddAction(UCk_GoapTest_Action_Suppress);
		GoapEntity.AddAction(UCk_GoapTest_Action_Forage);
		GoapEntity.AddAction(UCk_GoapTest_Action_Eat);
		GoapEntity.AddAction(UCk_GoapTest_Action_Scout);
		GoapEntity.AddAction(UCk_GoapTest_Action_Neutralize);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_SurviveFire);   // priority 10
		GoapEntity.AddGoal(UCk_GoapTest_Goal_Feed);          // priority 5
		GoapEntity.AddGoal(UCk_GoapTest_Goal_Neutralize);    // priority 3

		ResetWS();
		RequestPlan();


		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.5f));

		AutoConfig.TotalSteps = 4;
		AutoConfig.Description = "3 goals with different priorities. Planner picks highest-priority achievable goal.";
		AutoConfig.GlobalAutoCommand = "Ck_GymGoap_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymGoap_AutoPriorities";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Calm: only Neutralize reachable (pri 3)", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Hungry: Feed wins (pri 5)", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Under fire: Survive wins (pri 10)", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Reset all", 3, 3));
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Priorities_Replan");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Priorities_TakeFire");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Priorities_GetHungry");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Priorities_SpotEnemy");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Priorities_ResetAll");

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Priorities_Replan,     FCk_Delegate_Messaging_OnBroadcast(this, n"OnReplan"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Priorities_TakeFire,   FCk_Delegate_Messaging_OnBroadcast(this, n"OnTakeFire"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Priorities_GetHungry,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnGetHungry"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Priorities_SpotEnemy,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnSpotEnemy"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Priorities_ResetAll,   FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAll"));


		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void ResetWS()
	{
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.UnderFire"),    false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.InCover"),      false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.IsHungry"),     false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.HasFood"),      false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.EnemySpotted"), false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.EnemyDown"),    false);
	}

	private void RequestPlan() { GoapEntity.Request_Plan(); PlanCount++; }

	UFUNCTION() private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto Step = AutoStep % AutoConfig.TotalSteps;
		ResetWS();
		if      (Step == 0) { /* calm - Neutralize is the only achievable goal */ }
		else if (Step == 1) { GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.IsHungry"), true); }
		else if (Step == 2) { GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.UnderFire"), true); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.IsHungry"), true); }
		else if (Step == 3) { /* reset only */ }
		RequestPlan();
		AutoStep++;
	}

	UFUNCTION() private void OnAutoSet   (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning); }
	UFUNCTION() private void OnReplan    (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); RequestPlan(); }
	UFUNCTION() private void OnTakeFire  (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.UnderFire"), true);     RequestPlan(); }
	UFUNCTION() private void OnGetHungry (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.IsHungry"), true);      RequestPlan(); }
	UFUNCTION() private void OnSpotEnemy (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.EnemySpotted"), true);  RequestPlan(); }
	UFUNCTION() private void OnResetAll  (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); ResetWS(); RequestPlan(); }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto SelfEntity = ck::ToEntity(this);
		auto Status = utils_goap::Get_PlanStatus(GoapEntity);

		auto UnderFire    = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.UnderFire"));
		auto IsHungry     = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.IsHungry"));
		auto EnemySpotted = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Pri.EnemySpotted"));

		auto Text = gym_auto::FormatHeader(AutoConfig, AutoRunning);
		Text = f"{Text}===== Goals (priority) =====\n";
		Text = f"{Text}  Survive (10): UnderFire = false\n";
		Text = f"{Text}  Feed     (5): IsHungry = false\n";
		Text = f"{Text}  Neutralize (3): EnemyDown = true\n\n";
		Text = f"{Text}===== World State =====\n";
		Text = f"{Text}UnderFire: {UnderFire}   IsHungry: {IsHungry}   EnemySpotted: {EnemySpotted}\n\n";
		Text = f"{Text}===== Planner =====\n";
		Text = f"{Text}Status: {goap_gym_util::StatusString(Status)}   Plan #{PlanCount}\n";
		Text = f"{Text}{goap_gym_util::FormatPlan(GoapEntity)}\n";
		Text = Text + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		auto Mode = AutoRunning ? "[AUTO]" : "[MANUAL]";
		CkGym_Common::Update_StationDisplay(SelfEntity, f"MULTI-GOAL PRIORITIES {Mode}", Text, "");
	}
}

//============================================================================
// STATION 5 — NO PLAN POSSIBLE (demonstrates PlanFailed)
//============================================================================

class UCk_EntityScript_GoapGym_NoPlan : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FCk_Handle_Timer AutoTimer;

	int32 AutoStep = 0;
	bool AutoRunning = true;
	int32 PlanCount = 0;

	FCkGym_AutoConfig AutoConfig;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_NoPlan");

		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.NoPlan"));
		// Intentionally register actions that CANNOT reach KillEnemy
		GoapEntity.AddAction(UCk_GoapTest_Action_Scout);
		GoapEntity.AddAction(UCk_GoapTest_Action_Hide);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_KillEnemy);

		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.EnemyAlive"), true);
		RequestPlan();


		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(3.0f));

		AutoConfig.TotalSteps = 1;
		AutoConfig.Description = "Actions registered cannot reach the goal. Planner returns PlanFailed.";
		AutoConfig.GlobalAutoCommand = "Ck_GymGoap_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymGoap_AutoNoPlan";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Replan -> expected PlanFailed", 0, 0));
		AutoConfig.ManualCommands.Add("Ck_GymGoap_NoPlan_Replan");

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_NoPlan_Replan, FCk_Delegate_Messaging_OnBroadcast(this, n"OnReplan"));


		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void RequestPlan() { GoapEntity.Request_Plan(); PlanCount++; }

	UFUNCTION() private void AutoTick (FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { if (ck::Is_NOT_Valid(GoapEntity)) { return; } RequestPlan(); AutoStep++; }
	UFUNCTION() private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning); }
	UFUNCTION() private void OnReplan (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); RequestPlan(); }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto SelfEntity = ck::ToEntity(this);
		auto Status = utils_goap::Get_PlanStatus(GoapEntity);

		auto Text = gym_auto::FormatHeader(AutoConfig, AutoRunning);
		Text = f"{Text}===== Registered =====\n";
		Text = f"{Text}Actions: Scout, Hide\n";
		Text = f"{Text}Goal: KillEnemy (requires EnemyAlive=false)\n";
		Text = f"{Text}No action has EnemyAlive=false as an effect.\n\n";
		Text = f"{Text}===== Planner =====\n";
		Text = f"{Text}Status: {goap_gym_util::StatusString(Status)}   Plan #{PlanCount}\n";
		Text = f"{Text}{goap_gym_util::FormatPlan(GoapEntity)}\n";
		Text = Text + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		auto Mode = AutoRunning ? "[AUTO]" : "[MANUAL]";
		CkGym_Common::Update_StationDisplay(SelfEntity, f"NO PLAN POSSIBLE {Mode}", Text, "");
	}
}

//============================================================================
// STATION 6 — CIRCULAR DEPENDENCY (exercises framework cycle detector)
//============================================================================
// Intentional bad graph: ChargeDevice needs HasBattery, ChargeBattery needs
// HasPower. Classic chicken-and-egg — the GOAP framework's setup-time SCC
// detection flags this as a dependency cycle, and the plan-time reachability
// check populates UnreachableGoalConditions. The debugger surfaces both.

class UCk_EntityScript_GoapGym_CircularDep : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FCk_Handle_Timer AutoTimer;

	int32 AutoStep = 0;
	bool AutoRunning = true;
	int32 PlanCount = 0;
	bool BatterySeeded = false;

	FCkGym_AutoConfig AutoConfig;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_CircularDep");

		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.CircularDep"));
		GoapEntity.AddAction(UCk_GoapTest_Action_ChargeDevice);
		GoapEntity.AddAction(UCk_GoapTest_Action_ChargeBattery);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_HasPower);

		ResetWS();
		RequestPlan();


		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.5f));

		AutoConfig.TotalSteps = 3;
		AutoConfig.Description = "Intentional chicken-and-egg graph. Framework flags the cycle + goal unreachability. Seeding HasBattery breaks the deadlock.";
		AutoConfig.GlobalAutoCommand = "Ck_GymGoap_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymGoap_AutoCircularDep";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Empty start: PlanFailed + diagnostic banner", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Seed HasBattery -> plan succeeds (1 step)", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Clear seed -> PlanFailed again", 2, 2));
		AutoConfig.ManualCommands.Add("Ck_GymGoap_CircularDep_Replan");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_CircularDep_SeedBattery");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_CircularDep_ClearSeed");

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_CircularDep_Replan,       FCk_Delegate_Messaging_OnBroadcast(this, n"OnReplan"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_CircularDep_SeedBattery,  FCk_Delegate_Messaging_OnBroadcast(this, n"OnSeedBattery"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_CircularDep_ClearSeed,    FCk_Delegate_Messaging_OnBroadcast(this, n"OnClearSeed"));


		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void ResetWS()
	{
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Cycle.HasPower"),   false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Cycle.HasBattery"), BatterySeeded);
	}

	private void RequestPlan() { GoapEntity.Request_Plan(); PlanCount++; }

	UFUNCTION() private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto Step = AutoStep % AutoConfig.TotalSteps;
		if      (Step == 0) { BatterySeeded = false; ResetWS(); }
		else if (Step == 1) { BatterySeeded = true;  ResetWS(); }
		else if (Step == 2) { BatterySeeded = false; ResetWS(); }
		RequestPlan();
		AutoStep++;
	}

	UFUNCTION() private void OnAutoSet    (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning); }
	UFUNCTION() private void OnReplan     (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); RequestPlan(); }
	UFUNCTION() private void OnSeedBattery(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); BatterySeeded = true;  ResetWS(); RequestPlan(); }
	UFUNCTION() private void OnClearSeed  (FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload) { gym_auto::StopAuto(AutoTimer, AutoRunning); BatterySeeded = false; ResetWS(); RequestPlan(); }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		auto SelfEntity = ck::ToEntity(this);
		auto Status = utils_goap::Get_PlanStatus(GoapEntity);
		auto HasPower   = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Cycle.HasPower"));
		auto HasBattery = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.Cycle.HasBattery"));

		auto Text = gym_auto::FormatHeader(AutoConfig, AutoRunning);
		Text = f"{Text}===== Graph =====\n";
		Text = f"{Text}  ChargeDevice:  (HasBattery) -> HasPower\n";
		Text = f"{Text}  ChargeBattery: (HasPower)   -> HasBattery\n\n";
		Text = f"{Text}===== World State =====\n";
		Text = f"{Text}HasPower: {HasPower}   HasBattery: {HasBattery}   Seeded: {BatterySeeded}\n\n";
		Text = f"{Text}===== Planner =====\n";
		Text = f"{Text}Goal: HasPower=true   Status: {goap_gym_util::StatusString(Status)}   Plan #{PlanCount}\n";
		Text = f"{Text}{goap_gym_util::FormatPlan(GoapEntity)}\n";
		Text = Text + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		auto Mode = AutoRunning ? "[AUTO]" : "[MANUAL]";
		CkGym_Common::Update_StationDisplay(SelfEntity, f"CIRCULAR DEPENDENCY {Mode}", Text, "");
	}
}
