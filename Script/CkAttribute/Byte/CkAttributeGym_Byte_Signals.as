//============================================================================
// BYTE ATTRIBUTE SIGNAL BINDING STATION
//============================================================================

class UCk_EntityScript_AttributeGym_ByteSignals : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_ByteAttribute TestAttribute;

	FCk_Handle_Timer AutoTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;

	int32 Delegate1Count = 0;
	int32 Delegate2Count = 0;
	int32 Delegate3Count = 0;
	bool Delegate1Bound = false;
	bool Delegate2Bound = false;
	bool Delegate3Bound = false;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_ByteSignals");

		// Display timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto timer
		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.2f));

		// Auto config
		AutoConfig.TotalSteps = 6;
		AutoConfig.Description = "Tests signal binding/unbinding with multiple delegates.\nShows dynamic bind/unbind and signal firing verification.";
		AutoConfig.GlobalAutoCommand = "Ck_GymByte_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymByte_AutoSignals";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Bind first delegate", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Bind multiple delegates", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Trigger value changes", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Unbind selective delegates", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test rebinding", 4, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Unbind all delegates", 5, 5));
		AutoConfig.ManualCommands.Add("Ck_GymByte_SetSignalValue [val]");

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void
	DoBeginPlay(
		FCk_Handle InHandle)
	{
		Request_SetupAttributes(InHandle);

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ByteGym_SetValue,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetSignalValue"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto TestParams = FCk_Fragment_ByteAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"Test.SignalBinding"), 100);
		TestParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0).Set_MaxValue(255);
		TestAttribute = utils_byte_attribute::Add(InHandle, TestParams);
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { Request_UpdateDisplay(); }

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Step = AutoStep % AutoConfig.TotalSteps;

		if (Step == 0) { Request_BindFirstDelegate(); }
		else if (Step == 1) { Request_BindMultipleDelegates(); }
		else if (Step == 2) { Request_TriggerValueChanges(); }
		else if (Step == 3) { Request_UnbindSelectiveDelegates(); }
		else if (Step == 4) { Request_TestRebinding(); }
		else if (Step == 5) { Request_UnbindAllDelegates(); }

		AutoStep++;
	}

	UFUNCTION()
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning); }

	void Request_BindFirstDelegate()
	{
		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged1"));
		Delegate1Bound = true;
		utils_byte_attribute::Request_Override(TestAttribute, 120);
	}

	void Request_BindMultipleDelegates()
	{
		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged2"));
		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged3"));
		Delegate2Bound = true;
		Delegate3Bound = true;
		utils_byte_attribute::Request_Override(TestAttribute, 80);
	}

	void Request_TriggerValueChanges()
	{
		utils_byte_attribute::Request_Override(TestAttribute, 150);
		utils_byte_attribute::Request_Override(TestAttribute, 60);
		utils_byte_attribute::Request_Override(TestAttribute, 200);
	}

	void Request_UnbindSelectiveDelegates()
	{
		utils_byte_attribute::UnbindFrom_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged2"));
		Delegate2Bound = false;
		utils_byte_attribute::Request_Override(TestAttribute, 90);
	}

	void Request_TestRebinding()
	{
		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged2"));
		Delegate2Bound = true;
		utils_byte_attribute::Request_Override(TestAttribute, 110);
	}

	void Request_UnbindAllDelegates()
	{
		utils_byte_attribute::UnbindFrom_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged1"));
		utils_byte_attribute::UnbindFrom_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged2"));
		utils_byte_attribute::UnbindFrom_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged3"));
		Delegate1Bound = false;
		Delegate2Bound = false;
		Delegate3Bound = false;
		utils_byte_attribute::Request_Override(TestAttribute, 130);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "BYTE SIGNALS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		auto CurrentValue = utils_byte_attribute::Get_FinalValue(TestAttribute);
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
		DisplayText = f"{DisplayText}Total Signals Fired: " + f"{Delegate1Count + Delegate2Count + Delegate3Count}\n\n";

		auto ValueBar = CkGym_Attribute::Create_ProgressBar(CurrentValue, 255.0f, 20);
		DisplayText = f"{DisplayText}[{ValueBar}]\n";

		DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION()
	private void OnSetSignalValue(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Typed = InPayload.Get(FCk_Message_ByteGym_SetValue);
		utils_byte_attribute::Request_Override(TestAttribute, Typed.Value);
	}

	UFUNCTION() void OnValueChanged1(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { Delegate1Count++; }
	UFUNCTION() void OnValueChanged2(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { Delegate2Count++; }
	UFUNCTION() void OnValueChanged3(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { Delegate3Count++; }

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		Delegate1Count = 0;
		Delegate2Count = 0;
		Delegate3Count = 0;
		Delegate1Bound = false;
		Delegate2Bound = false;
		Delegate3Bound = false;
		utils_byte_attribute::Request_Override(TestAttribute, 100);

		AutoRunning = true;
		utils_timer::Request_Resume(AutoTimer);
	}
}
