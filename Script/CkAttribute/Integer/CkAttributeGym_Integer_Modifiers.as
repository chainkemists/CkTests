//============================================================================
// INTEGER MODIFIERS ENTITY SCRIPT
//============================================================================
//
// Demo sequence is a CkStateMachine graph (see
// CkAttributeGym_Integer_Modifiers_Steps.as), not an AutoStep counter. The
// station owns the SM; the step states own what each step DOES.
//
// The Ck_GymInteger_AutoModifiers console command still arrives as an
// FCk_Message_Gym_AutoSet broadcast - that transport is shared with every
// not-yet-migrated station - it just routes to an SM pause/resume now.
//============================================================================

class UCk_EntityScript_IntegerGym_Modifiers : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_IntegerAttribute DamageAttribute;

	FCk_Handle_StateMachine StepMachine;
	FCkGym_SmConfig StepConfig;
	int32 ValueChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_Modifiers");

		// Display timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Step sequence. AddDefaults is the initial state so the station opens
		// with both modifiers applied, matching what BeginPlay used to seed
		// before the first auto tick landed.
		StepMachine = gym_sm::Setup(InHandle, UCk_IntegerGym_Step_AddDefaults);

		StepConfig.Description = "Tests attribute modifier system with add/remove operations.\nDemonstrates weapon and buff modifier stacking.";
		StepConfig.GlobalAutoCommand = "Ck_GymInteger_Auto [0/1]";
		StepConfig.PerStationAutoCommand = "Ck_GymInteger_AutoModifiers";
		StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntegerGym_Step_AddDefaults, "Re-add default modifiers"));
		StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntegerGym_Step_AddWeapon,   "Add weapon bonus (+25)"));
		StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntegerGym_Step_AddBuff,     "Add buff bonus (+10)"));
		StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntegerGym_Step_ClearAll,    "Clear all modifiers"));
		StepConfig.ManualCommands.Add("Ck_GymInteger_AddWeaponBonus [value]");
		StepConfig.ManualCommands.Add("Ck_GymInteger_AddBuffBonus [value]");
		StepConfig.ManualCommands.Add("Ck_GymInteger_RemoveWeaponBonus");
		StepConfig.ManualCommands.Add("Ck_GymInteger_RemoveBuffBonus");
		StepConfig.ManualCommands.Add("Ck_GymInteger_ClearAllModifiers");

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void
	DoBeginPlay(
		FCk_Handle InHandle)
	{
		Request_SetupAttributes(InHandle);
		Request_BindSignals();

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_AddModifier,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddModifier"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_RemoveModifier,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveModifier"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_ClearModifiers,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnClearModifiers"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_Gym_AutoSet,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnAutoSet"));
	}

	void
	Request_SetupAttributes(
		FCk_Handle InHandle)
	{
		auto DamageParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Damage"),
			100);
		DamageParams.Set_MinMax(ECk_MinMax::Min);
		DamageParams.Set_MinValue(0);
		DamageAttribute = utils_integer_attribute::Add(InHandle, DamageParams);
	}

	void
	Request_BindSignals()
	{
		utils_integer_attribute::BindTo_OnValueChanged(DamageAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnDamageChanged"));
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		auto Typed = InPayload.Get(FCk_Message_Gym_AutoSet);
		gym_sm::Request_SetAutoRunning(StepMachine, Typed.Enabled);
	}

	void Request_ClearAllModifiers()
	{
		if (ck::Is_NOT_Valid(DamageAttribute)) return;
		utils_integer_attribute_modifier::Request_ClearAllModifiers(DamageAttribute, ECk_MinMaxCurrent::Current);
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = f"INTEGER MODIFIERS ({CkGym_Common::Get_NetworkRoleTitle(SelfEntity)})";
		auto DisplayText = gym_sm::FormatHeader(StepConfig, StepMachine);

		DisplayText = f"{DisplayText}Changes: {ValueChangeCount}\n\n";

		auto BaseValue = utils_integer_attribute::Get_BaseValue(DamageAttribute);
		auto BonusValue = utils_integer_attribute::Get_BonusValue(DamageAttribute);
		auto FinalValue = utils_integer_attribute::Get_FinalValue(DamageAttribute);

		DisplayText = f"{DisplayText}Damage: {BaseValue} + {BonusValue} = {FinalValue}\n\n";

		auto DamageBar = CkGym_Attribute::Create_ProgressBar(FinalValue, 200.0f, 20);
		DisplayText = f"{DisplayText}[{DamageBar}]\n\n";

		// Count from the live modifier list rather than a parallel bookkeeping
		// array - the old ActiveModifiers count and this loop's count could
		// disagree after a clear that only one of them saw.
		auto ModifierLines = "";
		auto ModifierCount = 0;
		auto Modifiers = utils_integer_attribute_modifier::ForEach(DamageAttribute, FInstancedStruct(), FCk_Lambda_InHandle());
		for (auto InModifier : Modifiers)
		{
			auto Delta = utils_integer_attribute_modifier::Get_Delta(InModifier);
			ModifierCount++;
			ModifierLines = f"{ModifierLines}  Mod {ModifierCount}: +{Delta}\n";
		}
		if (ModifierCount == 0) { ModifierLines = "  No active modifiers\n"; }

		DisplayText = f"{DisplayText}MODIFIERS ({ModifierCount}):\n{ModifierLines}";

		auto Trailer = gym_sm::FormatAutoAndCommands(StepConfig, StepMachine);
		DisplayText = f"{DisplayText}\n{Trailer}";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION() void OnDamageChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload) { ValueChangeCount++; }

	UFUNCTION()
	private void OnAddModifier(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_sm::Request_SetAutoRunning(StepMachine, false);
		auto TypedPayload = InPayload.Get(FCk_Message_IntegerGym_AddModifier);
		if (ck::Is_NOT_Valid(DamageAttribute)) return;

		auto ExistingMod = utils_integer_attribute_modifier::TryGet(DamageAttribute, TypedPayload.ModifierName, TypedPayload.Component);
		if (ck::IsValid(ExistingMod)) { utils_integer_attribute_modifier::Remove(ExistingMod); }

		auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
		ModParams.Set_ModifierDelta(TypedPayload.Delta);
		utils_integer_attribute_modifier::Add_Revocable(DamageAttribute, TypedPayload.ModifierName, ECk_AttributeModifier_Operation::Add, ModParams);
	}

	UFUNCTION()
	private void OnRemoveModifier(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_sm::Request_SetAutoRunning(StepMachine, false);
		auto TypedPayload = InPayload.Get(FCk_Message_IntegerGym_RemoveModifier);
		if (ck::Is_NOT_Valid(DamageAttribute)) return;

		auto ModifierToRemove = utils_integer_attribute_modifier::TryGet(DamageAttribute, TypedPayload.ModifierName, TypedPayload.Component);
		if (ck::IsValid(ModifierToRemove)) { utils_integer_attribute_modifier::Remove(ModifierToRemove); }
	}

	UFUNCTION()
	private void OnClearModifiers(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_sm::Request_SetAutoRunning(StepMachine, false);
		Request_ClearAllModifiers();
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		ValueChangeCount = 0;
		Request_ClearAllModifiers();

		// Re-entering AddDefaults re-applies both modifiers, so the reset does
		// not need its own copy of that logic.
		gym_sm::Request_GoToStep(StepMachine, UCk_IntegerGym_Step_AddDefaults);
		gym_sm::Request_SetAutoRunning(StepMachine, true);
	}
}
