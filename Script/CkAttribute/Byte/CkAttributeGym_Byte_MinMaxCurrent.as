//============================================================================
// BYTE ATTRIBUTE MIN/MAX/CURRENT COMPONENTS STATION
//============================================================================

USTRUCT()
struct FByteMinMaxCurrentSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	FByteMinMaxCurrentSpawnParams(FTransform InTransform)
	{
		InitialTransform = InTransform;
	}
}

//============================================================================
// BYTE MIN/MAX/CURRENT ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_AttributeGym_ByteMinMaxCurrent : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_ByteAttribute PowerLevelAttribute;

	int32 MinChangeCount = 0;
	int32 MaxChangeCount = 0;
	int32 CurrentChangeCount = 0;

	// Automation cycle state
	int32 CycleStep = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_ByteMinMaxCurrent");

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
		DisplayTimer.BindTo_OnUpdate(ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"DisplayTick"));

		auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(3.0f));
		AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
		AutoTimer.BindTo_OnDone(ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"AutoTick"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		// PowerLevel: Min=10, Max=200, Current=100
		auto PowerParams = FCk_Fragment_ByteAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.PowerLevel"), 100);
		PowerParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(10).Set_MaxValue(200);
		PowerLevelAttribute = utils_byte_attribute::Add(InHandle, PowerParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		auto MinDelegate = FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnMinChanged");
		utils_byte_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Min,
			ECk_Signal_BindingPolicy::FireIfPayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing, MinDelegate);

		auto MaxDelegate = FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnMaxChanged");
		utils_byte_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Max,
			ECk_Signal_BindingPolicy::FireIfPayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing, MaxDelegate);

		auto CurrentDelegate = FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnCurrentChanged");
		utils_byte_attribute::BindTo_OnValueChanged(PowerLevelAttribute, ECk_MinMaxCurrent::Current,
			ECk_Signal_BindingPolicy::FireIfPayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing, CurrentDelegate);
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
		utils_byte_attribute::Request_Override(PowerLevelAttribute, 20, ECk_MinMaxCurrent::Min);
	}

	void
	Request_ModifyMax()
	{
		utils_byte_attribute::Request_Override(PowerLevelAttribute, 180, ECk_MinMaxCurrent::Max);
	}

	void
	Request_ModifyCurrent()
	{
		utils_byte_attribute::Request_Override(PowerLevelAttribute, 150, ECk_MinMaxCurrent::Current);
	}

	void
	Request_TestComponentDetection()
	{
		// This step just displays component presence in the display update
	}

	void
	Request_TestValueRetrieval()
	{
		// Test all value retrieval methods - results shown in display
	}

	void
	Request_ResetToDefaults()
	{
		utils_byte_attribute::Request_Override(PowerLevelAttribute, 10, ECk_MinMaxCurrent::Min);
		utils_byte_attribute::Request_Override(PowerLevelAttribute, 200, ECk_MinMaxCurrent::Max);
		utils_byte_attribute::Request_Override(PowerLevelAttribute, 100, ECk_MinMaxCurrent::Current);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::SelfEntity(this);
		auto TitleText = "BYTE MIN/MAX/CURRENT (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Cycle Step: {CycleStep}/6\n";

		DisplayText = f"{DisplayText}Min Changes: {MinChangeCount} | Max Changes: {MaxChangeCount}\n";
		DisplayText = f"{DisplayText}Current Changes: {CurrentChangeCount}\n\n";

		// Component presence detection
		auto HasMin = utils_byte_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Min);
		auto HasMax = utils_byte_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Max);
		auto HasCurrent = utils_byte_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}Components Present:\n";
		DisplayText = f"{DisplayText}  Min: " + (HasMin ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Max: " + (HasMax ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Current: " + (HasCurrent ? "YES" : "NO") + "\n\n";

		// Value retrieval for each component
		auto MinValue = utils_byte_attribute::Get_BaseValue(PowerLevelAttribute, ECk_MinMaxCurrent::Min);
		auto MaxValue = utils_byte_attribute::Get_BaseValue(PowerLevelAttribute, ECk_MinMaxCurrent::Max);
		auto CurrentBase = utils_byte_attribute::Get_BaseValue(PowerLevelAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentBonus = utils_byte_attribute::Get_BonusValue(PowerLevelAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentFinal = utils_byte_attribute::Get_FinalValue(PowerLevelAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}PowerLevel Values:\n";
		DisplayText = f"{DisplayText}  Min: {MinValue}\n";
		DisplayText = f"{DisplayText}  Max: {MaxValue}\n";
		DisplayText = f"{DisplayText}  Current Base: {CurrentBase}\n";
		DisplayText = f"{DisplayText}  Current Bonus: {CurrentBonus}\n";
		DisplayText = f"{DisplayText}  Current Final: {CurrentFinal}\n\n";

		// Visual representation
		auto PowerBar = CkGym_Attribute::Create_ProgressBar((CurrentFinal - MinValue), (MaxValue - MinValue), 25);
		DisplayText = f"{DisplayText}[{PowerBar}]\n";
		DisplayText = f"{DisplayText}  {MinValue} <--- {CurrentFinal} ---> {MaxValue}\n\n";

		// Current automation phase
		auto PhaseText = Get_CurrentPhaseText();
		DisplayText = f"{DisplayText}AUTOMATION: {PhaseText}";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText,
            "Tests individual component manipulation (Min/Max/Current).\n" +
            "Shows component presence detection and separate change counters.\n" +
            "Progress bar displays current value within min-max range.\n" +
            "6-step automation cycle modifies each component separately.");
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

	// Signal callbacks
	UFUNCTION()
	void
	OnMinChanged(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_ByteAttribute_OnValueChanged InPayload)
	{
		MinChangeCount++;
	}

	UFUNCTION()
	void
	OnMaxChanged(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_ByteAttribute_OnValueChanged InPayload)
	{
		MaxChangeCount++;
	}

	UFUNCTION()
	void
	OnCurrentChanged(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_ByteAttribute_OnValueChanged InPayload)
	{
		CurrentChangeCount++;
	}

	// Message handlers
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

		utils_byte_attribute::Request_Override(PowerLevelAttribute, 10, ECk_MinMaxCurrent::Min);
		utils_byte_attribute::Request_Override(PowerLevelAttribute, 200, ECk_MinMaxCurrent::Max);
		utils_byte_attribute::Request_Override(PowerLevelAttribute, 100, ECk_MinMaxCurrent::Current);
	}
}