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

class UCk_EntityScript_GoapGym_Door : UCk_EntityScript_UE
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
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_Door");

		GoapEntity = utils_goap::Add(InHandle);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.Door"));
		GoapEntity.AddAction(UCk_GoapTest_Action_FindKey);
		GoapEntity.AddAction(UCk_GoapTest_Action_UnlockDoor);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_OpenDoor);

		ResetWorldState(false, false);
		RequestPlan();

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

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

class UCk_EntityScript_GoapGym_Tea : UCk_EntityScript_UE
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
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_Tea");

		GoapEntity = utils_goap::Add(InHandle);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.Tea"));
		GoapEntity.AddAction(UCk_GoapTest_Action_FillKettle);
		GoapEntity.AddAction(UCk_GoapTest_Action_BoilKettle);
		GoapEntity.AddAction(UCk_GoapTest_Action_SteepTea);
		GoapEntity.AddAction(UCk_GoapTest_Action_PourTea);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_ServeTea);

		SetWS(false, false, false, false);
		RequestPlan();

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

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

class UCk_EntityScript_GoapGym_Combat : UCk_EntityScript_UE
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
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_Combat");

		GoapEntity = utils_goap::Add(InHandle);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.Combat"));
		GoapEntity.AddAction(UCk_GoapTest_Action_PickUpWeapon);
		GoapEntity.AddAction(UCk_GoapTest_Action_LoadAmmo);
		GoapEntity.AddAction(UCk_GoapTest_Action_RangedAttack);
		GoapEntity.AddAction(UCk_GoapTest_Action_MeleeAttack);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_KillEnemy);

		ResetScenario();
		RequestPlan();

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

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

class UCk_EntityScript_GoapGym_Priorities : UCk_EntityScript_UE
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
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_Priorities");

		GoapEntity = utils_goap::Add(InHandle);
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

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

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

class UCk_EntityScript_GoapGym_NoPlan : UCk_EntityScript_UE
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
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_NoPlan");

		GoapEntity = utils_goap::Add(InHandle);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.NoPlan"));
		// Intentionally register actions that CANNOT reach KillEnemy
		GoapEntity.AddAction(UCk_GoapTest_Action_Scout);
		GoapEntity.AddAction(UCk_GoapTest_Action_Hide);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_KillEnemy);

		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.Combat.EnemyAlive"), true);
		RequestPlan();

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(3.0f));

		AutoConfig.TotalSteps = 1;
		AutoConfig.Description = "Actions registered cannot reach the goal. Planner returns PlanFailed.";
		AutoConfig.GlobalAutoCommand = "Ck_GymGoap_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymGoap_AutoNoPlan";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Replan -> expected PlanFailed", 0, 0));
		AutoConfig.ManualCommands.Add("Ck_GymGoap_NoPlan_Replan");

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_NoPlan_Replan, FCk_Delegate_Messaging_OnBroadcast(this, n"OnReplan"));

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

class UCk_EntityScript_GoapGym_CircularDep : UCk_EntityScript_UE
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
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_CircularDep");

		GoapEntity = utils_goap::Add(InHandle);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.CircularDep"));
		GoapEntity.AddAction(UCk_GoapTest_Action_ChargeDevice);
		GoapEntity.AddAction(UCk_GoapTest_Action_ChargeBattery);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_HasPower);

		ResetWS();
		RequestPlan();

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

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

//============================================================================
// STATION 7 — AGE OF EMPIRES (single-villager time-sliced execution)
//============================================================================
//
// Executes the GOAP plan over time, one action at a time. Each action takes
// Cost * SecondsPerCost seconds to "execute"; when it completes, its effects
// are applied to the world state and the next action begins. When the plan
// finishes, the next-priority goal is selected automatically (framework
// picks the highest-priority unsatisfied goal). When all goals are
// satisfied (planner returns PlanFailed because nothing to pursue), the
// world resets and the cycle starts over.
//
// This simulates a real executor layer — GOAP produces the recipe, the
// station simulates a unit carrying it out step by step.

enum ECk_GoapGymEmpire_Phase
{
	Idle,              // No plan, request one next tick
	AwaitingPlan,      // Plan was requested, waiting for PlanFound / PlanFailed
	Running,           // Executing CurrentPlan[CurrentActionIndex]
	BetweenPlans,      // Plan finished, brief pause before next
	AllGoalsComplete   // All goals satisfied, brief pause before world reset
}

