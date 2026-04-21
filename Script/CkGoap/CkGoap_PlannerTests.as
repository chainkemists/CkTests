// Language=angelscript
//============================================================================
// GOAP PLANNER TESTS — boolean capability ladder
//============================================================================
//
// Each station isolates ONE planner capability in classical (bool-only) GOAP.
// Stations run on BeginPlay, request a plan, and assert specific structural
// properties when it completes. Display panel shows PENDING / RUNNING / PASS /
// FAIL plus plan and final world state.
//
//   T1  Action execution         — single-step plan
//   T2  Dependency resolution    — strict ordered chain of boolean flags
//   T4  Branching                — two valid strategies, either satisfies goal
//   T5  Cost sensitivity         — cheaper action wins when alternatives exist
//
// Numeric / enum stations (T3, T6, T7, T8, T9) were removed when the planner
// reverted to classical boolean GOAP. They would need total redesign to
// exercise boolean planner behavior rather than numeric regression.

//----------------------------------------------------------------------------
// SHARED UTILITIES
//----------------------------------------------------------------------------

namespace planner_test_util
{
	FGameplayTag T(FName InName) { return GameplayTags::ResolveGameplayTag(InName); }

	FString PlanToString(TArray<TSubclassOf<UCk_GoapAction_EntityScript>> InPlan)
	{
		if (InPlan.Num() == 0) { return "  (empty)\n"; }
		auto Result = FString();
		for (int32 i = 0; i < InPlan.Num(); i++)
		{
			if (ck::IsValid(InPlan[i]))
			{
				Result = Result + f"  {i + 1}. {InPlan[i].Get().GetName()}\n";
			}
		}
		return Result;
	}

	int32 CountAction(TArray<TSubclassOf<UCk_GoapAction_EntityScript>> InPlan,
		TSubclassOf<UCk_GoapAction_EntityScript> InClass)
	{
		auto Count = 0;
		for (int32 i = 0; i < InPlan.Num(); i++)
		{
			if (InPlan[i] == InClass) { Count++; }
		}
		return Count;
	}

	bool ContainsAction(TArray<TSubclassOf<UCk_GoapAction_EntityScript>> InPlan,
		TSubclassOf<UCk_GoapAction_EntityScript> InClass)
	{
		return CountAction(InPlan, InClass) > 0;
	}
}

//============================================================================
// T1 — ACTION EXECUTION
//============================================================================

namespace t1_tags { const FName HasTool = n"Goap.WS.T1.HasTool"; }

class UCk_GoapT1_Action_CreateTool : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddEffect(planner_test_util::T(t1_tags::HasTool), true);
		SetCost(1.0f);
	}
};

class UCk_GoapT1_Goal_HasTool : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineGoal()
	{
		AddCondition(planner_test_util::T(t1_tags::HasTool), true);
		SetPriority(1);
	}
};

class UCk_EntityScript_PlannerT1 : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FString Status = "PENDING";
	FString Note = "";
	TArray<TSubclassOf<UCk_GoapAction_EntityScript>> LastPlan;
	float LastPlanCost = 0.0f;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_PlannerTest_T1");

		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, planner_test_util::T(n"Gym.PlannerTest.T1"));

		GoapEntity.AddAction(UCk_GoapT1_Action_CreateTool);
		GoapEntity.AddGoal  (UCk_GoapT1_Goal_HasTool);
		utils_goap::Set_WorldStateValue(GoapEntity, planner_test_util::T(t1_tags::HasTool), false);

		GoapEntity.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
		GoapEntity.BindTo_OnPlanFailed  (FCk_Delegate_Goap_OnPlanFailed  (this, n"OnPlanFailed"));
		GoapEntity.Request_Plan();
		Status = "RUNNING";

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
	{
		LastPlan = InPayload.Get_Actions();
		LastPlanCost = InPayload.Get_TotalCost();

		if (LastPlan.Num() != 1)             { Status = "FAIL"; Note = f"expected 1 action, got {LastPlan.Num()}"; return; }
		if (!planner_test_util::ContainsAction(LastPlan, UCk_GoapT1_Action_CreateTool))
		{ Status = "FAIL"; Note = "plan missing CreateTool"; return; }
		Status = "PASS";
	}

	UFUNCTION() private void OnPlanFailed(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanFailed InPayload)
	{ Status = "FAIL"; Note = "planner returned PlanFailed"; }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDt)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto HasTool = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t1_tags::HasTool));
		auto Text = f"Status: {Status}\n";
		if (Note.Len() > 0) { Text = Text + f"Note: {Note}\n"; }
		Text = Text + f"Cost: {LastPlanCost}  Length: {LastPlan.Num()}\n";
		Text = Text + f"-- World --\n  HasTool = {HasTool}\n";
		Text = Text + "-- Plan --\n" + planner_test_util::PlanToString(LastPlan);
		CkGym_Common::Update_StationDisplay(SelfEntity, "T1: ACTION EXECUTION", Text, "");
	}
}

