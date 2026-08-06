//============================================================================
// FLOAT ATTRIBUTE MULTIPLE ATTRIBUTES STATION
//============================================================================

class UCk_EntityScript_AttributeGym_FloatMultiple : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	TArray<FCk_Handle_FloatAttribute> AllAttributes;
	TArray<FCk_Handle_FloatAttribute> RPGAttributes;
	TArray<FCk_Handle_FloatAttribute> CombatAttributes;

	FCk_Handle_Timer AutoTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;
	int32 TotalAttributes = 0;
	int32 ValueChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatMultiple");

		auto DisplayTimerParams = FCk_Timer_Spec(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(3.5f));

		AutoConfig.TotalSteps = 6;
		AutoConfig.Description = "Creates multiple float attributes in batches.\nTests ForEach iteration, name-based lookups, and filtering.";
		AutoConfig.GlobalAutoCommand = "Ck_GymFloat_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymFloat_AutoMultiple";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Add combat batch (Attack + Defense)", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test ForEach operations", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test name-based lookup", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Batch value update (+15.5)", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test iteration filtering (>100)", 4, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Clear combat batch", 5, 5));
		AutoConfig.ManualCommands.Add("Ck_GymFloat_AddBatch");
		AutoConfig.ManualCommands.Add("Ck_GymFloat_ClearBatch");

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void
	DoBeginPlay(
		FCk_Handle InHandle)
	{
		Request_CreateInitialBatch(InHandle);
		Request_BindSignals(InHandle);

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_AddBatch,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualAddBatch"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_ClearBatch,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualClearBatch"));
	}

	void Request_CreateInitialBatch(FCk_Handle InHandle)
	{
		auto RPGParams = FCk_MultipleFloatAttribute_Spec();
		auto& RPGList = RPGParams._FloatAttributeParams;

		auto StrengthParams = FCk_FloatAttribute_Spec(
			utils_gameplay_tag::ResolveGameplayTag(n"RPG.Strength"), 85.5f);
		StrengthParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(10.0f).Set_MaxValue(255.0f);
		RPGList.Add(StrengthParams);

		auto AgilityParams = FCk_FloatAttribute_Spec(
			utils_gameplay_tag::ResolveGameplayTag(n"RPG.Agility"), 120.25f);
		AgilityParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(20.0f).Set_MaxValue(200.0f);
		RPGList.Add(AgilityParams);

		auto IntelligenceParams = FCk_FloatAttribute_Spec(
			utils_gameplay_tag::ResolveGameplayTag(n"RPG.Intelligence"), 95.75f);
		IntelligenceParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(15.0f).Set_MaxValue(255.0f);
		RPGList.Add(IntelligenceParams);

		RPGAttributes = utils_float_attribute::AddMultiple(InHandle, RPGParams, ECk_Replication::Replicates);
		AllAttributes.Append(RPGAttributes);
	}

	void Request_BindSignals(FCk_Handle InHandle)
	{
		for (auto Attribute : AllAttributes)
		{
			utils_float_attribute::BindTo_OnValueChanged(Attribute, ECk_MinMaxCurrent::Current,
				FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
		}
	}

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { Request_UpdateDisplay(); }

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Step = AutoStep % AutoConfig.TotalSteps;

		if (Step == 0) { Request_AddCombatBatch(); }
		else if (Step == 1) { Request_TestForEachOperations(); }
		else if (Step == 2) { Request_TestNameBasedLookup(); }
		else if (Step == 3) { Request_BatchValueUpdate(); }
		else if (Step == 4) { Request_TestIterationFiltering(); }
		else if (Step == 5) { Request_ClearCombatBatch(); }

		AutoStep++;
	}

	UFUNCTION()
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
	}

	void Request_AddCombatBatch()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto CombatParams = FCk_MultipleFloatAttribute_Spec();
		auto& CombatList = CombatParams._FloatAttributeParams;

		auto AttackParams = FCk_FloatAttribute_Spec(
			utils_gameplay_tag::ResolveGameplayTag(n"Combat.Attack"), 75.5f);
		AttackParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(5.0f).Set_MaxValue(150.0f);
		CombatList.Add(AttackParams);

		auto DefenseParams = FCk_FloatAttribute_Spec(
			utils_gameplay_tag::ResolveGameplayTag(n"Combat.Defense"), 60.25f);
		DefenseParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(100.0f);
		CombatList.Add(DefenseParams);

		CombatAttributes = utils_float_attribute::AddMultiple(SelfEntity, CombatParams, ECk_Replication::Replicates);
		AllAttributes.Append(CombatAttributes);

		for (auto Attribute : CombatAttributes)
		{
			utils_float_attribute::BindTo_OnValueChanged(Attribute, ECk_MinMaxCurrent::Current,
				FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
		}
	}

	void Request_TestForEachOperations()
	{
		auto SelfEntity = ck::ToEntity(this);
		TotalAttributes = 0;
		auto AllFound = utils_float_attribute::ForEach(SelfEntity, FInstancedStruct(), FCk_Lambda_InHandle(this, n"CountAttribute"));
		TotalAttributes = AllFound.Num();
	}

	UFUNCTION() private void CountAttribute(FCk_Handle InHandle, FInstancedStruct InOptionalPayload) { }

	void Request_TestNameBasedLookup()
	{
		auto SelfEntity = ck::ToEntity(this);
		utils_float_attribute::ForEach_ByName(SelfEntity,
			utils_gameplay_tag::ResolveGameplayTag(n"RPG.Strength"), FInstancedStruct(),
			FCk_Lambda_InHandle(this, n"ModifyStrength"));
	}

	UFUNCTION() private void ModifyStrength(FCk_Handle InHandle, FInstancedStruct InOptionalPayload)
	{
		auto StrengthAttr = InHandle.As_FloatAttribute();
		utils_float_attribute::Request_Override(StrengthAttr, 100.5f, ECk_MinMaxCurrent::Current);
	}

	void Request_BatchValueUpdate()
	{
		for (auto Attribute : RPGAttributes)
		{
			auto CurrentValue = utils_float_attribute::Get_FinalValue(Attribute);
			auto NewValue = Math::Clamp(CurrentValue + 15.5f, 0.0f, 255.0f);
			utils_float_attribute::Request_Override(Attribute, NewValue, ECk_MinMaxCurrent::Current);
		}
	}

	void Request_TestIterationFiltering()
	{
		auto SelfEntity = ck::ToEntity(this);
		utils_float_attribute::ForEach_If(SelfEntity, FInstancedStruct(),
			FCk_Lambda_InHandle(this, n"ProcessHighValue"),
			FCk_Predicate_InHandle_OutResult(this, n"FilterHighValue"));
	}

	UFUNCTION() private void ProcessHighValue(FCk_Handle InHandle, FInstancedStruct InOptionalPayload) { }

	UFUNCTION()
	private void FilterHighValue(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InOptionalPayload)
	{
		auto Attr = InHandle.As_FloatAttribute();
		auto Value = utils_float_attribute::Get_FinalValue(Attr);
		auto Res = OutResult;
		Res.Set(Value > 100.0f);
	}

	void Request_ClearCombatBatch()
	{
		for (auto Attribute : CombatAttributes) { AllAttributes.Remove(Attribute); }
		CombatAttributes.Empty();
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT MULTIPLE (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Changes: {ValueChangeCount} | Total: {AllAttributes.Num()}\n\n";

		DisplayText = f"{DisplayText}RPG ATTRIBUTES ({RPGAttributes.Num()}):\n";
		for (auto Attribute : RPGAttributes)
		{
			auto Value = utils_float_attribute::Get_FinalValue(Attribute);
			DisplayText = f"{DisplayText}  RPG Attr: {Value}\n";
		}

		if (CombatAttributes.Num() > 0)
		{
			DisplayText = f"{DisplayText}\nCOMBAT ATTRIBUTES ({CombatAttributes.Num()}):\n";
			for (auto Attribute : CombatAttributes)
			{
				auto Value = utils_float_attribute::Get_FinalValue(Attribute);
				DisplayText = f"{DisplayText}  Combat Attr: {Value}\n";
			}
		}

		DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);
		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION() void OnValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { ValueChangeCount++; }

	UFUNCTION()
	private void OnManualAddBatch(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		Request_AddCombatBatch();
	}

	UFUNCTION()
	private void OnManualClearBatch(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		Request_ClearCombatBatch();
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		ValueChangeCount = 0;
		TotalAttributes = 0;
		AllAttributes.Empty();
		RPGAttributes.Empty();
		CombatAttributes.Empty();
		Request_CreateInitialBatch(InHandle);
		Request_BindSignals(InHandle);
	}
}
