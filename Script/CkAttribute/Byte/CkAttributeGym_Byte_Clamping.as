//============================================================================
// BYTE CLAMPING ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_AttributeGym_ByteClamping : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_ByteAttribute ArmorAttribute;
	FCk_Handle_ByteAttribute StaminaAttribute;
	FCk_Handle_ByteAttribute HealthAttribute;
	FCk_Handle_ByteAttribute ShieldAttribute;

	FCk_Handle_Timer AutoTimer;
	FCk_Handle_Timer UpdateTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;

	int32 ValueChangeCount = 0;
	int32 ClampedCount = 0;
	uint8 LastPreClampValue = 0;
	uint8 LastClampedValue = 0;
	uint8 LastOverflow = 0;

	// Auto-cycling test values
	uint8 CurrentArmorTest = 100;
	uint8 CurrentStaminaTest = 150;
	uint8 CurrentHealthTest = 75;
	bool ArmorIncreasing = true;
	bool StaminaIncreasing = true;
	bool HealthIncreasing = false;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_ByteClamping");

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
		AutoConfig.Description = "Cycles attribute values beyond min/max to demonstrate clamping behavior.\nShield demonstrates initial-value clamping (created with value > max).";
		AutoConfig.GlobalAutoCommand = "Ck_GymByte_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymByte_AutoClamping";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Cycling Armor/Stamina/Health values", 0, 0));
		AutoConfig.ManualCommands.Add("Ck_GymByte_TestBoundaries");
		AutoConfig.ManualCommands.Add("Ck_GymByte_ResetAll");

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
		auto ArmorParams = FCk_Fragment_ByteAttribute_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Armor"), 100);
		ArmorParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0).Set_MaxValue(200);
		ArmorAttribute = utils_byte_attribute::Add(InHandle, ArmorParams);

		auto StaminaParams = FCk_Fragment_ByteAttribute_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Stamina"), 150);
		StaminaParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(50).Set_MaxValue(255);
		StaminaAttribute = utils_byte_attribute::Add(InHandle, StaminaParams);

		auto HealthParams = FCk_Fragment_ByteAttribute_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Health"), 75);
		HealthParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0).Set_MaxValue(100);
		HealthAttribute = utils_byte_attribute::Add(InHandle, HealthParams);

		auto ShieldParams = FCk_Fragment_ByteAttribute_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Shield"), 200);
		ShieldParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0).Set_MaxValue(150);
		ShieldAttribute = utils_byte_attribute::Add(InHandle, ShieldParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		utils_byte_attribute::BindTo_OnValueChanged(ArmorAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnArmorValueChanged"));
		utils_byte_attribute::BindTo_OnMinClamped(ArmorAttribute, FCk_Delegate_ByteAttribute_OnClamped(this, n"OnArmorClamped"));
		utils_byte_attribute::BindTo_OnMaxClamped(ArmorAttribute, FCk_Delegate_ByteAttribute_OnClamped(this, n"OnArmorClamped"));
		utils_byte_attribute::BindTo_OnValueChanged(StaminaAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnStaminaValueChanged"));
		utils_byte_attribute::BindTo_OnMinClamped(StaminaAttribute, FCk_Delegate_ByteAttribute_OnClamped(this, n"OnStaminaClamped"));
		utils_byte_attribute::BindTo_OnMaxClamped(StaminaAttribute, FCk_Delegate_ByteAttribute_OnClamped(this, n"OnStaminaClamped"));
		utils_byte_attribute::BindTo_OnValueChanged(HealthAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnHealthValueChanged"));
		utils_byte_attribute::BindTo_OnMinClamped(HealthAttribute, FCk_Delegate_ByteAttribute_OnClamped(this, n"OnHealthClamped"));
		utils_byte_attribute::BindTo_OnMaxClamped(HealthAttribute, FCk_Delegate_ByteAttribute_OnClamped(this, n"OnHealthClamped"));
		utils_byte_attribute::BindTo_OnValueChanged(ShieldAttribute, ECk_MinMaxCurrent::Current, FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnShieldValueChanged"));
		utils_byte_attribute::BindTo_OnMinClamped(ShieldAttribute, FCk_Delegate_ByteAttribute_OnClamped(this, n"OnShieldClamped"));
		utils_byte_attribute::BindTo_OnMaxClamped(ShieldAttribute, FCk_Delegate_ByteAttribute_OnClamped(this, n"OnShieldClamped"));
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { Request_UpdateDisplay(); }

	UFUNCTION()
	private void UpdateTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		if (AutoRunning) { Request_AutoUpdateValues(); }
	}

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { AutoStep++; }

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
		if (ArmorIncreasing) { CurrentArmorTest = uint8(CurrentArmorTest + 30); if (CurrentArmorTest >= 240) ArmorIncreasing = false; }
		else { CurrentArmorTest = uint8(CurrentArmorTest - 40); if (CurrentArmorTest <= 0) ArmorIncreasing = true; }

		if (StaminaIncreasing) { CurrentStaminaTest = uint8(CurrentStaminaTest + 25); if (CurrentStaminaTest >= 280) StaminaIncreasing = false; }
		else { CurrentStaminaTest = uint8(CurrentStaminaTest - 35); if (CurrentStaminaTest <= 20) StaminaIncreasing = true; }

		if (HealthIncreasing) { CurrentHealthTest = uint8(CurrentHealthTest + 20); if (CurrentHealthTest >= 120) HealthIncreasing = false; }
		else { CurrentHealthTest = uint8(CurrentHealthTest - 25); if (CurrentHealthTest <= 0) HealthIncreasing = true; }

		utils_byte_attribute::Request_Override(ArmorAttribute, CurrentArmorTest, ECk_MinMaxCurrent::Current);
		utils_byte_attribute::Request_Override(StaminaAttribute, CurrentStaminaTest, ECk_MinMaxCurrent::Current);
		utils_byte_attribute::Request_Override(HealthAttribute, CurrentHealthTest, ECk_MinMaxCurrent::Current);
	}

	void
    Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "BYTE CLAMPING (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Changes: {ValueChangeCount} | Clamps: {ClampedCount}\n";

		if (ClampedCount > 0)
		{
			DisplayText = f"{DisplayText}Last Clamp: pre={LastPreClampValue} clamped={LastClampedValue} overflow={LastOverflow}\n";
		}

		// Live polling via utility accessors - shows the Armor attribute's this-frame values.
		auto LivePre = utils_byte_attribute::Get_PreClampFinalValue(ArmorAttribute);
		auto LiveOvr = utils_byte_attribute::Get_ClampOverflow(ArmorAttribute);
		DisplayText = f"{DisplayText}Live Poll (Armor): pre={LivePre}  overflow={LiveOvr}\n";

		DisplayText = DisplayText + "\n";

		{
			auto ArmorValue = utils_byte_attribute::Get_FinalValue(ArmorAttribute);
			auto ArmorBar = CkGym_Attribute::Create_ProgressBar(ArmorValue, 200.0f, 20, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
			auto ClampSuffix = CkGym_Attribute::Get_ClampingSuffix(ArmorValue, CurrentArmorTest);
			DisplayText = f"{DisplayText}Armor: {ArmorValue}/200{ClampSuffix}\n";
			DisplayText = f"{DisplayText}[{ArmorBar}] " + (ArmorIncreasing ? "UP" : "DOWN") + "\n\n";
		}

		{
			auto StaminaValue = utils_byte_attribute::Get_FinalValue(StaminaAttribute);
			auto StaminaBar = CkGym_Attribute::Create_ProgressBar((StaminaValue - 50), (255 - 50), 20, ECk_ASCII_ProgressBar_Style::Equal_Symbol);
			auto ClampSuffix = CkGym_Attribute::Get_ClampingSuffix(StaminaValue, CurrentStaminaTest);
			DisplayText = f"{DisplayText}Stamina: {StaminaValue}/255{ClampSuffix}\n";
			DisplayText = f"{DisplayText}[{StaminaBar}] " + (StaminaIncreasing ? "UP" : "DOWN") + "\n\n";
		}

		{
			auto HealthValue = utils_byte_attribute::Get_FinalValue(HealthAttribute);
			auto HealthBar = CkGym_Attribute::Create_ProgressBar(HealthValue, 100.0f, 20);
			auto ClampSuffix = CkGym_Attribute::Get_ClampingSuffix(HealthValue, CurrentHealthTest);
			DisplayText = f"{DisplayText}Health: {HealthValue}/100{ClampSuffix}\n";
			DisplayText = f"{DisplayText}[{HealthBar}] " + (HealthIncreasing ? "UP" : "DOWN") + "\n\n";
		}

		{
			auto ShieldValue = utils_byte_attribute::Get_FinalValue(ShieldAttribute);
			auto ShieldBar = CkGym_Attribute::Create_ProgressBar(ShieldValue, 150.0f, 20, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
			DisplayText = f"{DisplayText}Shield: {ShieldValue}/150 (Initial: 200, clamped on creation)\n";
			DisplayText = f"{DisplayText}[{ShieldBar}] STATIC\n\n";
		}

		DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION() void OnArmorValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
	UFUNCTION() void OnStaminaValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
	UFUNCTION() void OnHealthValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
	UFUNCTION() void OnShieldValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { ValueChangeCount++; }

	UFUNCTION() void OnArmorClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnClamped InPayload)
	{
		ClampedCount++; LastPreClampValue = InPayload.Get_PreClampFinalValue(); LastClampedValue = InPayload.Get_FinalClampedValue(); LastOverflow = InPayload.Get_ClampOverflow();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(-50.0f, 0.0f, 150.0f), FLinearColor(0.0f, 0.0f, 1.0f, 1.0f));
	}

	UFUNCTION() void OnStaminaClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnClamped InPayload)
	{
		ClampedCount++; LastPreClampValue = InPayload.Get_PreClampFinalValue(); LastClampedValue = InPayload.Get_FinalClampedValue(); LastOverflow = InPayload.Get_ClampOverflow();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(0.0f, 0.0f, 150.0f), FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
	}

	UFUNCTION() void OnHealthClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnClamped InPayload)
	{
		ClampedCount++; LastPreClampValue = InPayload.Get_PreClampFinalValue(); LastClampedValue = InPayload.Get_FinalClampedValue(); LastOverflow = InPayload.Get_ClampOverflow();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(50.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
	}

	UFUNCTION() void OnShieldClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnClamped InPayload)
	{
		ClampedCount++; LastPreClampValue = InPayload.Get_PreClampFinalValue(); LastClampedValue = InPayload.Get_FinalClampedValue(); LastOverflow = InPayload.Get_ClampOverflow();
		CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(100.0f, 0.0f, 150.0f), FLinearColor(0.0f, 1.0f, 0.0f, 1.0f));
	}

	UFUNCTION()
	private void OnTestBoundaries(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		utils_timer::Request_Pause(UpdateTimer);

		CkGym_Common::Draw_DebugSphere(ck::ToEntity(this), FVector(0.0f, 0.0f, 300.0f), FLinearColor(1.0f, 1.0f, 0.0f, 1.0f), 25.0f, 3.0f, 2.0f);
		utils_byte_attribute::Request_Override(ArmorAttribute, 255, ECk_MinMaxCurrent::Current);
		utils_byte_attribute::Request_Override(StaminaAttribute, 30, ECk_MinMaxCurrent::Current);
		utils_byte_attribute::Request_Override(HealthAttribute, 150, ECk_MinMaxCurrent::Current);
		utils_byte_attribute::Request_Override(ShieldAttribute, 255, ECk_MinMaxCurrent::Current);
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		ValueChangeCount = 0;
		ClampedCount = 0;
		LastPreClampValue = 0;
		LastClampedValue = 0;
		LastOverflow = 0;
		CurrentArmorTest = 100;
		CurrentStaminaTest = 150;
		CurrentHealthTest = 75;
		ArmorIncreasing = true;
		StaminaIncreasing = true;
		HealthIncreasing = false;

		utils_byte_attribute::Request_Override(ArmorAttribute, 100, ECk_MinMaxCurrent::Current);
		utils_byte_attribute::Request_Override(StaminaAttribute, 150, ECk_MinMaxCurrent::Current);
		utils_byte_attribute::Request_Override(HealthAttribute, 75, ECk_MinMaxCurrent::Current);
		utils_byte_attribute::Request_Override(ShieldAttribute, 200, ECk_MinMaxCurrent::Current);

		AutoRunning = true;
		utils_timer::Request_Resume(AutoTimer);
		utils_timer::Request_Resume(UpdateTimer);
	}
}
