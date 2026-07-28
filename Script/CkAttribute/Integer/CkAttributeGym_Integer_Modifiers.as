//============================================================================
// INTEGER MODIFIERS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_Modifiers : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_IntegerAttribute DamageAttribute;
	TArray<FCk_Handle_IntegerAttributeModifier> ActiveModifiers;

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
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_Modifiers");

		// Display timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto timer
		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.5f));

		// Auto config
		AutoConfig.TotalSteps = 4;
		AutoConfig.Description = "Tests attribute modifier system with add/remove operations.\nDemonstrates weapon and buff modifier stacking.";
		AutoConfig.GlobalAutoCommand = "Ck_GymInteger_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymInteger_AutoModifiers";
		AutoConfig.Steps.Add(FCkGym_AutoStep("Add weapon bonus (+25)", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Add buff bonus (+10)", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Clear all modifiers", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("Re-add default modifiers", 3, 3));
		AutoConfig.ManualCommands.Add("Ck_GymInteger_AddWeaponBonus [value]");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_AddBuffBonus [value]");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_RemoveWeaponBonus");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_RemoveBuffBonus");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_ClearAllModifiers");

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void
	DoBeginPlay(
		FCk_Handle InHandle)
	{
		Request_SetupAttributes(InHandle);
		Request_BindSignals();
		Request_AddDefaultModifiers();

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_AddModifier,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddModifier"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_RemoveModifier,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveModifier"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_ClearModifiers,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnClearModifiers"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
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

	void Request_AddDefaultModifiers()
	{
		if (ck::Is_NOT_Valid(DamageAttribute))
			return;

		auto WeaponParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
		WeaponParams.Set_ModifierDelta(25);
		auto WeaponMod = utils_integer_attribute_modifier::Add_Revocable(
			DamageAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
			ECk_AttributeModifier_Operation::Add,
			WeaponParams);
		if (ck::IsValid(WeaponMod)) { ActiveModifiers.Add(WeaponMod); }

		auto BuffParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
		BuffParams.Set_ModifierDelta(10);
		auto BuffMod = utils_integer_attribute_modifier::Add_Revocable(
			DamageAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
			ECk_AttributeModifier_Operation::Add,
			BuffParams);
		if (ck::IsValid(BuffMod)) { ActiveModifiers.Add(BuffMod); }
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_UpdateDisplay();
	}

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Step = AutoStep % AutoConfig.TotalSteps;

		if (Step == 0) { Request_AddWeaponModifier(); }
		else if (Step == 1) { Request_AddBuffModifier(); }
		else if (Step == 2) { Request_ClearAllModifiers(); }
		else if (Step == 3) { Request_AddDefaultModifiers(); }

		AutoStep++;
	}

	UFUNCTION()
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
	}

	void Request_AddWeaponModifier()
	{
		if (ck::Is_NOT_Valid(DamageAttribute)) return;

		auto ExistingMod = utils_integer_attribute_modifier::TryGet(
			DamageAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
			ECk_MinMaxCurrent::Current);
		if (ck::IsValid(ExistingMod))
		{
			utils_integer_attribute_modifier::Remove(ExistingMod);
			ActiveModifiers.Remove(ExistingMod);
		}

		auto Params = FCk_Fragment_IntegerAttributeModifier_ParamsData();
		Params.Set_ModifierDelta(25);
		auto Mod = utils_integer_attribute_modifier::Add_Revocable(
			DamageAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
			ECk_AttributeModifier_Operation::Add,
			Params);
		if (ck::IsValid(Mod)) { ActiveModifiers.Add(Mod); }
	}

	void Request_AddBuffModifier()
	{
		if (ck::Is_NOT_Valid(DamageAttribute)) return;

		auto ExistingMod = utils_integer_attribute_modifier::TryGet(
			DamageAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
			ECk_MinMaxCurrent::Current);
		if (ck::IsValid(ExistingMod))
		{
			utils_integer_attribute_modifier::Remove(ExistingMod);
			ActiveModifiers.Remove(ExistingMod);
		}

		auto Params = FCk_Fragment_IntegerAttributeModifier_ParamsData();
		Params.Set_ModifierDelta(10);
		auto Mod = utils_integer_attribute_modifier::Add_Revocable(
			DamageAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
			ECk_AttributeModifier_Operation::Add,
			Params);
		if (ck::IsValid(Mod)) { ActiveModifiers.Add(Mod); }
	}

	void Request_ClearAllModifiers()
	{
		if (ck::Is_NOT_Valid(DamageAttribute)) return;
		utils_integer_attribute_modifier::Request_ClearAllModifiers(DamageAttribute, ECk_MinMaxCurrent::Current);
		ActiveModifiers.Empty();
	}

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "INTEGER MODIFIERS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		DisplayText = f"{DisplayText}Changes: {ValueChangeCount}\n\n";

		auto BaseValue = utils_integer_attribute::Get_BaseValue(DamageAttribute);
		auto BonusValue = utils_integer_attribute::Get_BonusValue(DamageAttribute);
		auto FinalValue = utils_integer_attribute::Get_FinalValue(DamageAttribute);

		DisplayText = f"{DisplayText}Damage: {BaseValue} + {BonusValue} = {FinalValue}\n\n";

		auto DamageBar = CkGym_Attribute::Create_ProgressBar(FinalValue, 200.0f, 20);
		DisplayText = f"{DisplayText}[{DamageBar}]\n\n";

		DisplayText = f"{DisplayText}MODIFIERS ({ActiveModifiers.Num()}):\n";
		auto ModifierCount = 0;
		auto Modifiers = utils_integer_attribute_modifier::ForEach(DamageAttribute, FInstancedStruct(), FCk_Lambda_InHandle());
		for (auto InModifier : Modifiers)
		{
			auto Delta = utils_integer_attribute_modifier::Get_Delta(InModifier);
			ModifierCount++;
			DisplayText = f"{DisplayText}  Mod {ModifierCount}: +{Delta}\n";
		}
		if (ModifierCount == 0) { DisplayText = f"{DisplayText}  No active modifiers\n"; }

		DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
	}

	UFUNCTION() void OnDamageChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload) { ValueChangeCount++; }

	UFUNCTION()
	private void OnAddModifier(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto TypedPayload = InPayload.Get(FCk_Message_IntegerGym_AddModifier);
		if (ck::Is_NOT_Valid(DamageAttribute)) return;

		auto ExistingMod = utils_integer_attribute_modifier::TryGet(DamageAttribute, TypedPayload.ModifierName, TypedPayload.Component);
		if (ck::IsValid(ExistingMod)) { utils_integer_attribute_modifier::Remove(ExistingMod); ActiveModifiers.Remove(ExistingMod); }

		auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
		ModParams.Set_ModifierDelta(TypedPayload.Delta);
		auto NewMod = utils_integer_attribute_modifier::Add_Revocable(DamageAttribute, TypedPayload.ModifierName, ECk_AttributeModifier_Operation::Add, ModParams);
		if (ck::IsValid(NewMod)) { ActiveModifiers.Add(NewMod); }
	}

	UFUNCTION()
	private void OnRemoveModifier(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto TypedPayload = InPayload.Get(FCk_Message_IntegerGym_RemoveModifier);
		if (ck::Is_NOT_Valid(DamageAttribute)) return;

		auto ModifierToRemove = utils_integer_attribute_modifier::TryGet(DamageAttribute, TypedPayload.ModifierName, TypedPayload.Component);
		if (ck::IsValid(ModifierToRemove)) { utils_integer_attribute_modifier::Remove(ModifierToRemove); ActiveModifiers.Remove(ModifierToRemove); }
	}

	UFUNCTION()
	private void OnClearModifiers(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		Request_ClearAllModifiers();
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		ValueChangeCount = 0;
		Request_ClearAllModifiers();
		Request_AddDefaultModifiers();

		AutoRunning = true;
		utils_timer::Request_Resume(AutoTimer);
	}
}
