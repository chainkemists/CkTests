//============================================================================
// INTEGER MIN/MAX/CURRENT COMPONENTS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_MinMaxCurrent : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_IntegerAttribute PowerLevelAttribute;

	FCk_Handle_Timer AutoTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;

	int32 MinChangeCount = 0;
	int32 MaxChangeCount = 0;
	int32 CurrentChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_MinMaxCurrent");

		// Display timer
		auto DisplayTimerParams = FCk_Timer_Spec(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto timer
		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(3.0f));

		// Auto config
		AutoConfig.TotalSteps = 6;
		AutoConfig.Description = "Tests individual component manipulation (Min/Max/Current).\nShows component presence detection and separate change counters.";
		AutoConfig.GlobalAutoCommand = "Ck_GymInteger_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymInteger_AutoMinMaxCurrent";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Modify Min component (10 -> 20)", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Modify Max component (100 -> 80)", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Modify Current component (50 -> 75)", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test component detection", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test value retrieval", 4, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Reset to defaults", 5, 5));
		AutoConfig.ManualCommands.Add("Ck_GymInteger_SetMin [val]");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_SetMax [val]");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_SetCurrent [val]");

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void
	DoBeginPlay(
		FCk_Handle InHandle)
	{
		Request_SetupAttributes(InHandle);
		Request_BindSignals();

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_SetValue,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetValue"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto PowerParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.PowerLevel"),
			50);
		PowerParams.Set_MinMax(ECk_MinMax::MinMax);
		PowerParams.Set_MinValue(10);
		PowerParams.Set_MaxValue(100);
		PowerLevelAttribute = utils_integer_attribute::Add(InHandle, PowerParams);
	}

	void
	Request_BindSignals()
	{
		utils_integer_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Min,
			FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnMinChanged"));
		utils_integer_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Max,
			FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnMaxChanged"));
		utils_integer_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnCurrentChanged"));
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

		if (Step == 0) { Request_ModifyMin(); }
		else if (Step == 1) { Request_ModifyMax(); }
		else if (Step == 2) { Request_ModifyCurrent(); }
		else if (Step == 3) { /* component detection shown in display */ }
		else if (Step == 4) { /* value retrieval shown in display */ }
		else if (Step == 5) { Request_ResetToDefaults(); }

		AutoStep++;
	}

	UFUNCTION()
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
	}

	void Request_ModifyMin()
	{
		utils_integer_attribute::Request_Override(PowerLevelAttribute, 20, ECk_MinMaxCurrent::Min);
	}

	void Request_ModifyMax()
	{
		utils_integer_attribute::Request_Override(PowerLevelAttribute, 80, ECk_MinMaxCurrent::Max);
	}

	void Request_ModifyCurrent()
	{
		utils_integer_attribute::Request_Override(PowerLevelAttribute, 75, ECk_MinMaxCurrent::Current);
	}

	void Request_ResetToDefaults()
	{
		utils_integer_attribute::Request_Override(PowerLevelAttribute, 10, ECk_MinMaxCurrent::Min);
		utils_integer_attribute::Request_Override(PowerLevelAttribute, 100, ECk_MinMaxCurrent::Max);
		utils_integer_attribute::Request_Override(PowerLevelAttribute, 50, ECk_MinMaxCurrent::Current);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "INTEGER MIN/MAX/CURRENT (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Min Changes: {MinChangeCount} | Max Changes: {MaxChangeCount}\n";
		DisplayText = f"{DisplayText}Current Changes: {CurrentChangeCount}\n\n";

		auto HasMin = utils_integer_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Min);
		auto HasMax = utils_integer_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Max);
		auto HasCurrent = utils_integer_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}Components Present:\n";
		DisplayText = f"{DisplayText}  Min: " + (HasMin ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Max: " + (HasMax ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Current: " + (HasCurrent ? "YES" : "NO") + "\n\n";

		auto MinValue = utils_integer_attribute::Get_FinalValue(PowerLevelAttribute, ECk_MinMaxCurrent::Min);
		auto MaxValue = utils_integer_attribute::Get_FinalValue(PowerLevelAttribute, ECk_MinMaxCurrent::Max);
		auto CurrentValue = utils_integer_attribute::Get_FinalValue(PowerLevelAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}Power Level:\n";
		DisplayText = f"{DisplayText}  Min: {MinValue} (Changes: {MinChangeCount})\n";
		DisplayText = f"{DisplayText}  Max: {MaxValue} (Changes: {MaxChangeCount})\n";
		DisplayText = f"{DisplayText}  Current: {CurrentValue} (Changes: {CurrentChangeCount})\n\n";

		auto PowerBar = CkGym_Attribute::Create_ProgressBar((CurrentValue - MinValue), float32(MaxValue - MinValue), 25);
		DisplayText = f"{DisplayText}[{PowerBar}]\n";
		DisplayText = f"{DisplayText}  {MinValue} <--- {CurrentValue} ---> {MaxValue}\n";

		DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION() void OnMinChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload) { MinChangeCount++; }
	UFUNCTION() void OnMaxChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload) { MaxChangeCount++; }
	UFUNCTION() void OnCurrentChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload) { CurrentChangeCount++; }

	UFUNCTION()
	private void OnSetValue(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Typed = InPayload.Get(FCk_Message_IntegerGym_SetValue);
		utils_integer_attribute::Request_Override(PowerLevelAttribute, Typed.Value, Typed.Component);
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		MinChangeCount = 0;
		MaxChangeCount = 0;
		CurrentChangeCount = 0;
		Request_ResetToDefaults();

		AutoRunning = true;
		utils_timer::Request_Resume(AutoTimer);
	}
}
