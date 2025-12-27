//============================================================================
// BYTE ATTRIBUTE VALUE RETRIEVAL STATION
//============================================================================

class UCk_EntityScript_AttributeGym_ByteValues : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_ByteAttribute TestAttribute;
	TArray<FCk_Handle_ByteAttributeModifier> ActiveModifiers;

	int32 CycleStep = 0;
	int32 ValueChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_ByteValues");

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
		// Test attribute: Min=5, Max=180, Current=75
		auto TestParams = FCk_Fragment_ByteAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"Test.ValueRetrieval"), 75);
		TestParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(5).Set_MaxValue(180);
		TestAttribute = utils_byte_attribute::Add(InHandle, TestParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Min,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged"));

		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Max,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged"));

		utils_byte_attribute::BindTo_OnValueChanged(TestAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged"));
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
		auto WeaponParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
		WeaponParams.Set_ModifierDelta(20);

		auto WeaponMod = utils_byte_attribute_modifier::Add_Revocable(
			TestAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
			ECk_AttributeModifier_Operation::Add,
			WeaponParams);

		if (ck::IsValid(WeaponMod))
		{
			ActiveModifiers.Add(WeaponMod);
		}

		auto BuffParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
		BuffParams.Set_ModifierDelta(15);

		auto BuffMod = utils_byte_attribute_modifier::Add_Revocable(
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
		utils_byte_attribute::Request_Override(TestAttribute, 8, ECk_MinMaxCurrent::Min);
		utils_byte_attribute::Request_Override(TestAttribute, 200, ECk_MinMaxCurrent::Max);
		utils_byte_attribute::Request_Override(TestAttribute, 90, ECk_MinMaxCurrent::Current);
	}

	void
	Request_TestAllRetrievalMethods()
	{
		// Values retrieved in display update for real-time testing
	}

	void
	Request_AddMoreModifiers()
	{
		auto EnchantParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
		EnchantParams.Set_ModifierDelta(12);

		auto EnchantMod = utils_byte_attribute_modifier::Add_Revocable(
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
		utils_byte_attribute_modifier::Request_ClearAllModifiers(TestAttribute, ECk_MinMaxCurrent::Current);
		ActiveModifiers.Empty();
	}

	void
	Request_ResetComponents()
	{
		utils_byte_attribute::Request_Override(TestAttribute, 5, ECk_MinMaxCurrent::Min);
		utils_byte_attribute::Request_Override(TestAttribute, 180, ECk_MinMaxCurrent::Max);
		utils_byte_attribute::Request_Override(TestAttribute, 75, ECk_MinMaxCurrent::Current);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "BYTE VALUES (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Cycle Step: {CycleStep}/6 | Changes: {ValueChangeCount}\n\n";

		// Component-specific value retrieval
		auto MinBase = utils_byte_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Min);
		auto MaxBase = utils_byte_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Max);
		auto CurrentBase = utils_byte_attribute::Get_BaseValue(TestAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentBonus = utils_byte_attribute::Get_BonusValue(TestAttribute, ECk_MinMaxCurrent::Current);
		auto CurrentFinal = utils_byte_attribute::Get_FinalValue(TestAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}COMPONENT VALUES:\n";
		DisplayText = f"{DisplayText}  Min Base: {MinBase}\n";
		DisplayText = f"{DisplayText}  Max Base: {MaxBase}\n";
		DisplayText = f"{DisplayText}  Current Base: {CurrentBase}\n";
		DisplayText = f"{DisplayText}  Current Bonus: {CurrentBonus}\n";
		DisplayText = f"{DisplayText}  Current Final: {CurrentFinal}\n\n";

		// Calculation breakdown
		DisplayText = f"{DisplayText}CALCULATION:\n";
		DisplayText = f"{DisplayText}  {CurrentBase} + {CurrentBonus} = {CurrentFinal}\n\n";

		// Progress bar for current value within min-max range
		auto ProgressPercent = (CurrentFinal - MinBase) / float32(MaxBase - MinBase);
		auto ValueBar = CkGym_Attribute::Create_ProgressBar(ProgressPercent * 100, 100.0f, 25);
		DisplayText = f"{DisplayText}[{ValueBar}]\n";
		DisplayText = f"{DisplayText}  {MinBase} <--- {CurrentFinal} ---> {MaxBase}\n\n";

		// Active modifiers
		DisplayText = f"{DisplayText}MODIFIERS ({ActiveModifiers.Num()}):\n";
		for (auto i = 0; i < ActiveModifiers.Num(); i++)
		{
			auto Delta = utils_byte_attribute_modifier::Get_Delta(ActiveModifiers[i]);
			DisplayText = f"{DisplayText}  Mod {i+1}: +{Delta}\n";
		}

		if (ActiveModifiers.Num() == 0)
		{
			DisplayText = f"{DisplayText}  No active modifiers\n";
		}

		DisplayText = f"{DisplayText}\nAUTOMATION: " + Get_CurrentPhaseText();

		auto Instructions = "Tests all value retrieval methods across Min/Max/Current components.\n"
        + "Shows Base/Bonus/Final calculations with live modifiers.\n"
        + "Demonstrates component-specific queries and value change tracking.";

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
		FCk_Payload_ByteAttribute_OnValueChanged InPayload)
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

		utils_byte_attribute_modifier::Request_ClearAllModifiers(TestAttribute, ECk_MinMaxCurrent::Current);
		ActiveModifiers.Empty();

		utils_byte_attribute::Request_Override(TestAttribute, 5, ECk_MinMaxCurrent::Min);
		utils_byte_attribute::Request_Override(TestAttribute, 180, ECk_MinMaxCurrent::Max);
		utils_byte_attribute::Request_Override(TestAttribute, 75, ECk_MinMaxCurrent::Current);
	}
}