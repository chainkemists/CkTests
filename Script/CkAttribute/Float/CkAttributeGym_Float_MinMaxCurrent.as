//============================================================================
// FLOAT ATTRIBUTE MIN/MAX/CURRENT COMPONENTS STATION
//============================================================================

class UCk_EntityScript_AttributeGym_FloatMinMaxCurrent : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute PowerLevelAttribute;

	int32 MinChangeCount = 0;
	int32 MaxChangeCount = 0;
	int32 CurrentChangeCount = 0;

	int32 CycleStep = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatMinMaxCurrent");

		Request_SetupTimers(InHandle);
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
	}

	void
	Request_SetupTimers(
		FCk_Handle InHandle)
	{
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(3.0f));
		AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
		AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"AutoTick"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		// PowerLevel: Min=10.0, Max=200.0, Current=100.0
		auto PowerParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.PowerLevel"), 100.0f);
		PowerParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(10.0f).Set_MaxValue(200.0f);
		PowerLevelAttribute = utils_float_attribute::Add(InHandle, PowerParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		auto MinDelegate = FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnMinChanged");
		utils_float_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Min, MinDelegate);

		auto MaxDelegate = FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnMaxChanged");
		utils_float_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Max, MaxDelegate);

		auto CurrentDelegate = FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnCurrentChanged");
		utils_float_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Current, CurrentDelegate);
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
		Request_ExecuteAutomationStep();
	}

	void
	Request_ExecuteAutomationStep()
	{
		CycleStep++;

		switch (CycleStep)
		{
			case 1: Request_ModifyMin(); break;
			case 2: Request_ModifyMax(); break;
			case 3: Request_ModifyCurrent(); break;
			case 4: Request_TestComponentDetection(); break;
			case 5: Request_TestValueRetrieval(); break;
			case 6: Request_ResetToDefaults(); break;
			default:
				CycleStep = 0;
				break;
		}
	}

	void
	Request_ModifyMin()
	{
		utils_float_attribute::Request_Override(PowerLevelAttribute, 25.5f, ECk_MinMaxCurrent::Min);
	}

	void
	Request_ModifyMax()
	{
		utils_float_attribute::Request_Override(PowerLevelAttribute, 175.75f, ECk_MinMaxCurrent::Max);
	}

	void
	Request_ModifyCurrent()
	{
		utils_float_attribute::Request_Override(PowerLevelAttribute, 142.3f, ECk_MinMaxCurrent::Current);
	}

	void
	Request_TestComponentDetection()
	{
		// Component presence displayed in display update
	}

	void
	Request_TestValueRetrieval()
	{
		// All value retrieval shown in display update
	}

	void
	Request_ResetToDefaults()
	{
		utils_float_attribute::Request_Override(PowerLevelAttribute, 10.0f, ECk_MinMaxCurrent::Min);
		utils_float_attribute::Request_Override(PowerLevelAttribute, 200.0f, ECk_MinMaxCurrent::Max);
		utils_float_attribute::Request_Override(PowerLevelAttribute, 100.0f, ECk_MinMaxCurrent::Current);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT MIN/MAX/CURRENT (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Cycle Step: {CycleStep}/6\n";

		DisplayText = f"{DisplayText}Min Changes: {MinChangeCount} | Max Changes: {MaxChangeCount}\n";
		DisplayText = f"{DisplayText}Current Changes: {CurrentChangeCount}\n\n";

		// Component presence detection
		auto HasMin = utils_float_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Min);
		auto HasMax = utils_float_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Max);
		auto HasCurrent = utils_float_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}Components Present:\n";
		DisplayText = f"{DisplayText}  Min: " + (HasMin ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Max: " + (HasMax ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Current: " + (HasCurrent ? "YES" : "NO") + "\n\n";

		// Value retrieval for each component
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

		// Visual representation
		auto Range = MaxValue - MinValue;
		auto BarValue = (Range > 0.0f) ? (CurrentFinal - MinValue) : 0.0f;
		auto PowerBar = CkGym_Attribute::Create_ProgressBar(BarValue, Range, 25);
		DisplayText = f"{DisplayText}[{PowerBar}]\n";
		DisplayText = f"{DisplayText}  {MinValue} <--- {CurrentFinal} ---> {MaxValue}\n\n";

		auto PhaseText = Get_CurrentPhaseText();
		DisplayText = f"{DisplayText}AUTOMATION: {PhaseText}";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText,
            "Tests individual component manipulation (Min/Max/Current).\n" +
            "Shows component presence detection and separate change counters.\n" +
            "Progress bar displays current value within min-max range.\n" +
            "6-step automation cycle modifies each component with fractional values.");
	}

	FString
	Get_CurrentPhaseText()
	{
		switch (CycleStep)
		{
			case 0: return "Idle";
			case 1: return "Modifying Min Component";
			case 2: return "Modifying Max Component";
			case 3: return "Modifying Current Component";
			case 4: return "Testing Component Detection";
			case 5: return "Testing Value Retrieval";
			case 6: return "Resetting to Defaults";
			default: return "Unknown Phase";
		}
	}

	UFUNCTION()
	void
	OnMinChanged(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnValueChanged InPayload)
	{
		MinChangeCount++;
	}

	UFUNCTION()
	void
	OnMaxChanged(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnValueChanged InPayload)
	{
		MaxChangeCount++;
	}

	UFUNCTION()
	void
	OnCurrentChanged(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnValueChanged InPayload)
	{
		CurrentChangeCount++;
	}

	UFUNCTION()
	private void
	OnResetAttributes(
		FCk_Handle InHandle,
		FGameplayTag InMessageName,
		FInstancedStruct InPayload)
	{
		CycleStep = 0;
		MinChangeCount = 0;
		MaxChangeCount = 0;
		CurrentChangeCount = 0;

		utils_float_attribute::Request_Override(PowerLevelAttribute, 10.0f, ECk_MinMaxCurrent::Min);
		utils_float_attribute::Request_Override(PowerLevelAttribute, 200.0f, ECk_MinMaxCurrent::Max);
		utils_float_attribute::Request_Override(PowerLevelAttribute, 100.0f, ECk_MinMaxCurrent::Current);
	}
}
