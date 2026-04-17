//============================================================================
// FLOAT ATTRIBUTE SIGNAL BINDING STATION
//============================================================================

class UCk_EntityScript_AttributeGym_FloatSignals : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute TestAttribute;

	FCk_Handle_Timer AutoTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;
	int32 Delegate1Count = 0;
	int32 Delegate2Count = 0;
	int32 Delegate3Count = 0;
	int32 MinClampCount = 0;
	int32 MaxClampCount = 0;
	float32 LastPreviousFinal = 0.0f;
	float32 LastNewFinal = 0.0f;
	float32 LastPreClampValue = 0.0f;
	float32 LastClampedValue = 0.0f;
	float32 LastOverflow = 0.0f;
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

		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.2f));

		AutoConfig.TotalSteps = 6;
		AutoConfig.Description = "Tests signal binding/unbinding with multiple delegates.\nShows OnValueChanged payload and OnMinClamped/OnMaxClamped events.";
		AutoConfig.GlobalAutoCommand = "Ck_GymFloat_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymFloat_AutoSignals";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Bind first delegate", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Bind two more delegates", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Trigger multiple value changes", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Unbind delegate 2", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Test min/max clamp signals", 4, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Unbind all delegates", 5, 5));
		AutoConfig.ManualCommands.Add("Ck_GymFloat_SetSignalValue [val]");

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
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_SetValue,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetSignalValue"));
	}

	void Request_SetupAttributes(FCk_Handle InHandle)
	{
		auto TestParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Signal"), 100.0f);
		TestParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(255.0f);
		TestAttribute = utils_float_attribute::Add(InHandle, TestParams);
	}

	void Request_BindClampSignals(FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnMinClamped(TestAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMinClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(TestAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMaxClamped"));
	}

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { Request_UpdateDisplay(); }

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Step = AutoStep % AutoConfig.TotalSteps;

		if (Step == 0)
		{
			utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
				FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged1"));
			Delegate1Bound = true;
			utils_float_attribute::Request_Override(TestAttribute, 120.5f);
		}
		else if (Step == 1)
		{
			utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
				FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged2"));
			utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
				FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged3"));
			Delegate2Bound = true;
			Delegate3Bound = true;
			utils_float_attribute::Request_Override(TestAttribute, 80.25f);
		}
		else if (Step == 2)
		{
			utils_float_attribute::Request_Override(TestAttribute, 150.75f);
			utils_float_attribute::Request_Override(TestAttribute, 60.1f);
			utils_float_attribute::Request_Override(TestAttribute, 200.5f);
		}
		else if (Step == 3)
		{
			utils_float_attribute::UnbindFrom_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
				FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged2"));
			Delegate2Bound = false;
			utils_float_attribute::Request_Override(TestAttribute, 90.0f);
		}
		else if (Step == 4)
		{
			utils_float_attribute::Request_Override(TestAttribute, -50.0f);
			utils_float_attribute::Request_Override(TestAttribute, 300.0f);
			utils_float_attribute::Request_Override(TestAttribute, 110.0f);
		}
		else if (Step == 5)
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
		auto TitleText = "FLOAT SIGNALS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

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

		DisplayText = f"{DisplayText}LAST PAYLOAD:\n";
		DisplayText = f"{DisplayText}  Previous Final: {LastPreviousFinal}\n";
		DisplayText = f"{DisplayText}  New Final: {LastNewFinal}\n";
		DisplayText = f"{DisplayText}  Delta: {LastNewFinal - LastPreviousFinal}\n";
		if (LastClampedValue != 0.0f || LastPreClampValue != 0.0f)
		{
			DisplayText = f"{DisplayText}  Last Clamp: pre={LastPreClampValue} clamped={LastClampedValue} overflow={LastOverflow}\n";
		}

		// Live polling via utility accessors — updates every frame.
		auto LivePre = utils_float_attribute::Get_PreClampFinalValue(TestAttribute);
		auto LiveOvr = utils_float_attribute::Get_ClampOverflow(TestAttribute);
		DisplayText = f"{DisplayText}  Live Poll:  pre={LivePre}  overflow={LiveOvr}\n";

		DisplayText = f"{DisplayText}\n";

		auto ValueBar = CkGym_Attribute::Create_ProgressBar(CurrentValue, 255.0f, 20);
		DisplayText = f"{DisplayText}[{ValueBar}]\n\n";

		DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);
		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION()
	private void OnSetSignalValue(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Typed = InPayload.Get(FCk_Message_FloatGym_SetValue);
		utils_float_attribute::Request_Override(TestAttribute, Typed.Value);
	}

	UFUNCTION() void OnValueChanged1(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { Delegate1Count++; LastPreviousFinal = InPayload.Get_FinalValue_Previous(); LastNewFinal = InPayload.Get_FinalValue(); }
	UFUNCTION() void OnValueChanged2(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { Delegate2Count++; LastPreviousFinal = InPayload.Get_FinalValue_Previous(); LastNewFinal = InPayload.Get_FinalValue(); }
	UFUNCTION() void OnValueChanged3(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { Delegate3Count++; LastPreviousFinal = InPayload.Get_FinalValue_Previous(); LastNewFinal = InPayload.Get_FinalValue(); }
	UFUNCTION() void OnMinClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		MinClampCount++;
		LastPreClampValue = InPayload.Get_PreClampFinalValue();
		LastClampedValue = InPayload.Get_FinalClampedValue();
		LastOverflow = InPayload.Get_ClampOverflow();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(-30.0f, 0.0f, 150.0f), FLinearColor(0.0f, 0.5f, 1.0f, 1.0f));
	}

	UFUNCTION() void OnMaxClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		MaxClampCount++;
		LastPreClampValue = InPayload.Get_PreClampFinalValue();
		LastClampedValue = InPayload.Get_FinalClampedValue();
		LastOverflow = InPayload.Get_ClampOverflow();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(30.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.5f, 0.0f, 1.0f));
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		Delegate1Count = 0; Delegate2Count = 0; Delegate3Count = 0;
		MinClampCount = 0; MaxClampCount = 0;
		LastPreviousFinal = 0.0f; LastNewFinal = 0.0f; LastPreClampValue = 0.0f; LastClampedValue = 0.0f; LastOverflow = 0.0f;
		Delegate1Bound = false; Delegate2Bound = false; Delegate3Bound = false;
		utils_float_attribute::Request_Override(TestAttribute, 100.0f);
	}
}
