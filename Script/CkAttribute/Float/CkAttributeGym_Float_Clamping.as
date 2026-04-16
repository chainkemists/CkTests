//============================================================================
// FLOAT CLAMPING ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_AttributeGym_FloatClamping : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute ArmorAttribute;
	FCk_Handle_FloatAttribute StaminaAttribute;
	FCk_Handle_FloatAttribute HealthAttribute;
	FCk_Handle_FloatAttribute ShieldAttribute;

	FCk_Handle_Timer AutoTimer;
	FCk_Handle_Timer UpdateTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;
	int32 ValueChangeCount = 0;
	int32 ClampedCount = 0;
	float32 LastPreClampValue = 0.0f;
	float32 LastClampedValue = 0.0f;

	// Auto-cycling test values (fractional to demonstrate float precision)
	float32 CurrentArmorTest = 100.5f;
	float32 CurrentStaminaTest = 150.75f;
	float32 CurrentHealthTest = 75.25f;
	bool ArmorIncreasing = true;
	bool StaminaIncreasing = true;
	bool HealthIncreasing = false;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatClamping");

		// Display timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Update timer for continuous value cycling
		auto UpdateTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.8f));
		UpdateTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		UpdateTimer = utils_timer::Add(InHandle, UpdateTimerParams);
		UpdateTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"UpdateTick"));

		// Auto timer (controls on/off for the cycling)
		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(1.8f));

		// Auto config
		AutoConfig.TotalSteps = 1;
		AutoConfig.Description = "Cycles fractional values beyond min/max to demonstrate clamping.\nShield demonstrates initial-value clamping (created with value > max).";
		AutoConfig.GlobalAutoCommand = "Ck_GymFloat_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymFloat_AutoClamping";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Cycling Armor/Stamina/Health values", 0, 0));
		AutoConfig.ManualCommands.Add("Ck_GymFloat_TestBoundaries");
		AutoConfig.ManualCommands.Add("Ck_GymFloat_ResetClamping");

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void
	DoBeginPlay(
		FCk_Handle InHandle)
	{
		Request_SetupAttributes(InHandle);
		Request_BindSignals(InHandle);

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_TestBoundaries, FCk_Delegate_Messaging_OnBroadcast(this, n"OnTestBoundaries"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto ArmorParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Armor"), 100.5f);
		ArmorParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(200.0f);
		ArmorAttribute = utils_float_attribute::Add(InHandle, ArmorParams);

		auto StaminaParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Stamina"), 150.75f);
		StaminaParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(50.0f).Set_MaxValue(255.0f);
		StaminaAttribute = utils_float_attribute::Add(InHandle, StaminaParams);

		auto HealthParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Health"), 75.25f);
		HealthParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(100.0f);
		HealthAttribute = utils_float_attribute::Add(InHandle, HealthParams);

		auto ShieldParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Defense"), 200.0f);
		ShieldParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(150.0f);
		ShieldAttribute = utils_float_attribute::Add(InHandle, ShieldParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnValueChanged(ArmorAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnArmorValueChanged"));
		utils_float_attribute::BindTo_OnMinClamped(ArmorAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnArmorClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(ArmorAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnArmorClamped"));
		utils_float_attribute::BindTo_OnValueChanged(StaminaAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnStaminaValueChanged"));
		utils_float_attribute::BindTo_OnMinClamped(StaminaAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnStaminaClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(StaminaAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnStaminaClamped"));
		utils_float_attribute::BindTo_OnValueChanged(HealthAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnHealthValueChanged"));
		utils_float_attribute::BindTo_OnMinClamped(HealthAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnHealthClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(HealthAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnHealthClamped"));
		utils_float_attribute::BindTo_OnValueChanged(ShieldAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnShieldValueChanged"));
		utils_float_attribute::BindTo_OnMinClamped(ShieldAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnShieldClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(ShieldAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnShieldClamped"));
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void UpdateTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (AutoRunning) { Request_AutoUpdateValues(); }
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

	void
	Request_AutoUpdateValues()
	{
		if (ArmorIncreasing) { CurrentArmorTest += 30.7f; if (CurrentArmorTest >= 240.0f) ArmorIncreasing = false; }
		else { CurrentArmorTest -= 40.3f; if (CurrentArmorTest <= -20.0f) ArmorIncreasing = true; }

		if (StaminaIncreasing) { CurrentStaminaTest += 25.5f; if (CurrentStaminaTest >= 280.0f) StaminaIncreasing = false; }
		else { CurrentStaminaTest -= 35.25f; if (CurrentStaminaTest <= 20.0f) StaminaIncreasing = true; }

		if (HealthIncreasing) { CurrentHealthTest += 20.1f; if (CurrentHealthTest >= 120.0f) HealthIncreasing = false; }
		else { CurrentHealthTest -= 25.75f; if (CurrentHealthTest <= -10.0f) HealthIncreasing = true; }

		utils_float_attribute::Request_Override(ArmorAttribute, CurrentArmorTest);
		utils_float_attribute::Request_Override(StaminaAttribute, CurrentStaminaTest);
		utils_float_attribute::Request_Override(HealthAttribute, CurrentHealthTest);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT CLAMPING (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Changes: {ValueChangeCount} | Clamps: {ClampedCount}\n";

		if (ClampedCount > 0)
		{
			auto ClampOverflow = LastPreClampValue - LastClampedValue;
			DisplayText = f"{DisplayText}Last Clamp: pre={LastPreClampValue} clamped={LastClampedValue} overflow={ClampOverflow}\n";
		}

		DisplayText = DisplayText + "\n";

		{
			auto ArmorValue = utils_float_attribute::Get_FinalValue(ArmorAttribute);
			auto ArmorBar = CkGym_Attribute::Create_ProgressBar(ArmorValue, 200.0f, 20, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
			auto ClampSuffix = CkGym_Attribute::Get_ClampingSuffix(ArmorValue, CurrentArmorTest);
			DisplayText = f"{DisplayText}Armor: {ArmorValue}/200{ClampSuffix}\n";
			DisplayText = f"{DisplayText}[{ArmorBar}] " + (ArmorIncreasing ? "UP" : "DOWN") + "\n\n";
		}

		{
			auto StaminaValue = utils_float_attribute::Get_FinalValue(StaminaAttribute);
			auto StaminaBar = CkGym_Attribute::Create_ProgressBar((StaminaValue - 50.0f), (255.0f - 50.0f), 20, ECk_ASCII_ProgressBar_Style::Equal_Symbol);
			auto ClampSuffix = CkGym_Attribute::Get_ClampingSuffix(StaminaValue, CurrentStaminaTest);
			DisplayText = f"{DisplayText}Stamina: {StaminaValue}/255{ClampSuffix}\n";
			DisplayText = f"{DisplayText}[{StaminaBar}] " + (StaminaIncreasing ? "UP" : "DOWN") + "\n\n";
		}

		{
			auto HealthValue = utils_float_attribute::Get_FinalValue(HealthAttribute);
			auto HealthBar = CkGym_Attribute::Create_ProgressBar(HealthValue, 100.0f, 20);
			auto ClampSuffix = CkGym_Attribute::Get_ClampingSuffix(HealthValue, CurrentHealthTest);
			DisplayText = f"{DisplayText}Health: {HealthValue}/100{ClampSuffix}\n";
			DisplayText = f"{DisplayText}[{HealthBar}] " + (HealthIncreasing ? "UP" : "DOWN") + "\n\n";
		}

		{
			auto ShieldValue = utils_float_attribute::Get_FinalValue(ShieldAttribute);
			auto ShieldBar = CkGym_Attribute::Create_ProgressBar(ShieldValue, 150.0f, 20, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
			DisplayText = f"{DisplayText}Shield: {ShieldValue}/150 (Initial: 200.0, clamped on creation)\n";
			DisplayText = f"{DisplayText}[{ShieldBar}] STATIC\n\n";
		}

		DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION() void OnArmorValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
	UFUNCTION() void OnStaminaValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
	UFUNCTION() void OnHealthValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
	UFUNCTION() void OnShieldValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { ValueChangeCount++; }

	UFUNCTION() void OnArmorClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		ClampedCount++; LastPreClampValue = InPayload.Get_PreClampFinalValue(); LastClampedValue = InPayload.Get_FinalClampedValue();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(-50.0f, 0.0f, 150.0f), FLinearColor(0.0f, 0.0f, 1.0f, 1.0f));
	}

	UFUNCTION() void OnStaminaClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		ClampedCount++; LastPreClampValue = InPayload.Get_PreClampFinalValue(); LastClampedValue = InPayload.Get_FinalClampedValue();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(0.0f, 0.0f, 150.0f), FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
	}

	UFUNCTION() void OnHealthClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		ClampedCount++; LastPreClampValue = InPayload.Get_PreClampFinalValue(); LastClampedValue = InPayload.Get_FinalClampedValue();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(50.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
	}

	UFUNCTION() void OnShieldClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		ClampedCount++; LastPreClampValue = InPayload.Get_PreClampFinalValue(); LastClampedValue = InPayload.Get_FinalClampedValue();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(100.0f, 0.0f, 150.0f), FLinearColor(0.0f, 1.0f, 0.0f, 1.0f));
	}

	UFUNCTION()
	private void OnTestBoundaries(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		utils_timer::Request_Pause(UpdateTimer);

		CkGym_Common::Draw_DebugSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 300.0f), FLinearColor(1.0f, 1.0f, 0.0f, 1.0f), 25.0f, 3.0f, 2.0f);
		utils_float_attribute::Request_Override(ArmorAttribute, 999.9f);
		utils_float_attribute::Request_Override(StaminaAttribute, -50.5f);
		utils_float_attribute::Request_Override(HealthAttribute, 150.75f);
		utils_float_attribute::Request_Override(ShieldAttribute, 999.0f);
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		ValueChangeCount = 0;
		ClampedCount = 0;
		LastPreClampValue = 0.0f;
		LastClampedValue = 0.0f;
		CurrentArmorTest = 100.5f;
		CurrentStaminaTest = 150.75f;
		CurrentHealthTest = 75.25f;
		ArmorIncreasing = true;
		StaminaIncreasing = true;
		HealthIncreasing = false;

		utils_float_attribute::Request_Override(ArmorAttribute, 100.5f);
		utils_float_attribute::Request_Override(StaminaAttribute, 150.75f);
		utils_float_attribute::Request_Override(HealthAttribute, 75.25f);
		utils_float_attribute::Request_Override(ShieldAttribute, 200.0f);
	}
}
