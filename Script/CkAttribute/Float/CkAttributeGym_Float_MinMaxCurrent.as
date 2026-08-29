//============================================================================
// FLOAT ATTRIBUTE MIN/MAX/CURRENT COMPONENTS STATION
//============================================================================

class UCk_EntityScript_AttributeGym_FloatMinMaxCurrent : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute PowerLevelAttribute;

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
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatMinMaxCurrent");

		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(3.0f));

		AutoConfig.TotalSteps = 6;
		AutoConfig.Description = "Tests individual Min/Max/Current component manipulation.\nShows component presence detection and separate change counters.";
		AutoConfig.GlobalAutoCommand = "panel [T] Auto-cycle all stations";
		AutoConfig.PerStationAutoCommand = "panel [4] Min/Max/Current station auto";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Modify Min component (10 -> 25.5)", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Modify Max component (200 -> 175.75)", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Modify Current component (100 -> 142.3)", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test component detection", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test value retrieval", 4, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Reset to defaults", 5, 5));
		AutoConfig.ManualCommands.Add("panel [U] Min preset · [I] Max preset · [O] Current preset");

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
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_SetValue,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetValue"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto PowerParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.PowerLevel"), 100.0f);
		PowerParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(10.0f).Set_MaxValue(200.0f);
		PowerLevelAttribute = utils_float_attribute::Add(InHandle, PowerParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Min,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnMinChanged"));
		utils_float_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Max,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnMaxChanged"));
		utils_float_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnCurrentChanged"));
	}

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { Request_UpdateDisplay(); }

	UFUNCTION()
	private void
	AutoTick(
		FCk_Handle_Timer InHandle,
		FCk_Chrono InChrono,
		FCk_Time InDeltaT)
	{
		auto Step = AutoStep % AutoConfig.TotalSteps;

		if (Step == 0) { utils_float_attribute::Request_Override(PowerLevelAttribute, 25.5f, ECk_MinMaxCurrent::Min); }
		else if (Step == 1) { utils_float_attribute::Request_Override(PowerLevelAttribute, 175.75f, ECk_MinMaxCurrent::Max); }
		else if (Step == 2) { utils_float_attribute::Request_Override(PowerLevelAttribute, 142.3f, ECk_MinMaxCurrent::Current); }
		else if (Step == 3) { /* component detection shown in display */ }
		else if (Step == 4) { /* value retrieval shown in display */ }
		else if (Step == 5)
		{
			utils_float_attribute::Request_Override(PowerLevelAttribute, 10.0f, ECk_MinMaxCurrent::Min);
			utils_float_attribute::Request_Override(PowerLevelAttribute, 200.0f, ECk_MinMaxCurrent::Max);
			utils_float_attribute::Request_Override(PowerLevelAttribute, 100.0f, ECk_MinMaxCurrent::Current);
		}

		AutoStep++;
	}

	UFUNCTION()
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT MIN/MAX/CURRENT (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Min Changes: {MinChangeCount} | Max Changes: {MaxChangeCount}\n";
		DisplayText = f"{DisplayText}Current Changes: {CurrentChangeCount}\n\n";

		auto HasMin = utils_float_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Min);
		auto HasMax = utils_float_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Max);
		auto HasCurrent = utils_float_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}Components Present:\n";
		DisplayText = f"{DisplayText}  Min: " + (HasMin ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Max: " + (HasMax ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Current: " + (HasCurrent ? "YES" : "NO") + "\n\n";

		auto MinValue = utils_float_attribute::Get_BaseValue(PowerLevelAttribute, ECk_MinMaxCurrent::Min);
		auto MaxValue = utils_float_attribute::Get_BaseValue(PowerLevelAttribute, ECk_MinMaxCurrent::Max);
		auto CurrentBase = utils_float_attribute::Get_BaseValue(PowerLevelAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentBonus = utils_float_attribute::Get_BonusValue(PowerLevelAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentFinal = utils_float_attribute::Get_FinalValue(PowerLevelAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}PowerLevel Values:\n";
		DisplayText = f"{DisplayText}  Min: {MinValue}\n";
		DisplayText = f"{DisplayText}  Max: {MaxValue}\n";
		DisplayText = f"{DisplayText}  Current Base: {CurrentBase}\n";
		DisplayText = f"{DisplayText}  Current Bonus: {CurrentBonus}\n";
		DisplayText = f"{DisplayText}  Current Final: {CurrentFinal}\n\n";

		auto Range = MaxValue - MinValue;
		auto BarValue = (Range > 0.0f) ? (CurrentFinal - MinValue) : 0.0f;
		auto PowerBar = CkGym_Attribute::Create_ProgressBar(BarValue, Range, 25);
		DisplayText = f"{DisplayText}[{PowerBar}]\n";
		DisplayText = f"{DisplayText}  {MinValue} <--- {CurrentFinal} ---> {MaxValue}\n\n";

		DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);
		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION()
	private void OnSetValue(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Typed = InPayload.Get(FCk_Message_FloatGym_SetValue);
		utils_float_attribute::Request_Override(PowerLevelAttribute, Typed.Value, Typed.Component);
	}

	UFUNCTION() void OnMinChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { MinChangeCount++; }
	UFUNCTION() void OnMaxChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { MaxChangeCount++; }
	UFUNCTION() void OnCurrentChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { CurrentChangeCount++; }

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		MinChangeCount = 0;
		MaxChangeCount = 0;
		CurrentChangeCount = 0;

		utils_float_attribute::Request_Override(PowerLevelAttribute, 10.0f, ECk_MinMaxCurrent::Min);
		utils_float_attribute::Request_Override(PowerLevelAttribute, 200.0f, ECk_MinMaxCurrent::Max);
		utils_float_attribute::Request_Override(PowerLevelAttribute, 100.0f, ECk_MinMaxCurrent::Current);
	}
}