//============================================================================
// T2 — DEPENDENCY RESOLUTION (strict ordering via sequential bool flags)
//============================================================================
// Four actions produce four flags. Each depends on the previous. Planner
// must emit them in order Step1 → Step2 → Step3 → StepFinal.

namespace t2_tags
{
	const FName Step1     = n"Goap.WS.T2.Step1";
	const FName Step2     = n"Goap.WS.T2.Step2";
	const FName Step3     = n"Goap.WS.T2.Step3";
	const FName StepFinal = n"Goap.WS.T2.StepFinal";
}

class UCk_GoapT2_Action_DoStep1 : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddEffect(planner_test_util::T(t2_tags::Step1), true);
		SetCost(1.0f);
	}
};

class UCk_GoapT2_Action_DoStep2 : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(planner_test_util::T(t2_tags::Step1), true);
		AddEffect      (planner_test_util::T(t2_tags::Step2), true);
		SetCost(1.0f);
	}
};

class UCk_GoapT2_Action_DoStep3 : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(planner_test_util::T(t2_tags::Step2), true);
		AddEffect      (planner_test_util::T(t2_tags::Step3), true);
		SetCost(1.0f);
	}
};

class UCk_GoapT2_Action_DoStepFinal : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(planner_test_util::T(t2_tags::Step3),     true);
		AddEffect      (planner_test_util::T(t2_tags::StepFinal), true);
		SetCost(1.0f);
	}
};

class UCk_GoapT2_Goal_StepFinal : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineGoal()
	{
		AddCondition(planner_test_util::T(t2_tags::StepFinal), true);
		SetPriority(1);
	}
};

class UCk_EntityScript_PlannerT2 : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;
	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FString Status = "PENDING";
	FString Note = "";
	TArray<TSubclassOf<UCk_GoapAction_EntityScript>> LastPlan;
	float LastPlanCost = 0.0f;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_PlannerTest_T2");
		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, planner_test_util::T(n"Gym.PlannerTest.T2"));

		GoapEntity.AddAction(UCk_GoapT2_Action_DoStep1);
		GoapEntity.AddAction(UCk_GoapT2_Action_DoStep2);
		GoapEntity.AddAction(UCk_GoapT2_Action_DoStep3);
		GoapEntity.AddAction(UCk_GoapT2_Action_DoStepFinal);
		GoapEntity.AddGoal  (UCk_GoapT2_Goal_StepFinal);

		GoapEntity.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
		GoapEntity.BindTo_OnPlanFailed  (FCk_Delegate_Goap_OnPlanFailed  (this, n"OnPlanFailed"));
		GoapEntity.Request_Plan();
		Status = "RUNNING";

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
	{
		LastPlan = InPayload.Get_Actions();
		LastPlanCost = InPayload.Get_TotalCost();

		if (LastPlan.Num() != 4) { Status = "FAIL"; Note = f"expected 4 steps, got {LastPlan.Num()}"; return; }
		if (LastPlan[0] != UCk_GoapT2_Action_DoStep1 ||
		    LastPlan[1] != UCk_GoapT2_Action_DoStep2 ||
		    LastPlan[2] != UCk_GoapT2_Action_DoStep3 ||
		    LastPlan[3] != UCk_GoapT2_Action_DoStepFinal)
		{ Status = "FAIL"; Note = "expected Step1 -> Step2 -> Step3 -> StepFinal"; return; }
		Status = "PASS";
	}

	UFUNCTION() private void OnPlanFailed(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanFailed InPayload)
	{ Status = "FAIL"; Note = "planner returned PlanFailed"; }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDt)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto S1 = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t2_tags::Step1));
		auto S2 = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t2_tags::Step2));
		auto S3 = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t2_tags::Step3));
		auto SF = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t2_tags::StepFinal));
		auto Text = f"Status: {Status}\n";
		if (Note.Len() > 0) { Text = Text + f"Note: {Note}\n"; }
		Text = Text + f"Cost: {LastPlanCost}  Length: {LastPlan.Num()}\n";
		Text = Text + f"-- World --\n  Step1={S1}  Step2={S2}  Step3={S3}  Final={SF}\n";
		Text = Text + "-- Plan --\n" + planner_test_util::PlanToString(LastPlan);
		CkGym_Common::Update_StationDisplay(SelfEntity, "T2: DEPENDENCY RESOLUTION", Text, "");
	}
}

