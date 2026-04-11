//============================================================================
// FLOAT ATTRIBUTE SIGNAL BINDING STATION
//============================================================================

class UCk_EntityScript_AttributeGym_FloatSignals : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute TestAttribute;

	int32 CycleStep = 0;
	int32 Delegate1Count = 0;
	int32 Delegate2Count = 0;
	int32 Delegate3Count = 0;
	int32 MinClampCount = 0;
	int32 MaxClampCount = 0;
	float32 LastPreviousFinal = 0.0f;
	float32 LastNewFinal = 0.0f;
	float32 LastClampedValue = 0.0f;
	bool Delegate1Bound = false;
	bool Delegate2Bound = false;
	bool Delegate3Bound = false;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatSignals");

		Request_SetupTimers(InHandle);
		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void
	DoBeginPlay(
		FCk_Handle InHandle)
	{
		Request_SetupAttributes(InHandle);
		Request_BindClampSignals(InHandle);

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

		auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.2f));
		AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
		AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"AutoTick"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto TestParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Signal"), 100.0f);
		TestParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(255.0f);
		TestAttribute = utils_float_attribute::Add(InHandle, TestParams);
	}

	void
	Request_BindClampSignals(
		FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnMinClamped(TestAttribute,
			FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMinClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(TestAttribute,
			FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMaxClamped"));
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
			case 1: Request_BindFirstDelegate(); break;
			case 2: Request_BindMultipleDelegates(); break;
			case 3: Request_TriggerValueChanges(); break;
			case 4: Request_UnbindSelectiveDelegates(); break;
			case 5: Request_TestClampSignals(); break;
			case 6: Request_UnbindAllDelegates(); break;
			default:
				CycleStep = 0;
				break;
		}
	}

	void
	Request_BindFirstDelegate()
	{
		utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged1"));

		Delegate1Bound = true;
		utils_float_attribute::Request_Override(TestAttribute, 120.5f);
	}

	void
	Request_BindMultipleDelegates()
	{
		utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged2"));

		utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged3"));

		Delegate2Bound = true;
		Delegate3Bound = true;
		utils_float_attribute::Request_Override(TestAttribute, 80.25f);
	}

	void
	Request_TriggerValueChanges()
	{
		utils_float_attribute::Request_Override(TestAttribute, 150.75f);
		utils_float_attribute::Request_Override(TestAttribute, 60.1f);
		utils_float_attribute::Request_Override(TestAttribute, 200.5f);
	}

	void
	Request_UnbindSelectiveDelegates()
	{
		utils_float_attribute::UnbindFrom_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged2"));

		Delegate2Bound = false;
		utils_float_attribute::Request_Override(TestAttribute, 90.0f);
	}

	void
	Request_TestClampSignals()
	{
		// Push beyond min and max to trigger clamp signals
		utils_float_attribute::Request_Override(TestAttribute, -50.0f);
		utils_float_attribute::Request_Override(TestAttribute, 300.0f);
		utils_float_attribute::Request_Override(TestAttribute, 110.0f);
	}

	void
	Request_UnbindAllDelegates()
	{
		utils_float_attribute::UnbindFrom_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged1"));

		utils_float_attribute::UnbindFrom_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged2"));

		utils_float_attribute::UnbindFrom_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged3"));

		Delegate1Bound = false;
		Delegate2Bound = false;
		Delegate3Bound = false;
		utils_float_attribute::Request_Override(TestAttribute, 130.0f);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT SIGNALS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Cycle Step: {CycleStep}/6\n\n";

		auto CurrentValue = utils_float_attribute::Get_FinalValue(TestAttribute);
		DisplayText = f"{DisplayText}Current Value: {CurrentValue}\n\n";

		DisplayText = f"{DisplayText}DELEGATE STATUS:\n";
		DisplayText = f"{DisplayText}  Delegate1: " + (Delegate1Bound ? "BOUND" : "unbound") + f" (Fired: {Delegate1Count})\n";
		DisplayText = f"{DisplayText}  Delegate2: " + (Delegate2Bound ? "BOUND" : "unbound") + f" (Fired: {Delegate2Count})\n";
		DisplayText = f"{DisplayText}  Delegate3: " + (Delegate3Bound ? "BOUND" : "unbound") + f" (Fired: {Delegate3Count})\n\n";

		auto TotalBound = 0;
		if (Delegate1Bound) TotalBound++;
		if (Delegate2Bound) TotalBound++;
		if (Delegate3Bound) TotalBound++;

		DisplayText = f"{DisplayText}Active Bindings: {TotalBound}/3\n";
		DisplayText = f"{DisplayText}Total Value Signals: " + f"{Delegate1Count + Delegate2Count + Delegate3Count}\n";
		DisplayText = f"{DisplayText}Min Clamps: {MinClampCount} | Max Clamps: {MaxClampCount}\n\n";

		// Payload inspection
		DisplayText = f"{DisplayText}LAST PAYLOAD:\n";
		DisplayText = f"{DisplayText}  Previous Final: {LastPreviousFinal}\n";
		DisplayText = f"{DisplayText}  New Final: {LastNewFinal}\n";
		DisplayText = f"{DisplayText}  Delta: {LastNewFinal - LastPreviousFinal}\n";
		if (LastClampedValue != 0.0f)
		{
			DisplayText = f"{DisplayText}  Last Clamped To: {LastClampedValue}\n";
		}
		DisplayText = f"{DisplayText}\n";

		auto ValueBar = CkGym_Attribute::Create_ProgressBar(CurrentValue, 255.0f, 20);
		DisplayText = f"{DisplayText}[{ValueBar}]\n\n";

		DisplayText = f"{DisplayText}AUTOMATION: " + Get_CurrentPhaseText();

		auto Instructions = "Tests signal binding/unbinding with multiple delegates.\n"
			+ "Shows OnValueChanged payload (previous/new/delta) and clamp events.\n"
			+ "Step 5 pushes values beyond min/max to trigger clamp signals.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}

	FString
	Get_CurrentPhaseText()
	{
		switch (CycleStep)
		{
			case 0: return "Idle - No Bindings";
			case 1: return "Binding First Delegate";
			case 2: return "Binding Multiple Delegates";
			case 3: return "Triggering Value Changes";
			case 4: return "Unbinding Selective Delegate";
			case 5: return "Testing Clamp Signals";
			case 6: return "Unbinding All Delegates";
			default: return "Unknown Phase";
		}
	}

	UFUNCTION()
	void
	OnValueChanged1(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnValueChanged InPayload)
	{
		Delegate1Count++;
		LastPreviousFinal = InPayload.Get_FinalValue_Previous();
		LastNewFinal = InPayload.Get_FinalValue();
	}

	UFUNCTION()
	void
	OnValueChanged2(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnValueChanged InPayload)
	{
		Delegate2Count++;
		LastPreviousFinal = InPayload.Get_FinalValue_Previous();
		LastNewFinal = InPayload.Get_FinalValue();
	}

	UFUNCTION()
	void
	OnValueChanged3(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnValueChanged InPayload)
	{
		Delegate3Count++;
		LastPreviousFinal = InPayload.Get_FinalValue_Previous();
		LastNewFinal = InPayload.Get_FinalValue();
	}

	UFUNCTION()
	void
	OnMinClamped(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		MinClampCount++;
		LastClampedValue = InPayload.Get_FinalClampedValue();
		auto SelfEntity = ck::ToEntity(this);
		CkGym_Attribute::Draw_ClampIndicator(SelfEntity, FVector(-30.0f, 0.0f, 150.0f), FLinearColor(0.0f, 0.5f, 1.0f, 1.0f));
	}

	UFUNCTION()
	void
	OnMaxClamped(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		MaxClampCount++;
		LastClampedValue = InPayload.Get_FinalClampedValue();
		auto SelfEntity = ck::ToEntity(this);
		CkGym_Attribute::Draw_ClampIndicator(SelfEntity, FVector(30.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.5f, 0.0f, 1.0f));
	}

	UFUNCTION()
	private void
	OnResetAttributes(
		FCk_Handle InHandle,
		FGameplayTag InMessageName,
		FInstancedStruct InPayload)
	{
		CycleStep = 0;
		Delegate1Count = 0;
		Delegate2Count = 0;
		Delegate3Count = 0;
		MinClampCount = 0;
		MaxClampCount = 0;
		LastPreviousFinal = 0.0f;
		LastNewFinal = 0.0f;
		LastClampedValue = 0.0f;
		Delegate1Bound = false;
		Delegate2Bound = false;
		Delegate3Bound = false;

		utils_float_attribute::Request_Override(TestAttribute, 100.0f);
	}
}
