//============================================================================
// FLOAT ATTRIBUTE REFILL STATION (Float-exclusive feature)
//============================================================================

class UCk_EntityScript_AttributeGym_FloatRefill : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute EnergyAttribute;
	FCk_Handle_FloatAttribute ManaAttribute;

	int32 CycleStep = 0;
	int32 ValueChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatRefill");

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
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_ToggleRefill,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnToggleRefill"));
	}

	void
	Request_SetupTimers(
		FCk_Handle InHandle)
	{
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(4.0f));
		AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
		AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"AutoTick"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		// Energy: 0-100, starts at 100.0, with refill enabled
		auto RefillParams = FCk_Fragment_FloatAttributeRefill_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Energy"), 5.0f);
		RefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

		auto EnergyParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Energy"), 100.0f);
		EnergyParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(100.0f);
		EnergyParams.Set_EnableRefill(true).Set_RefillParams(RefillParams);

		EnergyAttribute = utils_float_attribute::Add(InHandle, EnergyParams);

		// Mana: 0-80, starts at 80.0, refill with AlwaysReturnToZero policy
		auto ManaRefillParams = FCk_Fragment_FloatAttributeRefill_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Mana"), 3.0f);
		ManaRefillParams.Set_RefillBehavior(ECk_Attribute_Refill_Policy::AlwaysReturnToZero);
		ManaRefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

		auto ManaParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Mana"), 80.0f);
		ManaParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(80.0f);
		ManaParams.Set_EnableRefill(true).Set_RefillParams(ManaRefillParams);

		ManaAttribute = utils_float_attribute::Add(InHandle, ManaParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnValueChanged(EnergyAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
		utils_float_attribute::BindTo_OnMinClamped(EnergyAttribute,
			FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMinClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(EnergyAttribute,
			FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMaxClamped"));

		utils_float_attribute::BindTo_OnValueChanged(ManaAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
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
			case 1: Request_DrainEnergy(); break;
			case 2: Request_WatchRefill(); break;
			case 3: Request_PauseRefill(); break;
			case 4: Request_DrainAgain(); break;
			case 5: Request_ResumeRefill(); break;
			case 6: Request_ResetEnergy(); break;
			default:
				CycleStep = 0;
				break;
		}
	}

	void
	Request_DrainEnergy()
	{
		utils_float_attribute::Request_Override(EnergyAttribute, 20.0f);
		utils_float_attribute::Request_Override(ManaAttribute, 15.0f);
	}

	void
	Request_WatchRefill()
	{
		// Do nothing - let the refill system work and display shows recovery
	}

	void
	Request_PauseRefill()
	{
		auto Refill = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute);
		if (ck::IsValid(Refill))
		{
			utils_float_attribute_refill::Request_Pause(Refill);
		}
	}

	void
	Request_DrainAgain()
	{
		utils_float_attribute::Request_Override(EnergyAttribute, 10.0f);
		utils_float_attribute::Request_Override(ManaAttribute, 5.0f);
	}

	void
	Request_ResumeRefill()
	{
		auto Refill = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute);
		if (ck::IsValid(Refill))
		{
			utils_float_attribute_refill::Request_Resume(Refill);
		}
	}

	void
	Request_ResetEnergy()
	{
		utils_float_attribute::Request_Override(EnergyAttribute, 100.0f);
		utils_float_attribute::Request_Override(ManaAttribute, 80.0f);

		auto Refill = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute);
		if (ck::IsValid(Refill))
		{
			utils_float_attribute_refill::Request_Resume(Refill);
		}

		auto ManaRefill = utils_float_attribute::TryGet_RefillAttribute(ManaAttribute);
		if (ck::IsValid(ManaRefill))
		{
			utils_float_attribute_refill::Request_Resume(ManaRefill);
		}
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT REFILL (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Cycle Step: {CycleStep}/6 | Changes: {ValueChangeCount}\n\n";

		// Energy (Variable policy)
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

		// Mana (AlwaysReturnToZero policy)
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

		DisplayText = f"{DisplayText}\nAUTOMATION: " + Get_CurrentPhaseText();

		auto Instructions = "Tests the float-exclusive refill system with two policies.\n"
			+ "Energy: Variable policy (refills positively toward max).\n"
			+ "Mana: AlwaysReturnToZero policy (always refills toward zero).\n"
			+ "Use Ck_GymFloat_ToggleRefill to manually pause/resume energy.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}

	FString
	Get_CurrentPhaseText()
	{
		switch (CycleStep)
		{
			case 0: return "Idle - Full Energy";
			case 1: return "Draining Energy to 20";
			case 2: return "Watching Refill";
			case 3: return "Pausing Refill";
			case 4: return "Draining Again to 10";
			case 5: return "Resuming Refill";
			case 6: return "Resetting to Full";
			default: return "Unknown Phase";
		}
	}

	UFUNCTION()
	void
	OnValueChanged(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnValueChanged InPayload)
	{
		ValueChangeCount++;
	}

	UFUNCTION()
	void
	OnMinClamped(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		auto SelfEntity = ck::ToEntity(this);
		CkGym_Attribute::Draw_ClampIndicator(SelfEntity, FVector(0.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
	}

	UFUNCTION()
	void
	OnMaxClamped(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		auto SelfEntity = ck::ToEntity(this);
		CkGym_Attribute::Draw_ClampIndicator(SelfEntity, FVector(0.0f, 0.0f, 150.0f), FLinearColor(0.0f, 1.0f, 0.0f, 1.0f));
	}

	UFUNCTION()
	private void
	OnToggleRefill(
		FCk_Handle InHandle,
		FGameplayTag InMessageName,
		FInstancedStruct InPayload)
	{
		auto Refill = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute);
		if (ck::IsValid(Refill))
		{
			auto RefillState = utils_float_attribute_refill::Get_RefillState(Refill);
			if (RefillState == ECk_Attribute_RefillState::Running)
			{
				utils_float_attribute_refill::Request_Pause(Refill);
			}
			else
			{
				utils_float_attribute_refill::Request_Resume(Refill);
			}
		}
	}

	UFUNCTION()
	private void
	OnResetAttributes(
		FCk_Handle InHandle,
		FGameplayTag InMessageName,
		FInstancedStruct InPayload)
	{
		CycleStep = 0;
		ValueChangeCount = 0;

		utils_float_attribute::Request_Override(EnergyAttribute, 100.0f);
		utils_float_attribute::Request_Override(ManaAttribute, 80.0f);

		auto Refill = utils_float_attribute::TryGet_RefillAttribute(EnergyAttribute);
		if (ck::IsValid(Refill))
		{
			utils_float_attribute_refill::Request_Resume(Refill);
		}

		auto ManaRefill = utils_float_attribute::TryGet_RefillAttribute(ManaAttribute);
		if (ck::IsValid(ManaRefill))
		{
			utils_float_attribute_refill::Request_Resume(ManaRefill);
		}
	}
}