class UCk_EntityScript_GoapGym_Empire : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FCk_Handle_Timer AutoTimer;

	// Visual arena is drawn in immediate-mode each DisplayTick using
	// utils_pmg_basic_shapes::DrawFilled*. PMG's Create_*/Add_* flavors run
	// their setup processor only once and never re-sync the mesh to a moving
	// Transform, so persistent shapes can't follow the villager. Redrawing
	// every frame at the current position is cheap and keeps the code free
	// of entity-handle bookkeeping.
	FVector VillagerPosition = FVector::ZeroVector;

	// Execution state
	TArray<TSubclassOf<UCk_GoapAction_EntityScript>> CurrentPlan;
	int32 CurrentActionIndex = -1;
	float CurrentActionElapsed = 0.0f;
	float CurrentActionDuration = 0.0f;
	float CurrentActionCost = 0.0f;
	FString CurrentActionName = "";
	ECk_GoapGymEmpire_Phase Phase = ECk_GoapGymEmpire_Phase::Idle;
	float PhasePauseElapsed = 0.0f;

	// Villager movement state. Set when a new action begins; lerped each tick.
	FVector VillagerStartLocation = FVector::ZeroVector;
	FVector VillagerTargetLocation = FVector::ZeroVector;

	// Tuning constants
	const float SecondsPerCost = 0.3f;   // how many real seconds per cost unit
	const float BetweenPlansDelay = 1.0f;
	const float AllCompleteDelay = 2.5f;

	// Layout — offsets from the station's InitialTransform, in world units.
	// The arena sits on a ~6m x 4m footprint centered on the station.
	const FVector OffsetTownCenter = FVector(   0.0f,    0.0f, 0.0f);
	const FVector OffsetForest     = FVector(-300.0f,  200.0f, 0.0f);
	const FVector OffsetBerries    = FVector( 300.0f,  200.0f, 0.0f);
	const FVector OffsetGold       = FVector(-300.0f, -200.0f, 0.0f);
	const FVector OffsetStone      = FVector( 300.0f, -200.0f, 0.0f);
	const FVector OffsetLumberCamp = FVector(-200.0f,  180.0f, 0.0f);
	const FVector OffsetMill       = FVector( 200.0f,  180.0f, 0.0f);
	const FVector OffsetMiningCamp = FVector(   0.0f, -180.0f, 0.0f);
	const FVector OffsetBarracks   = FVector(   0.0f,  140.0f, 0.0f);

	// Distance-based cost weighting. CostPerDistanceUnit × distance_to_target
	// is added to every action's base cost before planning, so the planner
	// prefers the action whose target is closest to the villager's current
	// position. Movement meaningfully shapes the plan.
	const float CostPerDistanceUnit = 0.01f;  // 1 cost unit per 100cm of travel

	// Tracking
	bool AutoRunning = true;     // gym_auto pause/resume
	int32 PlanCount = 0;
	FString LastGoalName = "(none)";

	FCkGym_AutoConfig AutoConfig;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_GoapGym_Empire");

		GoapEntity = utils_goap::Add(InHandle);
		utils_gameplay_label::Add(GoapEntity, goap_gym_util::T(n"Gym.Goap.Empire"));

		// Single-villager economy. Two variants of each gatherable exist
		// so the planner can amortize via camps when the goal is heavier.
		GoapEntity.AddAction(UCk_GoapTest_Action_GatherWood);
		GoapEntity.AddAction(UCk_GoapTest_Action_GatherWoodFromCamp);
		GoapEntity.AddAction(UCk_GoapTest_Action_GatherFood);
		GoapEntity.AddAction(UCk_GoapTest_Action_GatherFoodFromMill);
		GoapEntity.AddAction(UCk_GoapTest_Action_GatherGold);
		GoapEntity.AddAction(UCk_GoapTest_Action_GatherStone);
		GoapEntity.AddAction(UCk_GoapTest_Action_BuildLumberCamp);
		GoapEntity.AddAction(UCk_GoapTest_Action_BuildMill);
		GoapEntity.AddAction(UCk_GoapTest_Action_BuildMiningCamp);
		GoapEntity.AddAction(UCk_GoapTest_Action_BuildBarracks);
		GoapEntity.AddAction(UCk_GoapTest_Action_ResearchFeudalAge);

		GoapEntity.AddGoal(UCk_GoapTest_Goal_GatherResources);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_BuildMilitary);
		GoapEntity.AddGoal(UCk_GoapTest_Goal_ReachFeudalAge);

		VillagerPosition = WorldPosFromOffset(OffsetTownCenter);
		ResetWorld();
		UpdateActionCostsByDistance();

		// DisplayTimer ticks every frame (0s interval). It drives BOTH the
		// station text render AND the plan-execution state machine.
		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// The AutoTimer is unused for driving steps here (execution runs on
		// DisplayTick), but we keep it so gym_auto's pause/resume still works.
		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.0f));

		AutoConfig.TotalSteps = 1;
		AutoConfig.Description = "Single-villager AoE economy. Plan executes action-by-action; world state advances live; goals cycle by priority.";
		AutoConfig.GlobalAutoCommand = "Ck_GymGoap_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymGoap_AutoEmpire";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Execute plan -> next goal -> reset", 0, 0));
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Empire_PlanGatherResources");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Empire_PlanBuildMilitary");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Empire_PlanFeudalAge");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Empire_ApplyPlan");
		AutoConfig.ManualCommands.Add("Ck_GymGoap_Empire_ResetWorld");

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Empire_PlanGatherResources, FCk_Delegate_Messaging_OnBroadcast(this, n"OnPlanGather"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Empire_PlanBuildMilitary,   FCk_Delegate_Messaging_OnBroadcast(this, n"OnPlanMilitary"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Empire_PlanFeudalAge,       FCk_Delegate_Messaging_OnBroadcast(this, n"OnPlanFeudal"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Empire_ApplyPlan,           FCk_Delegate_Messaging_OnBroadcast(this, n"OnApplyPlan"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_GoapGym_Empire_ResetWorld,          FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetWorld"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	private void ResetWorld()
	{
		// Start-of-game world: one villager, one town center, no resources,
		// no buildings, no research progress. Everything else flips during
		// plan execution.
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasTownCenter"),    true);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasVillager"),      true);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasWood"),          false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasFood"),          false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasGold"),          false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasStone"),         false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasLumberCamp"),    false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasMill"),          false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasMiningCamp"),    false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasBarracks"),      false);
		GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.ReachedFeudalAge"), false);

		// Visual reset: send villager home, remove building shapes.
		// Send villager home visually (positional reset).
		VillagerPosition = WorldPosFromOffset(OffsetTownCenter);
		VillagerStartLocation = VillagerPosition;
		VillagerTargetLocation = VillagerPosition;
	}

	// --------------------------------------------------------------------------
	// VISUAL ARENA (immediate-mode — redrawn every frame by DrawArena)
	// --------------------------------------------------------------------------

	private FVector StationOrigin()
	{
		return InitialTransform.GetLocation();
	}

	private FVector WorldPosFromOffset(FVector InOffset)
	{
		return StationOrigin() + InOffset;
	}

	private FVector GetVillagerLocation()
	{
		return VillagerPosition;
	}

	// Redraw the whole arena this frame using DrawFilled*. Duration=0 means
	// "visible this frame only" — next DisplayTick re-issues the draws.
	private void DrawArena()
	{
		const auto TcColor       = FLinearColor(0.95f, 0.85f, 0.30f, 0.65f);
		const auto ForestColor   = FLinearColor(0.15f, 0.55f, 0.15f, 0.75f);
		const auto BerryColor    = FLinearColor(0.80f, 0.20f, 0.25f, 0.75f);
		const auto GoldColor     = FLinearColor(0.95f, 0.75f, 0.10f, 0.75f);
		const auto StoneColor    = FLinearColor(0.55f, 0.55f, 0.60f, 0.75f);
		const auto VillColor     = FLinearColor(0.20f, 0.55f, 0.95f, 0.95f);
		const auto CampColor     = FLinearColor(0.65f, 0.45f, 0.25f, 0.85f);
		const auto MillColor     = FLinearColor(0.85f, 0.65f, 0.40f, 0.85f);
		const auto BarracksColor = FLinearColor(0.40f, 0.30f, 0.25f, 0.90f);

		// Resource / landmark landmarks (always present)
		utils_pmg_basic_shapes::DrawFilledBox(      WorldPosFromOffset(OffsetTownCenter), FVector(60.0f, 60.0f, 80.0f), TcColor,     true, 2.0f, ECk_Plane_Axis::XY, 0.0f);
		utils_pmg_basic_shapes::DrawFilledPyramid(  WorldPosFromOffset(OffsetForest),     80.0f, 120.0f,                ForestColor, true, 2.0f, ECk_Plane_Axis::XY, 0.0f);
		utils_pmg_basic_shapes::DrawFilledSphere(   WorldPosFromOffset(OffsetBerries),    45.0f, 16, 16,                BerryColor,  true, 2.0f, ECk_Plane_Axis::XY, 0.0f);
		utils_pmg_basic_shapes::DrawFilledCylinder( WorldPosFromOffset(OffsetGold),       45.0f, 60.0f, 16,             GoldColor,   true, 2.0f, ECk_Plane_Axis::XY, 0.0f);
		utils_pmg_basic_shapes::DrawFilledBox(      WorldPosFromOffset(OffsetStone),      FVector(70.0f, 70.0f, 40.0f), StoneColor,  true, 2.0f, ECk_Plane_Axis::XY, 0.0f);

		// Villager at current interpolated position
		utils_pmg_basic_shapes::DrawFilledCapsule(  VillagerPosition, 30.0f, 50.0f, 16, 8, VillColor,   true, 3.0f, ECk_Plane_Axis::XY, 0.0f);

		// Buildings appear only when the corresponding world-state fact is true.
		if (GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasLumberCamp")))
		{ utils_pmg_basic_shapes::DrawFilledBox(WorldPosFromOffset(OffsetLumberCamp), FVector(40.0f, 40.0f, 40.0f), CampColor,     true, 2.0f, ECk_Plane_Axis::XY, 0.0f); }
		if (GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasMill")))
		{ utils_pmg_basic_shapes::DrawFilledPyramid(WorldPosFromOffset(OffsetMill),  50.0f, 70.0f,                MillColor,     true, 2.0f, ECk_Plane_Axis::XY, 0.0f); }
		if (GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasMiningCamp")))
		{ utils_pmg_basic_shapes::DrawFilledBox(WorldPosFromOffset(OffsetMiningCamp), FVector(40.0f, 40.0f, 40.0f), CampColor,     true, 2.0f, ECk_Plane_Axis::XY, 0.0f); }
		if (GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasBarracks")))
		{ utils_pmg_basic_shapes::DrawFilledBox(WorldPosFromOffset(OffsetBarracks), FVector(70.0f, 50.0f, 60.0f), BarracksColor, true, 2.0f, ECk_Plane_Axis::XY, 0.0f); }
	}

	// --------------------------------------------------------------------------
	// ACTION → LOCATION MAPPING + DISTANCE-BASED COSTS
	// --------------------------------------------------------------------------

	// Where the villager needs to be standing to perform this action.
	private FVector GetActionTargetLocation(FString InActionName)
	{
		if      (InActionName.Contains("GatherWood"))        { return WorldPosFromOffset(OffsetForest); }
		else if (InActionName.Contains("GatherFood"))        { return WorldPosFromOffset(OffsetBerries); }
		else if (InActionName.Contains("GatherGold"))        { return WorldPosFromOffset(OffsetGold); }
		else if (InActionName.Contains("GatherStone"))       { return WorldPosFromOffset(OffsetStone); }
		else if (InActionName.Contains("BuildLumberCamp"))   { return WorldPosFromOffset(OffsetLumberCamp); }
		else if (InActionName.Contains("BuildMiningCamp"))   { return WorldPosFromOffset(OffsetMiningCamp); }
		else if (InActionName.Contains("BuildMill"))         { return WorldPosFromOffset(OffsetMill); }
		else if (InActionName.Contains("BuildBarracks"))     { return WorldPosFromOffset(OffsetBarracks); }
		else if (InActionName.Contains("ResearchFeudalAge")) { return WorldPosFromOffset(OffsetTownCenter); }
		return WorldPosFromOffset(OffsetTownCenter);
	}

	private FVector GetTargetForActionClass(TSubclassOf<UCk_GoapAction_EntityScript> InClass)
	{
		if (ck::Is_NOT_Valid(InClass)) { return StationOrigin(); }
		return GetActionTargetLocation(InClass.Get().GetName().ToString());
	}

	// Per-action "base" costs. The planner's view of an action's cost is
	// base + distance_from_villager_to_target × CostPerDistanceUnit. The base
	// is what would live in the action's CDO; we restate it here so we can
	// rewrite the dynamic cost each tick without re-loading the CDO.
	private float GetBaseCost(TSubclassOf<UCk_GoapAction_EntityScript> InClass)
	{
		const auto ActionName = ck::IsValid(InClass) ? InClass.Get().GetName().ToString() : FString();
		if      (ActionName.Contains("GatherWoodFromCamp"))   { return 3.0f; }
		else if (ActionName.Contains("GatherWood"))           { return 8.0f; }
		else if (ActionName.Contains("GatherFoodFromMill"))   { return 3.0f; }
		else if (ActionName.Contains("GatherFood"))           { return 8.0f; }
		else if (ActionName.Contains("GatherGold"))           { return 5.0f; }
		else if (ActionName.Contains("GatherStone"))          { return 5.0f; }
		else if (ActionName.Contains("BuildLumberCamp"))      { return 4.0f; }
		else if (ActionName.Contains("BuildMiningCamp"))      { return 4.0f; }
		else if (ActionName.Contains("BuildMill"))            { return 4.0f; }
		else if (ActionName.Contains("BuildBarracks"))        { return 5.0f; }
		else if (ActionName.Contains("ResearchFeudalAge"))    { return 10.0f; }
		return 1.0f;
	}

	// Rewrite every action's cost to reflect current villager position. Called
	// right before Request_Plan so the planner sees up-to-date distance costs.
	private void UpdateActionCostsByDistance()
	{
		auto ActionClasses = TArray<TSubclassOf<UCk_GoapAction_EntityScript>>();
		ActionClasses.Add(UCk_GoapTest_Action_GatherWood);
		ActionClasses.Add(UCk_GoapTest_Action_GatherWoodFromCamp);
		ActionClasses.Add(UCk_GoapTest_Action_GatherFood);
		ActionClasses.Add(UCk_GoapTest_Action_GatherFoodFromMill);
		ActionClasses.Add(UCk_GoapTest_Action_GatherGold);
		ActionClasses.Add(UCk_GoapTest_Action_GatherStone);
		ActionClasses.Add(UCk_GoapTest_Action_BuildLumberCamp);
		ActionClasses.Add(UCk_GoapTest_Action_BuildMill);
		ActionClasses.Add(UCk_GoapTest_Action_BuildMiningCamp);
		ActionClasses.Add(UCk_GoapTest_Action_BuildBarracks);
		ActionClasses.Add(UCk_GoapTest_Action_ResearchFeudalAge);

		const auto VillagerPos = GetVillagerLocation();

		for (auto ActionClass : ActionClasses)
		{
			const auto Target = GetTargetForActionClass(ActionClass);
			const auto Distance = float((VillagerPos - Target).Size());
			const auto BaseCost = GetBaseCost(ActionClass);
			const auto NewCost = BaseCost + Distance * CostPerDistanceUnit;
			utils_goap::Set_ActionCost(GoapEntity, ActionClass, NewCost);
		}
	}

	// Simulates plan execution by writing each action's effects into the world state.
	private void ApplyPlanEffects()
	{
		auto Plan = utils_goap::Get_Plan(GoapEntity);
		for (auto ActionClass : Plan)
		{
			auto ActionName = ActionClass.Get().GetName();
			ApplyEffectByActionName(ActionName.ToString());
		}
	}

	private void ApplyEffectByActionName(FString InName)
	{
		// Mirrors each action's AddEffect/consumption from CkGoap_TestActions.as.
		// Order matters: longer prefixes must win over shorter ones
		// (e.g. "BuildMiningCamp" before "BuildMill", "ResearchFeudalAge" is
		// a distinct prefix so safe). Using if/else-if guarantees single match.
		if      (InName.Contains("GatherWood"))
		{
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasWood"), true);
		}
		else if (InName.Contains("GatherFood"))
		{
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasFood"), true);
		}
		else if (InName.Contains("GatherGold"))
		{
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasGold"), true);
		}
		else if (InName.Contains("GatherStone"))
		{
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasStone"), true);
		}
		else if (InName.Contains("BuildLumberCamp"))
		{
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasLumberCamp"), true);
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasWood"),       false);
		}
		else if (InName.Contains("BuildMiningCamp"))
		{
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasMiningCamp"), true);
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasWood"),       false);
		}
		else if (InName.Contains("BuildMill"))
		{
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasMill"), true);
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasWood"), false);
		}
		else if (InName.Contains("BuildBarracks"))
		{
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasBarracks"), true);
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasWood"),     false);
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasStone"),    false);
		}
		else if (InName.Contains("ResearchFeudalAge"))
		{
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.ReachedFeudalAge"), true);
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasFood"),          false);
			GoapEntity.Set_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasGold"),          false);
		}
	}

	// --------------------------------------------------------------------------
	// PLAN REQUEST HELPERS (used by manual commands)
	// --------------------------------------------------------------------------

	private void RequestPlan_Auto()
	{
		// No specific goal — framework auto-selects highest priority unsatisfied
		LastGoalName = "(auto)";
		CurrentPlan.Reset();
		CurrentActionIndex = -1;
		Phase = ECk_GoapGymEmpire_Phase::AwaitingPlan;
		UpdateActionCostsByDistance();  // bake villager position into costs
		GoapEntity.Request_Plan();
		PlanCount++;
	}

	private void RequestPlan_Specific(TSubclassOf<UCk_GoapGoal_EntityScript> InGoal, FString InLabel)
	{
		LastGoalName = InLabel;
		CurrentPlan.Reset();
		CurrentActionIndex = -1;
		Phase = ECk_GoapGymEmpire_Phase::AwaitingPlan;
		UpdateActionCostsByDistance();
		GoapEntity.Request_PlanForGoal(InGoal);
		PlanCount++;
	}

	private bool IsValidPlanIndex(int32 InIndex)
	{
		return InIndex >= 0 && InIndex < CurrentPlan.Num();
	}

	private void BeginActionAt(int32 InIndex)
	{
		CurrentActionIndex = InIndex;
		CurrentActionElapsed = 0.0f;
		if (!IsValidPlanIndex(InIndex))
		{
			CurrentActionName = "";
			CurrentActionDuration = 0.0f;
			CurrentActionCost = 0.0f;
			return;
		}
		auto ActionClass = CurrentPlan[InIndex];
		CurrentActionName = ActionClass.Get().GetName().ToString();
		CurrentActionCost = utils_goap::Get_ActionCost(GoapEntity, ActionClass);
		CurrentActionDuration = Math::Max(0.05f, CurrentActionCost * SecondsPerCost);

		// Snapshot the villager's start position; the DisplayTick lerp
		// moves VillagerPosition toward VillagerTargetLocation over the
		// action's duration. Cost already encodes distance, so the lerp
		// pace matches the planner's expectation.
		VillagerStartLocation = VillagerPosition;
		VillagerTargetLocation = GetActionTargetLocation(CurrentActionName);
	}

	private void CompleteCurrentAction()
	{
		if (!IsValidPlanIndex(CurrentActionIndex)) { return; }
		auto ActionClass = CurrentPlan[CurrentActionIndex];
		const auto CompletedName = ActionClass.Get().GetName().ToString();

		// Snap villager to the target so we don't drift over many actions.
		VillagerPosition = VillagerTargetLocation;

		ApplyEffectByActionName(CompletedName);
	}

	// --------------------------------------------------------------------------
	// TICK-DRIVEN EXECUTION STATE MACHINE
	// --------------------------------------------------------------------------

	private void AdvanceExecution(float InDeltaSeconds)
	{
		const auto Status = utils_goap::Get_PlanStatus(GoapEntity);

		if (Phase == ECk_GoapGymEmpire_Phase::Idle)
		{
			RequestPlan_Auto();
			return;
		}

		if (Phase == ECk_GoapGymEmpire_Phase::AwaitingPlan)
		{
			if (Status == ECk_GoapPlanStatus::Planning) { return; }

			if (Status == ECk_GoapPlanStatus::PlanFound)
			{
				CurrentPlan = utils_goap::Get_Plan(GoapEntity);
				if (CurrentPlan.Num() == 0)
				{
					// Goal was already satisfied — advance to next plan
					Phase = ECk_GoapGymEmpire_Phase::BetweenPlans;
					PhasePauseElapsed = 0.0f;
					return;
				}
				Phase = ECk_GoapGymEmpire_Phase::Running;
				BeginActionAt(0);
				return;
			}

			// PlanFailed / CostThresholdReached — either all goals satisfied
			// or something's unreachable. Either way, cycle the world.
			Phase = ECk_GoapGymEmpire_Phase::AllGoalsComplete;
			PhasePauseElapsed = 0.0f;
			return;
		}

		if (Phase == ECk_GoapGymEmpire_Phase::Running)
		{
			CurrentActionElapsed += InDeltaSeconds;

			// Animate villager: lerp VillagerPosition from start → target
			// over action duration. DrawArena reads VillagerPosition each
			// frame, so this propagates to the capsule's render position.
			if (CurrentActionDuration > 0.0f)
			{
				const auto Alpha = Math::Clamp(CurrentActionElapsed / CurrentActionDuration, 0.0f, 1.0f);
				VillagerPosition = Math::Lerp(VillagerStartLocation, VillagerTargetLocation, Alpha);
			}

			if (CurrentActionElapsed < CurrentActionDuration) { return; }

			CompleteCurrentAction();

			const auto NextIndex = CurrentActionIndex + 1;
			if (CurrentPlan.IsValidIndex(NextIndex))
			{
				BeginActionAt(NextIndex);
			}
			else
			{
				// Plan complete. Pause briefly, then try the next goal.
				CurrentPlan.Reset();
				CurrentActionIndex = -1;
				CurrentActionName = "(plan complete)";
				CurrentActionDuration = 0.0f;
				CurrentActionElapsed = 0.0f;
				Phase = ECk_GoapGymEmpire_Phase::BetweenPlans;
				PhasePauseElapsed = 0.0f;
			}
			return;
		}

		if (Phase == ECk_GoapGymEmpire_Phase::BetweenPlans)
		{
			PhasePauseElapsed += InDeltaSeconds;
			if (PhasePauseElapsed >= BetweenPlansDelay)
			{
				Phase = ECk_GoapGymEmpire_Phase::Idle;  // request next plan next tick
			}
			return;
		}

		if (Phase == ECk_GoapGymEmpire_Phase::AllGoalsComplete)
		{
			PhasePauseElapsed += InDeltaSeconds;
			if (PhasePauseElapsed >= AllCompleteDelay)
			{
				ResetWorld();
				LastGoalName = "(reset)";
				Phase = ECk_GoapGymEmpire_Phase::Idle;
			}
			return;
		}
	}

	// --------------------------------------------------------------------------
	// MANUAL COMMAND HANDLERS
	// --------------------------------------------------------------------------

	// gym_auto::Setup binds a timer to n"AutoTick" by default — execution here
	// is DisplayTick-driven, so this is a no-op. Keeping the handler lets the
	// standard gym_auto pause/resume plumbing work unchanged.
	UFUNCTION() private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) {}

	UFUNCTION() private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
	}

	UFUNCTION() private void OnPlanGather(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		RequestPlan_Specific(UCk_GoapTest_Goal_GatherResources, "GatherResources");
	}

	UFUNCTION() private void OnPlanMilitary(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		RequestPlan_Specific(UCk_GoapTest_Goal_BuildMilitary, "BuildMilitary");
	}

	UFUNCTION() private void OnPlanFeudal(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		RequestPlan_Specific(UCk_GoapTest_Goal_ReachFeudalAge, "ReachFeudalAge");
	}

	UFUNCTION() private void OnApplyPlan(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		// "Skip ahead": apply every remaining action's effects at once.
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		ApplyPlanEffects();
		CurrentPlan.Reset();
		CurrentActionIndex = -1;
		Phase = ECk_GoapGymEmpire_Phase::BetweenPlans;
		PhasePauseElapsed = 0.0f;
	}

	UFUNCTION() private void OnResetWorld(FCk_Handle InHandle, FGameplayTag InMsg, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		ResetWorld();
		CurrentPlan.Reset();
		CurrentActionIndex = -1;
		CurrentActionName = "";
		Phase = ECk_GoapGymEmpire_Phase::Idle;
		LastGoalName = "(reset)";
	}

	// --------------------------------------------------------------------------
	// DISPLAY (drives both text + execution state machine)
	// --------------------------------------------------------------------------

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (ck::Is_NOT_Valid(GoapEntity)) { return; }
		const auto DeltaSeconds = float(InDeltaT.Get_Seconds());

		if (AutoRunning) { AdvanceExecution(DeltaSeconds); }

		// Redraw arena every frame — PMG's DrawFilled* with duration=0
		// means "1 frame" which is exactly what we want at display cadence.
		DrawArena();

		auto SelfEntity = ck::ToEntity(this);
		auto Status = utils_goap::Get_PlanStatus(GoapEntity);

		auto Wood     = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasWood"));
		auto Food     = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasFood"));
		auto Gold     = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasGold"));
		auto Stone    = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasStone"));
		auto Lumber   = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasLumberCamp"));
		auto Mill     = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasMill"));
		auto Mining   = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasMiningCamp"));
		auto Barracks = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.HasBarracks"));
		auto Feudal   = GoapEntity.Get_WorldStateValue(goap_gym_util::T(n"Goap.WS.AoE.ReachedFeudalAge"));

		auto Text = gym_auto::FormatHeader(AutoConfig, AutoRunning);
		Text = f"{Text}===== Resources =====\n";
		Text = f"{Text}Wood: {Wood}   Food: {Food}   Gold: {Gold}   Stone: {Stone}\n\n";
		Text = f"{Text}===== Buildings =====\n";
		Text = f"{Text}LumberCamp: {Lumber}   Mill: {Mill}   MiningCamp: {Mining}\n";
		Text = f"{Text}Barracks: {Barracks}   FeudalAge: {Feudal}\n\n";

		Text = f"{Text}===== Villager =====\n";
		Text = f"{Text}Phase: {PhaseString(Phase)}\n";
		if (Phase == ECk_GoapGymEmpire_Phase::Running)
		{
			auto Pct = int32(100);
			if (CurrentActionDuration > 0.0f)
			{
				Pct = int32(Math::Clamp(CurrentActionElapsed / CurrentActionDuration, 0.0f, 1.0f) * 100.0f);
			}
			auto Step = CurrentActionIndex + 1;
			auto Total = CurrentPlan.Num();
			Text = f"{Text}Doing: {CurrentActionName}  (step {Step}/{Total}, cost {CurrentActionCost}, {Pct}%)\n";
		}
		else if (Phase == ECk_GoapGymEmpire_Phase::BetweenPlans)
		{
			Text = f"{Text}Plan complete. Next plan in {BetweenPlansDelay - PhasePauseElapsed}s...\n";
		}
		else if (Phase == ECk_GoapGymEmpire_Phase::AllGoalsComplete)
		{
			Text = f"{Text}All goals satisfied. World reset in {AllCompleteDelay - PhasePauseElapsed}s...\n";
		}
		Text = f"{Text}\n";

		Text = f"{Text}===== Planner =====\n";
		Text = f"{Text}Goal: {LastGoalName}   Status: {goap_gym_util::StatusString(Status)}   Plan #{PlanCount}\n";
		Text = f"{Text}{goap_gym_util::FormatPlan(GoapEntity)}\n";
		Text = Text + gym_auto::FormatAutoAndCommands(AutoConfig, 0, AutoRunning);

		auto Mode = AutoRunning ? "[AUTO]" : "[MANUAL]";
		CkGym_Common::Update_StationDisplay(SelfEntity, f"AGE OF EMPIRES {Mode}", Text, "");
	}

	private FString PhaseString(ECk_GoapGymEmpire_Phase InPhase)
	{
		if (InPhase == ECk_GoapGymEmpire_Phase::Idle)             { return "Idle (requesting plan)"; }
		if (InPhase == ECk_GoapGymEmpire_Phase::AwaitingPlan)     { return "Awaiting plan from planner"; }
		if (InPhase == ECk_GoapGymEmpire_Phase::Running)          { return "Executing plan"; }
		if (InPhase == ECk_GoapGymEmpire_Phase::BetweenPlans)     { return "Between plans"; }
		if (InPhase == ECk_GoapGymEmpire_Phase::AllGoalsComplete) { return "All goals complete"; }
		return "Unknown";
	}
}
