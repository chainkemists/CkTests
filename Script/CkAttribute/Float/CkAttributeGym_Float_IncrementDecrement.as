//============================================================================
// FLOAT ATTRIBUTE INCREMENT/DECREMENT STATION
//============================================================================

class UCk_EntityScript_AttributeGym_FloatIncrementDecrement : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute CounterAttribute;
	TArray<FCk_Handle_FloatAttributeModifier> RevocableModifiers;

	int32 CycleStep = 0;
	int32 ValueChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatIncrementDecrement");

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

		auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.0f));
		AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
		AutoTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"AutoTick"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		// Counter: 0-50, starts at 25.0
		auto CounterParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Counter"), 25.0f);
		CounterParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(50.0f);
		CounterAttribute = utils_float_attribute::Add(InHandle, CounterParams);
	}

	void
	Request_BindSignals(
		FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnValueChanged(CounterAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
		utils_float_attribute::BindTo_OnMinClamped(CounterAttribute,
			FCk_Delegate_FloatAttribute_OnClamped(this, n"OnClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(CounterAttribute,
			FCk_Delegate_FloatAttribute_OnClamped(this, n"OnClamped"));
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
			case 1: Request_IncrementNotRevocable(); break;
			case 2: Request_IncrementNotRevocable(); break;
			case 3: Request_IncrementNotRevocable(); break;
			case 4: Request_IncrementRevocable(); break;
			case 5: Request_IncrementRevocable(); break;
			case 6: Request_DecrementNotRevocable(); break;
			case 7: Request_DecrementNotRevocable(); break;
			case 8: Request_RevokeAllRevocable(); break;
			case 9: Request_DecrementRevocable(); break;
			case 10: Request_DecrementRevocable(); break;
			case 11: Request_RevokeAllRevocable(); break;
			case 12: Request_ResetToDefault(); break;
			default:
				CycleStep = 0;
				break;
		}
	}

	void
	Request_IncrementNotRevocable()
	{
		CounterAttribute.IncrementNotRevocable();
	}

	void
	Request_IncrementRevocable()
	{
		auto Mod = CounterAttribute.IncrementRevocable();
		if (ck::IsValid(Mod))
		{
			RevocableModifiers.Add(Mod);
		}
	}

	void
	Request_DecrementNotRevocable()
	{
		CounterAttribute.DecrementNotRevocable();
	}

	void
	Request_DecrementRevocable()
	{
		auto Mod = CounterAttribute.DecrementRevocable();
		if (ck::IsValid(Mod))
		{
			RevocableModifiers.Add(Mod);
		}
	}

	void
	Request_RevokeAllRevocable()
	{
		for (auto Mod : RevocableModifiers)
		{
			if (ck::IsValid(Mod))
			{
				utils_float_attribute_modifier::Remove(Mod);
			}
		}
		RevocableModifiers.Empty();
	}

	void
	Request_ResetToDefault()
	{
		utils_float_attribute_modifier::Request_ClearAllModifiers(CounterAttribute, ECk_MinMaxCurrent::Current);
		RevocableModifiers.Empty();
		utils_float_attribute::Request_Override(CounterAttribute, 25.0f);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT INC/DEC (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Cycle Step: {CycleStep}/12 | Changes: {ValueChangeCount}\n\n";

		auto BaseValue = utils_float_attribute::Get_BaseValue(CounterAttribute);
		auto BonusValue = utils_float_attribute::Get_BonusValue(CounterAttribute);
		auto FinalValue = utils_float_attribute::Get_FinalValue(CounterAttribute);

		DisplayText = f"{DisplayText}Counter: {BaseValue} + {BonusValue} = {FinalValue}\n";
		DisplayText = f"{DisplayText}Range: 0 to 50\n\n";

		auto CounterBar = CkGym_Attribute::Create_ProgressBar(FinalValue, 50.0f, 25);
		DisplayText = f"{DisplayText}[{CounterBar}]\n\n";

		DisplayText = f"{DisplayText}Revocable Modifiers: {RevocableModifiers.Num()}\n";
		for (auto i = 0; i < RevocableModifiers.Num(); i++)
		{
			if (ck::IsValid(RevocableModifiers[i]))
			{
				auto Delta = utils_float_attribute_modifier::Get_Delta(RevocableModifiers[i]);
				auto Sign = (Delta >= 0.0f) ? "+" : "";
				DisplayText = f"{DisplayText}  [{i}] {Sign}{Delta}\n";
			}
		}

		DisplayText = f"{DisplayText}\nAUTOMATION: " + Get_CurrentPhaseText();

		auto Instructions = "Tests the float mixin increment/decrement helpers.\n"
			+ "IncrementNotRevocable: permanent +1.0 | IncrementRevocable: removable +1.0\n"
			+ "DecrementNotRevocable: permanent -1.0 | DecrementRevocable: removable -1.0\n"
			+ "Revoke steps remove all revocable modifiers, leaving permanent ones.";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}

	FString
	Get_CurrentPhaseText()
	{
		switch (CycleStep)
		{
			case 0: return "Idle - Base 25.0";
			case 1: return "IncrementNotRevocable (+1 permanent)";
			case 2: return "IncrementNotRevocable (+1 permanent)";
			case 3: return "IncrementNotRevocable (+1 permanent)";
			case 4: return "IncrementRevocable (+1 removable)";
			case 5: return "IncrementRevocable (+1 removable)";
			case 6: return "DecrementNotRevocable (-1 permanent)";
			case 7: return "DecrementNotRevocable (-1 permanent)";
			case 8: return "Revoking All Revocable Modifiers";
			case 9: return "DecrementRevocable (-1 removable)";
			case 10: return "DecrementRevocable (-1 removable)";
			case 11: return "Revoking All Revocable Modifiers";
			case 12: return "Resetting to Default";
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
	OnClamped(
		FCk_Handle InAttributeOwnerEntity,
		FCk_Payload_FloatAttribute_OnClamped InPayload)
	{
		auto SelfEntity = ck::ToEntity(this);
		CkGym_Attribute::Draw_ClampIndicator(SelfEntity, FVector(0.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.5f, 0.0f, 1.0f));
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

		utils_float_attribute_modifier::Request_ClearAllModifiers(CounterAttribute, ECk_MinMaxCurrent::Current);
		RevocableModifiers.Empty();
		utils_float_attribute::Request_Override(CounterAttribute, 25.0f);
	}
}