//============================================================================
// T4 — BRANCHING (two valid strategies)
//============================================================================
// Either gather wood then craft-from-wood, or gather stone then craft-from-
// stone. Both produce HasTool. Planner picks either path; we just check it
// completed.

namespace t4_tags
{
	const FName HasWood  = n"Goap.WS.T4.HasWood";
	const FName HasStone = n"Goap.WS.T4.HasStone";
	const FName HasTool  = n"Goap.WS.T4.HasTool";
}

class UCk_GoapT4_Action_GatherWood : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddEffect(planner_test_util::T(t4_tags::HasWood), true);
		SetCost(1.0f);
	}
};

class UCk_GoapT4_Action_GatherStone : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddEffect(planner_test_util::T(t4_tags::HasStone), true);
		SetCost(1.0f);
	}
};

class UCk_GoapT4_Action_CraftToolFromWood : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(planner_test_util::T(t4_tags::HasWood), true);
		AddEffect      (planner_test_util::T(t4_tags::HasTool), true);
		SetCost(1.0f);
	}
};

class UCk_GoapT4_Action_CraftToolFromStone : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(planner_test_util::T(t4_tags::HasStone), true);
		AddEffect      (planner_test_util::T(t4_tags::HasTool),  true);
		SetCost(1.0f);
	}
};

class UCk_GoapT4_Goal_HasTool : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineGoal()
	{
		AddCondition(planner_test_util::T(t4_tags::HasTool), true);
		SetPriority(1);
	}
};

class UCk_EntityScript_PlannerT4 : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;
	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FString Status = "PENDING";
	FString Note = "";
	TArray<TSubclassOf<UCk_GoapAction_EntityScript>> LastPlan;
	float LastPlanCost = 0.0f;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_PlannerTest_T4");
		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, planner_test_util::T(n"Gym.PlannerTest.T4"));

		GoapEntity.AddAction(UCk_GoapT4_Action_GatherWood);
		GoapEntity.AddAction(UCk_GoapT4_Action_GatherStone);
		GoapEntity.AddAction(UCk_GoapT4_Action_CraftToolFromWood);
		GoapEntity.AddAction(UCk_GoapT4_Action_CraftToolFromStone);
		GoapEntity.AddGoal  (UCk_GoapT4_Goal_HasTool);

		GoapEntity.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
		GoapEntity.BindTo_OnPlanFailed  (FCk_Delegate_Goap_OnPlanFailed  (this, n"OnPlanFailed"));
		GoapEntity.Request_Plan();
		Status = "RUNNING";

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
	{
		LastPlan = InPayload.Get_Actions();
		LastPlanCost = InPayload.Get_TotalCost();

		auto UsedWood  = planner_test_util::ContainsAction(LastPlan, UCk_GoapT4_Action_CraftToolFromWood);
		auto UsedStone = planner_test_util::ContainsAction(LastPlan, UCk_GoapT4_Action_CraftToolFromStone);

		if (!UsedWood && !UsedStone)
		{ Status = "FAIL"; Note = "neither craft path taken"; return; }
		Status = "PASS";
		Note = UsedStone ? "chose Stone path" : "chose Wood path";
	}

	UFUNCTION() private void OnPlanFailed(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanFailed InPayload)
	{ Status = "FAIL"; Note = "planner returned PlanFailed"; }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDt)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto HasWood  = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t4_tags::HasWood));
		auto HasStone = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t4_tags::HasStone));
		auto HasTool  = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t4_tags::HasTool));
		auto Text = f"Status: {Status}\n";
		if (Note.Len() > 0) { Text = Text + f"Note: {Note}\n"; }
		Text = Text + f"Cost: {LastPlanCost}  Length: {LastPlan.Num()}\n";
		Text = Text + f"-- World --\n  HasWood={HasWood}  HasStone={HasStone}  HasTool={HasTool}\n";
		Text = Text + "-- Plan --\n" + planner_test_util::PlanToString(LastPlan);
		CkGym_Common::Update_StationDisplay(SelfEntity, "T4: BRANCHING", Text, "");
	}
}

