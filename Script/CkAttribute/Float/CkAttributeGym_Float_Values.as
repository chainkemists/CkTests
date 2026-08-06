//============================================================================
// FLOAT ATTRIBUTE VALUE RETRIEVAL STATION
//============================================================================

class UCk_EntityScript_AttributeGym_FloatValues : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute TestAttribute;
	TArray<FCk_Handle_FloatAttributeModifier> ActiveModifiers;

	FCk_Handle_Timer AutoTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;
	int32 ValueChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatValues");

		// Display timer
		auto DisplayTimerParams = FCk_Timer_Spec(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto timer
		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.8f));

		// Auto config
		AutoConfig.TotalSteps = 6;
		AutoConfig.Description = "Tests Base/Bonus/Final retrieval, percentage, and magnitude.\nShows calculation breakdown with live modifiers.";
		AutoConfig.GlobalAutoCommand = "Ck_GymFloat_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymFloat_AutoValues";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Add base modifiers (+20.5, +15.25)", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Modify Min/Max/Current components", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test all retrieval methods", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Add more modifiers (+12.75)", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Clear all modifiers", 4, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Reset components to defaults", 5, 5));
		AutoConfig.ManualCommands.Add("Ck_GymFloat_AddModifier");
		AutoConfig.ManualCommands.Add("Ck_GymFloat_ClearModifiers");

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void
	DoBeginPlay(
		FCk_Handle InHandle)
	{
		Request_SetupAttributes(InHandle);
		Request_BindSignals(InHandle);

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_AddModifier,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddModifier"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_ClearModifiers,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnClearModifiers"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto TestParams = FCk_FloatAttribute_Spec(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Test"), 75.5f);
		TestParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(5.0f).Set_MaxValue(180.0f);
		TestAttribute = utils_float_attribute::Add(InHandle, TestParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Min,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
		utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Max,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
		utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
	}

	UFUNCTION()
	private void
	DisplayTick(
		FCk_Handle_Timer InHandle,
		FCk_Chrono InChrono,
		FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void
	AutoTick(
		FCk_Handle_Timer InHandle,
		FCk_Chrono InChrono,
		FCk_Time InDeltaT)
	{
		auto Step = AutoStep % AutoConfig.TotalSteps;

		if (Step == 0) { Request_AddModifiers(); }
		else if (Step == 1) { Request_ModifyComponents(); }
		else if (Step == 2) { /* Values retrieved in display */ }
		else if (Step == 3) { Request_AddMoreModifiers(); }
		else if (Step == 4) { Request_ClearModifiers(); }
		else if (Step == 5) { Request_ResetComponents(); }

		AutoStep++;
	}

	UFUNCTION()
	private void
	OnAutoSet(
		FCk_Handle InHandle,
		FGameplayTag InMessageName,
		FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
	}

	void
	Request_AddModifiers()
	{
		auto WeaponParams = FCk_FloatAttributeModifier_Spec();
		WeaponParams.Set_ModifierDelta(20.5f);

		auto WeaponMod = utils_float_attribute_modifier::Add_Revocable(
			TestAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
			ECk_AttributeModifier_Operation::Add,
			WeaponParams);

		if (ck::IsValid(WeaponMod))
		{
			ActiveModifiers.Add(WeaponMod);
		}

		auto BuffParams = FCk_FloatAttributeModifier_Spec();
		BuffParams.Set_ModifierDelta(15.25f);

		auto BuffMod = utils_float_attribute_modifier::Add_Revocable(
			TestAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
			ECk_AttributeModifier_Operation::Add,
			BuffParams);

		if (ck::IsValid(BuffMod))
		{
			ActiveModifiers.Add(BuffMod);
		}
	}

	void
	Request_ModifyComponents()
	{
		utils_float_attribute::Request_Override(TestAttribute, 8.0f, ECk_MinMaxCurrent::Min);
		utils_float_attribute::Request_Override(TestAttribute, 200.0f, ECk_MinMaxCurrent::Max);
		utils_float_attribute::Request_Override(TestAttribute, 90.5f, ECk_MinMaxCurrent::Current);
	}

	void
	Request_AddMoreModifiers()
	{
		auto EnchantParams = FCk_FloatAttributeModifier_Spec();
		EnchantParams.Set_ModifierDelta(12.75f);

		auto EnchantMod = utils_float_attribute_modifier::Add_Revocable(
			TestAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Enchant"),
			ECk_AttributeModifier_Operation::Add,
			EnchantParams);

		if (ck::IsValid(EnchantMod))
		{
			ActiveModifiers.Add(EnchantMod);
		}
	}

	void
	Request_ClearModifiers()
	{
		utils_float_attribute_modifier::Request_ClearAllModifiers(TestAttribute, ECk_MinMaxCurrent::Current);
		ActiveModifiers.Empty();
	}

	void
	Request_ResetComponents()
	{
		utils_float_attribute::Request_Override(TestAttribute, 5.0f, ECk_MinMaxCurrent::Min);
		utils_float_attribute::Request_Override(TestAttribute, 180.0f, ECk_MinMaxCurrent::Max);
		utils_float_attribute::Request_Override(TestAttribute, 75.5f, ECk_MinMaxCurrent::Current);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT VALUES (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Changes: {ValueChangeCount}\n\n";

		auto MinBase = utils_float_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Min);
		auto MaxBase = utils_float_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Max);
		auto CurrentBase = utils_float_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentBonus = utils_float_attribute::Get_BonusValue(TestAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentFinal = utils_float_attribute::Get_FinalValue(TestAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}COMPONENT VALUES:\n";
		DisplayText = f"{DisplayText}  Min Base: {MinBase}\n";
		DisplayText = f"{DisplayText}  Max Base: {MaxBase}\n";
		DisplayText = f"{DisplayText}  Current Base: {CurrentBase}\n";
		DisplayText = f"{DisplayText}  Current Bonus: {CurrentBonus}\n";
		DisplayText = f"{DisplayText}  Current Final: {CurrentFinal}\n\n";

		DisplayText = f"{DisplayText}CALCULATION:\n";
		DisplayText = f"{DisplayText}  {CurrentBase} + {CurrentBonus} = {CurrentFinal}\n\n";

		// Float-specific: percentage and magnitude (exercise both overloads)
		auto PercentByHandle = utils_float_attribute::Get_Value_AsPercentage(TestAttribute);
		auto TestTag = utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Test");
		auto PercentByName = utils_float_attribute::Get_Value_AsPercentage(SelfEntity, TestTag);
		auto Magnitude = utils_float_attribute::Calculate_Attribute_Magnitude(TestAttribute);
		DisplayText = f"{DisplayText}FLOAT-SPECIFIC:\n";
		DisplayText = f"{DisplayText}  Percentage (by handle): {PercentByHandle * 100.0f}%\n";
		DisplayText = f"{DisplayText}  Percentage (by name):   {PercentByName * 100.0f}%\n";
		DisplayText = f"{DisplayText}  Magnitude (Max-Min): {Magnitude}\n\n";

		// Progress bar
		auto MinFinal = utils_float_attribute::Get_FinalValue(TestAttribute, ECk_MinMaxCurrent::Min);
		auto MaxFinal = utils_float_attribute::Get_FinalValue(TestAttribute, ECk_MinMaxCurrent::Max);
		auto ProgressPercent = (CurrentFinal - MinFinal) / (MaxFinal - MinFinal);
		auto ValueBar = CkGym_Attribute::Create_ProgressBar(ProgressPercent * 100.0f, 100.0f, 25);
		DisplayText = f"{DisplayText}[{ValueBar}]\n";
		DisplayText = f"{DisplayText}  {MinFinal} <--- {CurrentFinal} ---> {MaxFinal}\n\n";

		// Active modifiers
		DisplayText = f"{DisplayText}MODIFIERS ({ActiveModifiers.Num()}):\n";
		for (auto i = 0; i < ActiveModifiers.Num(); i++)
		{
			auto Delta = utils_float_attribute_modifier::Get_Delta(ActiveModifiers[i]);
			DisplayText = f"{DisplayText}  Mod {i+1}: +{Delta}\n";
		}

		if (ActiveModifiers.Num() == 0)
		{
			DisplayText = f"{DisplayText}  No active modifiers\n";
		}

		DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION()
	void
	OnValueChanged(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnValueChanged InPayload)
	{
		ValueChangeCount++;
	}

	UFUNCTION()
	private void
	OnAddModifier(
		FCk_Handle InHandle,
		FGameplayTag InMessageName,
		FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		Request_AddModifiers();
	}

	UFUNCTION()
	private void
	OnClearModifiers(
		FCk_Handle InHandle,
		FGameplayTag InMessageName,
		FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		Request_ClearModifiers();
	}

	UFUNCTION()
	private void
	OnResetAttributes(
		FCk_Handle InHandle,
		FGameplayTag InMessageName,
		FInstancedStruct InPayload)
	{
		AutoStep = 0;
		ValueChangeCount = 0;

		utils_float_attribute_modifier::Request_ClearAllModifiers(TestAttribute, ECk_MinMaxCurrent::Current);
		ActiveModifiers.Empty();

		utils_float_attribute::Request_Override(TestAttribute, 5.0f, ECk_MinMaxCurrent::Min);
		utils_float_attribute::Request_Override(TestAttribute, 180.0f, ECk_MinMaxCurrent::Max);
		utils_float_attribute::Request_Override(TestAttribute, 75.5f, ECk_MinMaxCurrent::Current);
	}
}
