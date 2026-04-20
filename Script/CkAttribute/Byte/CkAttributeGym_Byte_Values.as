//============================================================================
// BYTE ATTRIBUTE VALUE RETRIEVAL STATION
//============================================================================

class UCk_EntityScript_AttributeGym_ByteValues : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_ByteAttribute TestAttribute;
	TArray<FCk_Handle_ByteAttributeModifier> ActiveModifiers;

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
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_ByteValues");

		// Display timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto timer
		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.8f));

		// Auto config
		AutoConfig.TotalSteps = 6;
		AutoConfig.Description = "Tests Base/Bonus/Final retrieval across Min/Max/Current components.\nShows calculation breakdown with live modifiers.";
		AutoConfig.GlobalAutoCommand = "Ck_GymByte_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymByte_AutoValues";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Add base modifiers (+20, +15)", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Modify Min/Max/Current components", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test all retrieval methods", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Add more modifiers (+12)", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Clear all modifiers", 4, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Reset components to defaults", 5, 5));
		AutoConfig.ManualCommands.Add("Ck_GymByte_AddModifier");
		AutoConfig.ManualCommands.Add("Ck_GymByte_ClearModifiers");

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
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ByteGym_AddModifier,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddModifier"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ByteGym_ClearModifiers,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnClearModifiers"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto TestParams = FCk_Fragment_ByteAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"Test.ValueRetrieval"), 75);
		TestParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(5).Set_MaxValue(180);
		TestAttribute = utils_byte_attribute::Add(InHandle, TestParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Min,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged"));
		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Max,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged"));
		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged"));
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
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
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
	}

	void Request_AddModifiers()
	{
		auto WeaponParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
		WeaponParams.Set_ModifierDelta(20);
		auto WeaponMod = utils_byte_attribute_modifier::Add_Revocable(TestAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"), ECk_AttributeModifier_Operation::Add, WeaponParams);
		if (ck::IsValid(WeaponMod)) { ActiveModifiers.Add(WeaponMod); }

		auto BuffParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
		BuffParams.Set_ModifierDelta(15);
		auto BuffMod = utils_byte_attribute_modifier::Add_Revocable(TestAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"), ECk_AttributeModifier_Operation::Add, BuffParams);
		if (ck::IsValid(BuffMod)) { ActiveModifiers.Add(BuffMod); }
	}

	void Request_ModifyComponents()
	{
		utils_byte_attribute::Request_Override(TestAttribute, 8, ECk_MinMaxCurrent::Min);
		utils_byte_attribute::Request_Override(TestAttribute, 200, ECk_MinMaxCurrent::Max);
		utils_byte_attribute::Request_Override(TestAttribute, 90, ECk_MinMaxCurrent::Current);
	}

	void Request_AddMoreModifiers()
	{
		auto EnchantParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
		EnchantParams.Set_ModifierDelta(12);
		auto EnchantMod = utils_byte_attribute_modifier::Add_Revocable(TestAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Enchant"), ECk_AttributeModifier_Operation::Add, EnchantParams);
		if (ck::IsValid(EnchantMod)) { ActiveModifiers.Add(EnchantMod); }
	}

	void Request_ClearModifiers()
	{
		utils_byte_attribute_modifier::Request_ClearAllModifiers(TestAttribute, ECk_MinMaxCurrent::Current);
		ActiveModifiers.Empty();
	}

	void Request_ResetComponents()
	{
		utils_byte_attribute::Request_Override(TestAttribute, 5, ECk_MinMaxCurrent::Min);
		utils_byte_attribute::Request_Override(TestAttribute, 180, ECk_MinMaxCurrent::Max);
		utils_byte_attribute::Request_Override(TestAttribute, 75, ECk_MinMaxCurrent::Current);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "BYTE VALUES (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Changes: {ValueChangeCount}\n\n";

		auto MinBase = utils_byte_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Min);
		auto MaxBase = utils_byte_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Max);
		auto CurrentBase = utils_byte_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentBonus = utils_byte_attribute::Get_BonusValue(TestAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentFinal = utils_byte_attribute::Get_FinalValue(TestAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}COMPONENT VALUES:\n";
		DisplayText = f"{DisplayText}  Min Base: {MinBase}\n";
		DisplayText = f"{DisplayText}  Max Base: {MaxBase}\n";
		DisplayText = f"{DisplayText}  Current Base: {CurrentBase}\n";
		DisplayText = f"{DisplayText}  Current Bonus: {CurrentBonus}\n";
		DisplayText = f"{DisplayText}  Current Final: {CurrentFinal}\n\n";

		DisplayText = f"{DisplayText}CALCULATION:\n";
		DisplayText = f"{DisplayText}  {CurrentBase} + {CurrentBonus} = {CurrentFinal}\n\n";

		auto ProgressPercent = (CurrentFinal - MinBase) / float32(MaxBase - MinBase);
		auto ValueBar = CkGym_Attribute::Create_ProgressBar(ProgressPercent * 100, 100.0f, 25);
		DisplayText = f"{DisplayText}[{ValueBar}]\n";
		DisplayText = f"{DisplayText}  {MinBase} <--- {CurrentFinal} ---> {MaxBase}\n\n";

		DisplayText = f"{DisplayText}MODIFIERS ({ActiveModifiers.Num()}):\n";
		for (auto i = 0; i < ActiveModifiers.Num(); i++)
		{
			auto Delta = utils_byte_attribute_modifier::Get_Delta(ActiveModifiers[i]);
			DisplayText = f"{DisplayText}  Mod {i+1}: +{Delta}\n";
		}
		if (ActiveModifiers.Num() == 0) { DisplayText = f"{DisplayText}  No active modifiers\n"; }

		DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION() void OnValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { ValueChangeCount++; }

	UFUNCTION()
	private void OnAddModifier(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		Request_AddModifiers();
	}

	UFUNCTION()
	private void OnClearModifiers(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		Request_ClearModifiers();
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		ValueChangeCount = 0;
		utils_byte_attribute_modifier::Request_ClearAllModifiers(TestAttribute, ECk_MinMaxCurrent::Current);
		ActiveModifiers.Empty();
		Request_ResetComponents();

		AutoRunning = true;
		utils_timer::Request_Resume(AutoTimer);
	}
}
