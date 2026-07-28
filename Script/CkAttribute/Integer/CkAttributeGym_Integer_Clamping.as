//============================================================================
// INTEGER CLAMPING & SIGNALS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_Clamping : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_IntegerAttribute ResourceAttribute;

	FCk_Handle_Timer AutoTimer;
	FCk_Handle_Timer UpdateTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;

	int32 MinClampCount = 0;
	int32 MaxClampCount = 0;
	int32 LastInputValue = 50;
	int32 LastPreClampValue = 0;
	int32 LastClampedValue = 0;
	int32 LastOverflow = 0;

	// Auto-cycling test values
	int32 CurrentTestValue = 50;
	bool IsIncreasing = true;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_Clamping");

		// Display timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Update timer for continuous value cycling
		auto UpdateTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.5f));
		UpdateTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		UpdateTimer = utils_timer::Add(InHandle, UpdateTimerParams);
		UpdateTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"UpdateTick"));

		// Auto timer (controls on/off for the cycling)
		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.5f));

		// Auto config
		AutoConfig.TotalSteps = 1;
		AutoConfig.Description = "Auto-cycles values beyond min/max to trigger OnMinClamped and OnMaxClamped.";
		AutoConfig.GlobalAutoCommand = "Ck_GymInteger_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymInteger_AutoClamping";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Cycling Resource value (0-100 range)", 0, 0));
		AutoConfig.ManualCommands.Add("Ck_GymInteger_SetResource [val]");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_TestBoundaries");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_ResetClamping");

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
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_TestBoundaries,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnTestBoundaries"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_SetResource,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetResource"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto ResourceParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Resource"),
			50);
		ResourceParams.Set_MinMax(ECk_MinMax::MinMax);
		ResourceParams.Set_MinValue(0);
		ResourceParams.Set_MaxValue(100);
		ResourceAttribute = utils_integer_attribute::Add(InHandle, ResourceParams);
	}

	void
	Request_BindSignals()
	{
		utils_integer_attribute::BindTo_OnMinClamped(ResourceAttribute,
			FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMinClamped"));
		utils_integer_attribute::BindTo_OnMaxClamped(ResourceAttribute,
			FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMaxClamped"));
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void UpdateTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (AutoRunning) { Request_AutoUpdateValue(); }
	}

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		AutoStep++;
	}

	UFUNCTION()
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
		if (AutoRunning) { utils_timer::Request_Resume(UpdateTimer); }
		else { utils_timer::Request_Pause(UpdateTimer); }
	}

	void Request_AutoUpdateValue()
	{
		if (ck::Is_NOT_Valid(ResourceAttribute))
			return;

		if (IsIncreasing)
		{
			CurrentTestValue += 20;
			if (CurrentTestValue >= 120) { IsIncreasing = false; }
		}
		else
		{
			CurrentTestValue -= 25;
			if (CurrentTestValue <= -20) { IsIncreasing = true; }
		}

		LastInputValue = CurrentTestValue;
		utils_integer_attribute::Request_Override(ResourceAttribute, CurrentTestValue, ECk_MinMaxCurrent::Current);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "INTEGER CLAMPING (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Min Clamps: {MinClampCount} | Max Clamps: {MaxClampCount}\n";

		if (MinClampCount > 0 || MaxClampCount > 0)
		{
			DisplayText = f"{DisplayText}Last Clamp: pre={LastPreClampValue} clamped={LastClampedValue} overflow={LastOverflow}\n";
		}

		// Live polling via utility accessors — updates every frame (this-frame values).
		auto LivePre = utils_integer_attribute::Get_PreClampFinalValue(ResourceAttribute);
		auto LiveOvr = utils_integer_attribute::Get_ClampOverflow(ResourceAttribute);
		DisplayText = f"{DisplayText}Live Poll:  pre={LivePre}  overflow={LiveOvr}\n";

		DisplayText = DisplayText + "\n";

		auto ResourceValue = utils_integer_attribute::Get_FinalValue(ResourceAttribute);
		auto ClampStatus = "";

		if (ResourceValue == 0 && LastInputValue < 0) { ClampStatus = " [MIN CLAMPED]"; }
		else if (ResourceValue == 100 && LastInputValue > 100) { ClampStatus = " [MAX CLAMPED]"; }
		else { ClampStatus = " [NORMAL]"; }

		DisplayText = f"{DisplayText}Resource: {ResourceValue}/100\n";
		DisplayText = f"{DisplayText}Input Value: {LastInputValue}\n";
		DisplayText = f"{DisplayText}Status: " + ClampStatus + "\n";
		DisplayText = f"{DisplayText}Direction: " + (IsIncreasing ? "INCREASING" : "DECREASING") + "\n\n";

		auto ResourceBar = CkGym_Attribute::Create_ProgressBar(ResourceValue, 100.0f, 20);
		DisplayText = f"{DisplayText}[{ResourceBar}]\n";

		DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION() void OnMinClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnClamped InPayload)
	{
		MinClampCount++;
		LastPreClampValue = InPayload.Get_PreClampFinalValue();
		LastClampedValue = InPayload.Get_FinalClampedValue();
		LastOverflow = InPayload.Get_ClampOverflow();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(-50.0f, 0.0f, 150.0f), FLinearColor(0.0f, 0.0f, 1.0f, 1.0f));
	}

	UFUNCTION() void OnMaxClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnClamped InPayload)
	{
		MaxClampCount++;
		LastPreClampValue = InPayload.Get_PreClampFinalValue();
		LastClampedValue = InPayload.Get_FinalClampedValue();
		LastOverflow = InPayload.Get_ClampOverflow();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(50.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
	}

	UFUNCTION()
	private void OnSetResource(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		utils_timer::Request_Pause(UpdateTimer);
		auto Typed = InPayload.Get(FCk_Message_IntegerGym_SetResource);
		CurrentTestValue = Typed.Value;
		LastInputValue = Typed.Value;
		utils_integer_attribute::Request_Override(ResourceAttribute, Typed.Value, ECk_MinMaxCurrent::Current);
	}

	UFUNCTION()
	private void OnTestBoundaries(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		utils_timer::Request_Pause(UpdateTimer);

		CkGym_Common::Draw_DebugSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 250.0f), FLinearColor(1.0f, 1.0f, 0.0f, 1.0f), 25.0f, 3.0f, 2.0f);
		utils_integer_attribute::Request_Override(ResourceAttribute, -50, ECk_MinMaxCurrent::Current);
		utils_integer_attribute::Request_Override(ResourceAttribute, 150, ECk_MinMaxCurrent::Current);
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		MinClampCount = 0;
		MaxClampCount = 0;
		CurrentTestValue = 50;
		LastInputValue = 50;
		LastPreClampValue = 0;
		LastClampedValue = 0;
		LastOverflow = 0;
		IsIncreasing = true;

		utils_integer_attribute::Request_Override(ResourceAttribute, 50, ECk_MinMaxCurrent::Current);

		AutoRunning = true;
		utils_timer::Request_Resume(AutoTimer);
		utils_timer::Request_Resume(UpdateTimer);
	}
}
