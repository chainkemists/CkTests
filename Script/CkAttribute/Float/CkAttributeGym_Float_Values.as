//============================================================================
// FLOAT ATTRIBUTE VALUE RETRIEVAL STATION
//============================================================================

class UCk_EntityScript_AttributeGym_FloatValues : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute TestAttribute;
	TArray<FCk_Handle_FloatAttributeModifier> ActiveModifiers;

	int32 CycleStep = 0;
	int32 ValueChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatValues");

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

		auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.8f));
		AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
		AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"AutoTick"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto TestParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Test"), 75.5f);
		TestParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(5.0f).Set_MaxValue(180.0f);
		TestAttribute = utils_float_attribute::Add(InHandle, TestParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Min,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));

		utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Max,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));

		utils_float_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
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
			case 1: Request_AddModifiers(); break;
			case 2: Request_ModifyComponents(); break;
			case 3: Request_TestAllRetrievalMethods(); break;
			case 4: Request_AddMoreModifiers(); break;
			case 5: Request_ClearModifiers(); break;
			case 6: Request_ResetComponents(); break;
			default:
				CycleStep = 0;
				break;
		}
	}

	void
	Request_AddModifiers()
	{
		auto WeaponParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
		WeaponParams.Set_ModifierDelta(20.5f);

		auto WeaponMod = utils_float_attribute_modifier::Add_Revocable(
			TestAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
			ECk_AttributeModifier_Operation::Add,
			WeaponParams);

		if (ck::IsValid(WeaponMod))
		{
			ActiveModifiers.Add(WeaponMod);
		}

		auto BuffParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
		BuffParams.Set_ModifierDelta(15.25f);

		auto BuffMod = utils_float_attribute_modifier::Add_Revocable(
			TestAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
			ECk_AttributeModifier_Operation::Add,
			BuffParams);

		if (ck::IsValid(BuffMod))
		{
			ActiveModifiers.Add(BuffMod);
		}
	}

	void
	Request_ModifyComponents()
	{
		utils_float_attribute::Request_Override(TestAttribute, 8.0f, ECk_MinMaxCurrent::Min);
		utils_float_attribute::Request_Override(TestAttribute, 200.0f, ECk_MinMaxCurrent::Max);
		utils_float_attribute::Request_Override(TestAttribute, 90.5f, ECk_MinMaxCurrent::Current);
	}

	void
	Request_TestAllRetrievalMethods()
	{
		// Values retrieved in display update for real-time testing
	}

	void
	Request_AddMoreModifiers()
	{
		auto EnchantParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
		EnchantParams.Set_ModifierDelta(12.75f);

		auto EnchantMod = utils_float_attribute_modifier::Add_Revocable(
			TestAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Enchant"),
			ECk_AttributeModifier_Operation::Add,
			EnchantParams);

		if (ck::IsValid(EnchantMod))
		{
			ActiveModifiers.Add(EnchantMod);
		}
	}

	void
	Request_ClearModifiers()
	{
		utils_float_attribute_modifier::Request_ClearAllModifiers(TestAttribute, ECk_MinMaxCurrent::Current);
		ActiveModifiers.Empty();
	}

	void
	Request_ResetComponents()
	{
		utils_float_attribute::Request_Override(TestAttribute, 5.0f, ECk_MinMaxCurrent::Min);
		utils_float_attribute::Request_Override(TestAttribute, 180.0f, ECk_MinMaxCurrent::Max);
		utils_float_attribute::Request_Override(TestAttribute, 75.5f, ECk_MinMaxCurrent::Current);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT VALUES (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Cycle Step: {CycleStep}/6 | Changes: {ValueChangeCount}\n\n";

		auto MinBase = utils_float_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Min);
		auto MaxBase = utils_float_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Max);
		auto CurrentBase = utils_float_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentBonus = utils_float_attribute::Get_BonusValue(TestAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentFinal = utils_float_attribute::Get_FinalValue(TestAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}COMPONENT VALUES:\n";
		DisplayText = f"{DisplayText}  Min Base: {MinBase}\n";
		DisplayText = f"{DisplayText}  Max Base: {MaxBase}\n";
		DisplayText = f"{DisplayText}  Current Base: {CurrentBase}\n";
		DisplayText = f"{DisplayText}  Current Bonus: {CurrentBonus}\n";
		DisplayText = f"{DisplayText}  Current Final: {CurrentFinal}\n\n";

		DisplayText = f"{DisplayText}CALCULATION:\n";
		DisplayText = f"{DisplayText}  {CurrentBase} + {CurrentBonus} = {CurrentFinal}\n\n";

		// Float-specific: percentage and magnitude (exercise both overloads)
		auto PercentByHandle = utils_float_attribute::Get_Value_AsPercentage(TestAttribute);
		auto TestTag = utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Test");
		auto PercentByName = utils_float_attribute::Get_Value_AsPercentage(SelfEntity, TestTag);
		auto Magnitude = utils_float_attribute::Calculate_Attribute_Magnitude(TestAttribute);
		DisplayText = f"{DisplayText}FLOAT-SPECIFIC:\n";
		DisplayText = f"{DisplayText}  Percentage (by handle): {PercentByHandle * 100.0f}%\n";
		DisplayText = f"{DisplayText}  Percentage (by name):   {PercentByName * 100.0f}%\n";
		DisplayText = f"{DisplayText}  Magnitude (Max-Min): {Magnitude}\n\n";

		// Progress bar
		auto MinFinal = utils_float_attribute::Get_FinalValue(TestAttribute, ECk_MinMaxCurrent::Min);
		auto MaxFinal = utils_float_attribute::Get_FinalValue(TestAttribute, ECk_MinMaxCurrent::Max);
		auto ProgressPercent = (CurrentFinal - MinFinal) / (MaxFinal - MinFinal);
		auto ValueBar = CkGym_Attribute::Create_ProgressBar(ProgressPercent * 100.0f, 100.0f, 25);
		DisplayText = f"{DisplayText}[{ValueBar}]\n";
		DisplayText = f"{DisplayText}  {MinFinal} <--- {CurrentFinal} ---> {MaxFinal}\n\n";

		// Active modifiers
		DisplayText = f"{DisplayText}MODIFIERS ({ActiveModifiers.Num()}):\n";
		for (auto i = 0; i < ActiveModifiers.Num(); i++)
		{
			auto Delta = utils_float_attribute_modifier::Get_Delta(ActiveModifiers[i]);
			DisplayText = f"{DisplayText}  Mod {i+1}: +{Delta}\n";
		}

		if (ActiveModifiers.Num() == 0)
		{
			DisplayText = f"{DisplayText}  No active modifiers\n";
		}

		DisplayText = f"{DisplayText}\nAUTOMATION: " + Get_CurrentPhaseText();

		auto Instructions = "Tests all value retrieval methods across Min/Max/Current components.\n"
        + "Shows Base/Bonus/Final calculations with live modifiers.\n"
        + "Demonstrates float-specific: Get_Value_AsPercentage, Calculate_Attribute_Magnitude.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}

	FString
	Get_CurrentPhaseText()
	{
		switch (CycleStep)
		{
			case 0: return "Idle - Base Setup Complete";
			case 1: return "Adding Base Modifiers";
			case 2: return "Modifying Components";
			case 3: return "Testing All Retrieval Methods";
			case 4: return "Adding More Modifiers";
			case 5: return "Clearing All Modifiers";
			case 6: return "Resetting Components";
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
	private void
	OnResetAttributes(
		FCk_Handle InHandle,
		FGameplayTag InMessageName,
		FInstancedStruct InPayload)
	{
		CycleStep = 0;
		ValueChangeCount = 0;

		utils_float_attribute_modifier::Request_ClearAllModifiers(TestAttribute, ECk_MinMaxCurrent::Current);
		ActiveModifiers.Empty();

		utils_float_attribute::Request_Override(TestAttribute, 5.0f, ECk_MinMaxCurrent::Min);
		utils_float_attribute::Request_Override(TestAttribute, 180.0f, ECk_MinMaxCurrent::Max);
		utils_float_attribute::Request_Override(TestAttribute, 75.5f, ECk_MinMaxCurrent::Current);
	}
}
