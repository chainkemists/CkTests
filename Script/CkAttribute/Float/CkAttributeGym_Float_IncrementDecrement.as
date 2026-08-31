//============================================================================
// FLOAT ATTRIBUTE INCREMENT/DECREMENT STATION
//============================================================================

class UCk_EntityScript_AttributeGym_FloatIncrementDecrement : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_FloatAttribute CounterAttribute;
	TArray<FCk_Handle_FloatAttributeModifier> RevocableModifiers;

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
		utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatIncrementDecrement");

		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.0f));

		AutoConfig.TotalSteps = 12;
		AutoConfig.Description = "Tests the float mixin increment/decrement helpers.\nRevocable vs non-revocable +1/-1 operations.";
		AutoConfig.GlobalAutoCommand = "panel [T] Auto-cycle all stations";
		AutoConfig.PerStationAutoCommand = "panel [7] Inc/Dec station auto";
		AutoConfig.Steps.Add(FCkGym_AutoStep("IncrementNotRevocable (x3)", 0, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("IncrementRevocable (x2)", 3, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("DecrementNotRevocable (x2)", 5, 6));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Revoke all revocable", 7, 7));
		AutoConfig.Steps.Add(FCkGym_AutoStep("DecrementRevocable (x2)", 8, 9));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Revoke all revocable", 10, 10));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Reset to default", 11, 11));
		AutoConfig.ManualCommands.Add("panel [N] Inc/Dec ring - increment / decrement / revoke all");

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
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_Increment,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualIncrement"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_Decrement,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualDecrement"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_RevokeAll,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualRevokeAll"));
	}

	void Request_SetupAttributes(FCk_Handle InHandle)
	{
		auto CounterParams = FCk_Fragment_FloatAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Counter"), 25.0f);
		CounterParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(50.0f);
		CounterAttribute = utils_float_attribute::Add(InHandle, CounterParams);
	}

	void Request_BindSignals(FCk_Handle InHandle)
	{
		utils_float_attribute::BindTo_OnValueChanged(CounterAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));
		utils_float_attribute::BindTo_OnMinClamped(CounterAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnClamped"));
		utils_float_attribute::BindTo_OnMaxClamped(CounterAttribute, FCk_Delegate_FloatAttribute_OnClamped(this, n"OnClamped"));
	}

	UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { Request_UpdateDisplay(); }

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Step = AutoStep % AutoConfig.TotalSteps;

		if (Step >= 0 && Step <= 2) { CounterAttribute.IncrementNotRevocable(); }
		else if (Step >= 3 && Step <= 4)
		{
			auto Mod = CounterAttribute.IncrementRevocable();
			if (ck::IsValid(Mod)) { RevocableModifiers.Add(Mod); }
		}
		else if (Step >= 5 && Step <= 6) { CounterAttribute.DecrementNotRevocable(); }
		else if (Step == 7) { Request_RevokeAllRevocable(); }
		else if (Step >= 8 && Step <= 9)
		{
			auto Mod = CounterAttribute.DecrementRevocable();
			if (ck::IsValid(Mod)) { RevocableModifiers.Add(Mod); }
		}
		else if (Step == 10) { Request_RevokeAllRevocable(); }
		else if (Step == 11) { Request_ResetToDefault(); }

		AutoStep++;
	}

	UFUNCTION()
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
	}

	void Request_RevokeAllRevocable()
	{
		for (auto Mod : RevocableModifiers)
		{
			if (ck::IsValid(Mod)) { utils_float_attribute_modifier::Remove(Mod); }
		}
		RevocableModifiers.Empty();
	}

	void Request_ResetToDefault()
	{
		utils_float_attribute_modifier::Request_ClearAllModifiers(CounterAttribute, ECk_MinMaxCurrent::Current);
		RevocableModifiers.Empty();
		utils_float_attribute::Request_Override(CounterAttribute, 25.0f, ECk_MinMaxCurrent::Current);
	}

	void Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "FLOAT INC/DEC (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Changes: {ValueChangeCount}\n\n";

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

		DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);
		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION()
	private void OnManualIncrement(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Mod = CounterAttribute.IncrementRevocable();
		if (ck::IsValid(Mod)) { RevocableModifiers.Add(Mod); }
	}

	UFUNCTION()
	private void OnManualDecrement(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Mod = CounterAttribute.DecrementRevocable();
		if (ck::IsValid(Mod)) { RevocableModifiers.Add(Mod); }
	}

	UFUNCTION()
	private void OnManualRevokeAll(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		Request_RevokeAllRevocable();
	}

	UFUNCTION() void OnValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
	UFUNCTION() void OnClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload) { CkGym_Attribute::Draw_ClampIndicator(ck::ToEntity(this), FVector(0.0f, 0.0f, 150.0f), FLinearColor(1.0f, 0.5f, 0.0f, 1.0f)); }

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		ValueChangeCount = 0;
		utils_float_attribute_modifier::Request_ClearAllModifiers(CounterAttribute, ECk_MinMaxCurrent::Current);
		RevocableModifiers.Empty();
		utils_float_attribute::Request_Override(CounterAttribute, 25.0f, ECk_MinMaxCurrent::Current);
	}
}