//============================================================================
// T5 — COST SENSITIVITY
//============================================================================
// CheapTool (cost 1) and ExpensiveTool (cost 5) both produce HasTool, both
// need HasMaterial. Gather supplies HasMaterial. Cheap path total = 2;
// expensive path total = 6. Planner must pick CheapTool.

namespace t5_tags
{
	const FName HasMaterial = n"Goap.WS.T5.HasMaterial";
	const FName HasTool     = n"Goap.WS.T5.HasTool";
}

class UCk_GoapT5_Action_Gather : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddEffect(planner_test_util::T(t5_tags::HasMaterial), true);
		SetCost(1.0f);
	}
};

class UCk_GoapT5_Action_CheapTool : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(planner_test_util::T(t5_tags::HasMaterial), true);
		AddEffect      (planner_test_util::T(t5_tags::HasTool),     true);
		SetCost(1.0f);
	}
};

class UCk_GoapT5_Action_ExpensiveTool : UCk_GoapAction_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineAction()
	{
		AddPrecondition(planner_test_util::T(t5_tags::HasMaterial), true);
		AddEffect      (planner_test_util::T(t5_tags::HasTool),     true);
		SetCost(5.0f);
	}
};

class UCk_GoapT5_Goal_HasTool : UCk_GoapGoal_EntityScript
{
	UFUNCTION(BlueprintOverride) void DoDefineGoal()
	{
		AddCondition(planner_test_util::T(t5_tags::HasTool), true);
		SetPriority(1);
	}
};

class UCk_EntityScript_PlannerT5 : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;
	UPROPERTY(ExposeOnSpawn) FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_Goap GoapEntity;
	FString Status = "PENDING";
	FString Note = "";
	TArray<TSubclassOf<UCk_GoapAction_EntityScript>> LastPlan;
	float LastPlanCost = 0.0f;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
		utils_entity_tag::Add(InHandle, n"TAG_PlannerTest_T5");
		auto GoapParams = FCk_Fragment_Goap_ParamsData();
		GoapParams.Set_PlanOnStart(false);
		GoapEntity = utils_goap::Add(InHandle, GoapParams);
		utils_gameplay_label::Add(GoapEntity, planner_test_util::T(n"Gym.PlannerTest.T5"));

		GoapEntity.AddAction(UCk_GoapT5_Action_Gather);
		GoapEntity.AddAction(UCk_GoapT5_Action_CheapTool);
		GoapEntity.AddAction(UCk_GoapT5_Action_ExpensiveTool);
		GoapEntity.AddGoal  (UCk_GoapT5_Goal_HasTool);

		GoapEntity.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
		GoapEntity.BindTo_OnPlanFailed  (FCk_Delegate_Goap_OnPlanFailed  (this, n"OnPlanFailed"));
		GoapEntity.Request_Plan();
		Status = "RUNNING";

		auto DisplayParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
	{
		LastPlan = InPayload.Get_Actions();
		LastPlanCost = InPayload.Get_TotalCost();

		auto UsedCheap     = planner_test_util::ContainsAction(LastPlan, UCk_GoapT5_Action_CheapTool);
		auto UsedExpensive = planner_test_util::ContainsAction(LastPlan, UCk_GoapT5_Action_ExpensiveTool);

		if (UsedExpensive)
		{ Status = "FAIL"; Note = "planner chose ExpensiveTool (cost 5) over CheapTool (cost 1)"; return; }
		if (!UsedCheap)
		{ Status = "FAIL"; Note = "plan has no tool-crafting action"; return; }
		Status = "PASS";
		Note = f"chose CheapTool path (total {LastPlanCost})";
	}

	UFUNCTION() private void OnPlanFailed(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanFailed InPayload)
	{ Status = "FAIL"; Note = "planner returned PlanFailed"; }

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDt)
	{
		auto SelfEntity = ck::ToEntity(this);
		auto Mat  = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t5_tags::HasMaterial));
		auto Tool = utils_goap::Get_WorldStateValue(GoapEntity, planner_test_util::T(t5_tags::HasTool));
		auto Text = f"Status: {Status}\n";
		if (Note.Len() > 0) { Text = Text + f"Note: {Note}\n"; }
		Text = Text + f"Cost: {LastPlanCost}  Length: {LastPlan.Num()}\n";
		Text = Text + f"-- World --\n  HasMaterial={Mat}  HasTool={Tool}\n";
		Text = Text + "-- Plan --\n" + planner_test_util::PlanToString(LastPlan);
		CkGym_Common::Update_StationDisplay(SelfEntity, "T5: COST SENSITIVITY", Text, "");
	}
}
