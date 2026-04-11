//============================================================================
// INTEGER MODIFIERS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_Modifiers : UCk_EntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	FCk_Handle_IntegerAttribute DamageAttribute;
	TArray<FCk_Handle_IntegerAttributeModifier> ActiveModifiers;

	// Automation cycle state
	int32 CycleStep = 0;
	int32 ValueChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow
	DoConstruct(
		FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_Modifiers");

		Request_SetupTimers(InHandle);
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
	Request_SetupTimers(
		FCk_Handle InHandle)
	{
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));
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

		// Add a weapon bonus
		auto WeaponParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
		WeaponParams.Set_ModifierDelta(25);
		auto WeaponMod = utils_integer_attribute_modifier::Add_Revocable(
			DamageAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
			ECk_AttributeModifier_Operation::Add,
			WeaponParams);
		if (ck::IsValid(WeaponMod))
		{
			ActiveModifiers.Add(WeaponMod);
		}

		// Add a buff modifier
		auto BuffParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
		BuffParams.Set_ModifierDelta(10);
		auto BuffMod = utils_integer_attribute_modifier::Add_Revocable(
			DamageAttribute,
			utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
			ECk_AttributeModifier_Operation::Add,
			BuffParams);
		if (ck::IsValid(BuffMod))
		{
			ActiveModifiers.Add(BuffMod);
		}
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

	void
	Request_UpdateDisplay()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TitleText = "INTEGER MODIFIERS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
		auto DisplayText = f"Changes: {ValueChangeCount}\n\n";

		auto BaseValue = utils_integer_attribute::Get_BaseValue(DamageAttribute);
		auto BonusValue = utils_integer_attribute::Get_BonusValue(DamageAttribute);
		auto FinalValue = utils_integer_attribute::Get_FinalValue(DamageAttribute);

		DisplayText = f"{DisplayText}===== Damage Attribute =====\n";
		DisplayText = f"{DisplayText}Base Value: {BaseValue}\n";
		DisplayText = f"{DisplayText}Bonus Value: {BonusValue}\n";
		DisplayText = f"{DisplayText}Final Value: {FinalValue}\n\n";

		DisplayText = f"{DisplayText}===== Active Modifiers =====\n";

		auto ModifierCount = 0;
		auto Modifiers = utils_integer_attribute_modifier::ForEach(DamageAttribute, FInstancedStruct(), FCk_Lambda_InHandle());

		for (auto InModifier : Modifiers)
		{
			auto Delta = utils_integer_attribute_modifier::Get_Delta(InModifier);
			ModifierCount++;
			DisplayText = f"{DisplayText}Modifier {ModifierCount}: +{Delta}\n";
		}

		if (ModifierCount == 0)
		{
			DisplayText = f"{DisplayText}No active modifiers\n";
		}
		DisplayText = f"{DisplayText}\n";

		// Visual representation
		auto DamageBar = CkGym_Attribute::Create_ProgressBar(FinalValue, 200.0f, 20);
		DisplayText = f"{DisplayText}[{DamageBar}]";

		auto Instructions = "Tests attribute modifier system with add/remove operations.\n"
			+ "Demonstrates weapon and buff modifier stacking.\n"
			+ "Commands: Ck_GymInteger_AddWeaponBonus/AddBuffBonus/RemoveWeaponBonus/RemoveBuffBonus/ClearAllModifiers";

		CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, Instructions);
	}

	// Signal callbacks
	UFUNCTION()
	void OnDamageChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
	{
		ValueChangeCount++;
	}

	// Message handlers
	UFUNCTION()
	private void OnAddModifier(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		auto TypedPayload = InPayload.Get(FCk_Message_IntegerGym_AddModifier);

		if (ck::Is_NOT_Valid(DamageAttribute))
			return;

		// Remove existing modifier with same name first
		auto ExistingMod = utils_integer_attribute_modifier::TryGet(
			DamageAttribute,
			TypedPayload.ModifierName,
			TypedPayload.Component);
		if (ck::IsValid(ExistingMod))
		{
			utils_integer_attribute_modifier::Remove(ExistingMod);
			ActiveModifiers.Remove(ExistingMod);
		}

		// Add new modifier
		auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
		ModParams.Set_ModifierDelta(TypedPayload.Delta);

		auto NewMod = utils_integer_attribute_modifier::Add_Revocable(
			DamageAttribute,
			TypedPayload.ModifierName,
			ECk_AttributeModifier_Operation::Add,
			ModParams);

		if (ck::IsValid(NewMod))
		{
			ActiveModifiers.Add(NewMod);
		}
	}

	UFUNCTION()
	private void OnRemoveModifier(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		auto TypedPayload = InPayload.Get(FCk_Message_IntegerGym_RemoveModifier);

		if (ck::Is_NOT_Valid(DamageAttribute))
			return;

		auto ModifierToRemove = utils_integer_attribute_modifier::TryGet(
			DamageAttribute,
			TypedPayload.ModifierName,
			TypedPayload.Component);

		if (ck::IsValid(ModifierToRemove))
		{
			utils_integer_attribute_modifier::Remove(ModifierToRemove);
			ActiveModifiers.Remove(ModifierToRemove);
		}
	}

	UFUNCTION()
	private void OnClearModifiers(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		if (ck::Is_NOT_Valid(DamageAttribute))
			return;

		utils_integer_attribute_modifier::Request_ClearAllModifiers(DamageAttribute);
		ActiveModifiers.Empty();
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		ValueChangeCount = 0;
		OnClearModifiers(InHandle, InMessageName, InPayload);
		Request_AddDefaultModifiers();
	}
}
