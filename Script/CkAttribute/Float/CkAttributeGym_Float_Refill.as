//============================================================================
// FLOAT ATTRIBUTE REFILL STATION (Float-exclusive feature)
//============================================================================

class UCk_EntityScript_AttributeGym_FloatRefill : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute EnergyAttribute;
	FCk_Handle_FloatAttribute ManaAttribute;

	FCk_Handle_Timer AutoTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;
	int32 ValueChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatRefill");

		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(4.0f));

		AutoConfig.TotalSteps = 6;
		AutoConfig.Description = "Tests the float-exclusive refill system with two policies.\nEnergy: Variable | Mana: AlwaysReturnToZero.";
		AutoConfig.GlobalAutoCommand = "panel [T] Auto-cycle all stations";
		AutoConfig.PerStationAutoCommand = "panel [6] Refill station auto";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Drain energy to 20, mana to 15", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Watch refill", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Pause energy refill", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Drain again (energy 10, mana 5)", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Resume energy refill", 4, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Reset to full", 5, 5));
		AutoConfig.ManualCommands.Add("panel [G] Refill ring · toggle refill / drain energy / drain mana");

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
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_ToggleRefill,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnToggleRefill"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_DrainEnergy,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnDrainEnergy"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_DrainMana,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnDrainMana"));
	}

	void Request_SetupAttributes(FCk_Handle InHandle)
	{
		auto RefillParams = FCk_Fragment_FloatAttributeRefill_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Energy.Refill"), 5.0f);
		RefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

		auto EnergyParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Energy"), 100.0f);
		EnergyParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(100.0f);
		EnergyParams.Set_EnableRefill(true).Set_RefillParams(RefillParams);
		EnergyAttribute = utils_float_attribute::Add(InHandle, EnergyParams);

		auto ManaRefillParams = FCk_Fragment_FloatAttributeRefill_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Mana.Refill"), 3.0f);
		ManaRefillParams.Set_RefillBehavior(ECk_Attribute_Refill_Policy::AlwaysReturnToZero);
		ManaRefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

		auto ManaParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Mana"), 80.0f);
		ManaParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(80.0f);
		ManaParams.Set_EnableRefill(true).Set_RefillParams(ManaRefillParams);
		ManaAttribute = utils_float_attribute::Add(InHandle, ManaParams);
	}

	void Request_BindSignals(FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnValueChanged(EnergyAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
		utils_float_attribute::BindTo_OnMinClamped(EnergyAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMinClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(EnergyAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMaxClamped"));
		utils_float_attribute::BindTo_OnValueChanged(ManaAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
	}

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { Request_UpdateDisplay(); }

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Step = AutoStep % AutoConfig.TotalSteps;

		if (Step == 0) { utils_float_attribute::Request_Override(EnergyAttribute, 20.0f, ECk_MinMaxCurrent::Current); utils_float_attribute::Request_Override(ManaAttribute, 15.0f, ECk_MinMaxCurrent::Current); }
		else if (Step == 1) { /* watch refill */ }
		else if (Step == 2) { auto R = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute); if (ck::IsValid(R)) { utils_float_attribute_refill::Request_Pause(R); } }
		else if (Step == 3) { utils_float_attribute::Request_Override(EnergyAttribute, 10.0f, ECk_MinMaxCurrent::Current); utils_float_attribute::Request_Override(ManaAttribute, 5.0f, ECk_MinMaxCurrent::Current); }
		else if (Step == 4) { auto R = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute); if (ck::IsValid(R)) { utils_float_attribute_refill::Request_Resume(R); } }
		else if (Step == 5)
		{
			utils_float_attribute::Request_Override(EnergyAttribute, 100.0f, ECk_MinMaxCurrent::Current);
			utils_float_attribute::Request_Override(ManaAttribute, 80.0f, ECk_MinMaxCurrent::Current);
			auto R = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute); if (ck::IsValid(R)) { utils_float_attribute_refill::Request_Resume(R); }
			auto MR = utils_float_attribute::TryGet_RefillAttribute(ManaAttribute); if (ck::IsValid(MR)) { utils_float_attribute_refill::Request_Resume(MR); }
		}

		AutoStep++;
	}

	UFUNCTION() private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload) { gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning); }

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT REFILL (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Changes: {ValueChangeCount}\n\n";

		auto EnergyValue = utils_float_attribute::Get_FinalValue(EnergyAttribute);
		auto EnergyBar = CkGym_Attribute::Create_ProgressBar(EnergyValue, 100.0f, 25);
		DisplayText = f"{DisplayText}ENERGY (Variable Policy):\n";
		DisplayText = f"{DisplayText}  Value: {EnergyValue}/100\n";
		DisplayText = f"{DisplayText}  [{EnergyBar}]\n";
		{
			auto Refill = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute);
			if (ck::IsValid(Refill))
			{
				auto FillRate = utils_float_attribute_refill::Get_FillRate(Refill);
				auto RefillState = utils_float_attribute_refill::Get_RefillState(Refill);
				auto StateStr = (RefillState == ECk_Attribute_RefillState::Running) ? "RUNNING" : "PAUSED";
				DisplayText = f"{DisplayText}  Rate: {FillRate}/sec | State: {StateStr}\n";
			}
		}

		auto ManaValue = utils_float_attribute::Get_FinalValue(ManaAttribute);
		auto ManaBar = CkGym_Attribute::Create_ProgressBar(ManaValue, 80.0f, 25, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
		DisplayText = f"{DisplayText}\nMANA (AlwaysReturnToZero Policy):\n";
		DisplayText = f"{DisplayText}  Value: {ManaValue}/80\n";
		DisplayText = f"{DisplayText}  [{ManaBar}]\n";
		{
			auto Refill = utils_float_attribute::TryGet_RefillAttribute(ManaAttribute);
			if (ck::IsValid(Refill))
			{
				auto FillRate = utils_float_attribute_refill::Get_FillRate(Refill);
				auto RefillState = utils_float_attribute_refill::Get_RefillState(Refill);
				auto StateStr = (RefillState == ECk_Attribute_RefillState::Running) ? "RUNNING" : "PAUSED";
				DisplayText = f"{DisplayText}  Rate: {FillRate}/sec | State: {StateStr}\n";
			}
		}

		DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);
		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION() void OnValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
	UFUNCTION() void OnMinClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload) { CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(0.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.0f, 0.0f, 1.0f)); }
	UFUNCTION() void OnMaxClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload) { CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(0.0f, 0.0f, 150.0f), FLinearColor(0.0f, 1.0f, 0.0f, 1.0f)); }

	UFUNCTION()
	private void OnDrainEnergy(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		utils_float_attribute::Request_Override(EnergyAttribute, 10.0f, ECk_MinMaxCurrent::Current);
	}

	UFUNCTION()
	private void OnDrainMana(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		utils_float_attribute::Request_Override(ManaAttribute, 5.0f, ECk_MinMaxCurrent::Current);
	}

	UFUNCTION()
	private void OnToggleRefill(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Refill = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute);
		if (ck::IsValid(Refill))
		{
			auto RefillState = utils_float_attribute_refill::Get_RefillState(Refill);
			if (RefillState == ECk_Attribute_RefillState::Running) { utils_float_attribute_refill::Request_Pause(Refill); }
			else { utils_float_attribute_refill::Request_Resume(Refill); }
		}
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		ValueChangeCount = 0;
		utils_float_attribute::Request_Override(EnergyAttribute, 100.0f, ECk_MinMaxCurrent::Current);
		utils_float_attribute::Request_Override(ManaAttribute, 80.0f, ECk_MinMaxCurrent::Current);
		auto R = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute); if (ck::IsValid(R)) { utils_float_attribute_refill::Request_Resume(R); }
		auto MR = utils_float_attribute::TryGet_RefillAttribute(ManaAttribute); if (ck::IsValid(MR)) { utils_float_attribute_refill::Request_Resume(MR); }
	}
}
