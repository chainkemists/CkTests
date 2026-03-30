// Language=angelscript

//============================================================================
// INTEGER ATTRIBUTE GYM - COMPREHENSIVE TESTING
//============================================================================

//============================================================================
// SPAWN PARAMETERS
//============================================================================

USTRUCT()
struct FIntegerGymSpawnParams
{
	UPROPERTY()
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY()
	FString StationName = "";

	FIntegerGymSpawnParams(FTransform InTransform, FString InStationName = "")
	{
		InitialTransform = InTransform;
		StationName = InStationName;
	}
}

//============================================================================
// BASIC INTEGER ATTRIBUTES ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_Basic : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	FString StationName = "Basic";

	FCk_Handle_IntegerAttribute HealthAttribute;
	FCk_Handle_IntegerAttribute ArmorAttribute;
	FCk_Handle_IntegerAttribute ExperienceAttribute;

	int32 HealthChangeCount = 0;
	int32 ArmorChangeCount = 0;
	int32 ExperienceChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_Basic");

		// Display update timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Health: 0-100, starts at 100
		auto HealthParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Health"),
			100);

		HealthParams.Set_MinMax(ECk_MinMax::MinMax);
		HealthParams.Set_MinValue(0);
		HealthParams.Set_MaxValue(100);
		HealthAttribute = utils_integer_attribute::Add(InHandle, HealthParams);

		// Armor: 0-50, starts at 25
		auto ArmorParams = FCk_Fragment_IntegerAttribute_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Armor"),
																	25);
		ArmorParams.Set_MinMax(ECk_MinMax::MinMax);
		ArmorParams.Set_MinValue(0);
		ArmorParams.Set_MaxValue(50);
		ArmorAttribute = utils_integer_attribute::Add(InHandle, ArmorParams);

		// Experience: 0-unlimited, starts at 0
		auto ExperienceParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Experience"),
			0);
		ExperienceParams.Set_MinMax(ECk_MinMax::Min); // Only min clamping
		ExperienceParams.Set_MinValue(0);
		ExperienceAttribute = utils_integer_attribute::Add(InHandle, ExperienceParams);

		auto HealthDelegate = FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnHealthChanged");
		utils_integer_attribute::BindTo_OnValueChanged(
			HealthAttribute,
			ECk_MinMaxCurrent::Current,
			HealthDelegate);

		auto ArmorDelegate = FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnArmorChanged");
		utils_integer_attribute::BindTo_OnValueChanged(
			ArmorAttribute,
			ECk_MinMaxCurrent::Current,
			ArmorDelegate);

		auto ExperienceDelegate = FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnExperienceChanged");
		utils_integer_attribute::BindTo_OnValueChanged(
			ExperienceAttribute,
			ECk_MinMaxCurrent::Current,
			ExperienceDelegate);

		// Bind to messages
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_SetHealth, FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetHealth"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_SetArmor, FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetArmor"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_SetExperience, FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetExperience"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_ResetAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		DisplayStats();
	}

	void DisplayStats()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TransformHandle = SelfEntity.As_Transform();

		if (ck::Ensure(ck::IsValid(TransformHandle), "TransformHandle should be valid in gym") == false)
		{
			return;
		}

		auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);

		auto TitleText = "BASIC INTEGER ATTRIBUTES";
		auto DisplayText = "";

		DisplayText = f"{DisplayText}===== Value Tracking =====\n";
		DisplayText = f"{DisplayText}Health Changes: {HealthChangeCount}\n";
		DisplayText = f"{DisplayText}Armor Changes: {ArmorChangeCount}\n";
		DisplayText = f"{DisplayText}XP Changes: {ExperienceChangeCount}\n\n";

		if (ck::Ensure(ck::IsValid(HealthAttribute), "HealthAttribute should be valid in DisplayStats") == false)
		{
			return;
		}
		auto HealthValue = utils_integer_attribute::Get_FinalValue(HealthAttribute);
		auto HealthBar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(HealthValue / 100.0f), 20, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);
		DisplayText = f"{DisplayText}Health: {HealthValue}/100\n";
		DisplayText = f"{DisplayText}[{HealthBar}]\n\n";

		if (ck::Ensure(ck::IsValid(TransformHandle), "ArmorAttribute should be valid in DisplayStats") == false)
		{
			return;
		}

		auto ArmorValue = utils_integer_attribute::Get_FinalValue(ArmorAttribute);
		auto ArmorBar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(ArmorValue / 50.0f), 20, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
		DisplayText = f"{DisplayText}Armor: {ArmorValue}/50\n";
		DisplayText = f"{DisplayText}[{ArmorBar}]\n\n";

		if (ck::Ensure(ck::IsValid(ExperienceAttribute), "ExperienceAttribute should be valid in DisplayStats") == false)
		{
			return;
		}

		auto XPValue = utils_integer_attribute::Get_FinalValue(ExperienceAttribute);
		DisplayText = f"{DisplayText}Experience: {XPValue} (no max)\n\n";

		DisplayText = f"{DisplayText}===== Commands =====\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_SetHealth [value]\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_SetArmor [value]\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_SetExperience [value]";

		auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
		auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
		Fragment.Title = FText::FromString(TitleText);
		Fragment.Description = FText::FromString(DisplayText);
	}

	// Signal callbacks
	UFUNCTION()
	void OnHealthChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
	{
		HealthChangeCount++;
	}

	UFUNCTION()
	void OnArmorChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
	{
		ArmorChangeCount++;
	}

	UFUNCTION()
	void OnExperienceChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
	{
		ExperienceChangeCount++;
	}

	// Message handlers
	UFUNCTION()
	private void OnSetHealth(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		auto TypedPayload = InPayload.Get(FCk_Message_IntegerGym_SetHealth);
		if (ck::Ensure(ck::IsValid(HealthAttribute), "HealthAttribute should be valid when setting health") == false)
		{
			return;
		}

		utils_integer_attribute::Request_Override(HealthAttribute, TypedPayload.Value);
	}

	UFUNCTION()
	private void OnSetArmor(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		auto TypedPayload = InPayload.Get(FCk_Message_IntegerGym_SetArmor);
		if (ck::Ensure(ck::IsValid(ArmorAttribute), "ArmorAttribute should be valid when setting armor") == false)
		{
			return;
		}

		utils_integer_attribute::Request_Override(ArmorAttribute, TypedPayload.Value);
	}

	UFUNCTION()
	private void OnSetExperience(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		auto TypedPayload = InPayload.Get(FCk_Message_IntegerGym_SetExperience);
		if (ck::Ensure(ck::IsValid(ExperienceAttribute), "ExperienceAttribute should be valid when setting experience") == false)
		{
			return;
		}

		utils_integer_attribute::Request_Override(ExperienceAttribute, TypedPayload.Value);
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		HealthChangeCount = 0;
		ArmorChangeCount = 0;
		ExperienceChangeCount = 0;

		if (ck::Ensure(ck::IsValid(HealthAttribute), "HealthAttribute should be valid when resetting") == false)
		{
			return;
		}
		utils_integer_attribute::Request_Override(HealthAttribute, 100);

		if (ck::Ensure(ck::IsValid(ArmorAttribute), "ArmorAttribute should be valid when resetting") == false)
		{
			return;
		}
		utils_integer_attribute::Request_Override(ArmorAttribute, 25);

		if (ck::Ensure(ck::IsValid(ExperienceAttribute), "ExperienceAttribute should be valid when resetting") == false)
		{
			return;
		}
		utils_integer_attribute::Request_Override(ExperienceAttribute, 0);
	}
}

//============================================================================
// MIN/MAX/CURRENT COMPONENTS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_MinMaxCurrent : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	FString StationName = "MinMaxCurrent";

	FCk_Handle_IntegerAttribute PowerLevelAttribute;

	int32 MinChangeCount = 0;
	int32 MaxChangeCount = 0;
	int32 CurrentChangeCount = 0;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_MinMaxCurrent");

		// Display update timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void DoBeginPlay(FCk_Handle InHandle)
	{
		auto SelfEntity = InHandle;

		// Create a single attribute with all three components
		auto PowerParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.PowerLevel"),
			50						   // Current value
		);
		PowerParams.Set_MinMax(ECk_MinMax::MinMax);
		PowerParams.Set_MinValue(10);  // Min component
		PowerParams.Set_MaxValue(100); // Max component

		PowerLevelAttribute = utils_integer_attribute::Add(SelfEntity, PowerParams);

		// Bind to value changes for each component
		auto MinDelegate = FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnMinChanged");
		utils_integer_attribute::BindTo_OnValueChanged(
			PowerLevelAttribute,
			ECk_MinMaxCurrent::Min,
			MinDelegate);

		auto MaxDelegate = FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnMaxChanged");
		utils_integer_attribute::BindTo_OnValueChanged(
			PowerLevelAttribute,
			ECk_MinMaxCurrent::Max,
			MaxDelegate);

		auto CurrentDelegate = FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnCurrentChanged");
		utils_integer_attribute::BindTo_OnValueChanged(
			PowerLevelAttribute,
			ECk_MinMaxCurrent::Current,
			CurrentDelegate);

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_ResetAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		DisplayStats();
	}

	void DisplayStats()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TransformHandle = SelfEntity.As_Transform();

		auto TitleText = "MIN/MAX/CURRENT COMPONENTS";
		auto DisplayText = "";

		DisplayText = f"{DisplayText}===== Component Values =====\n";

		auto HasMin = utils_integer_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Min);
		auto HasMax = utils_integer_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Max);
		auto HasCurrent = utils_integer_attribute::Has_Component(PowerLevelAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}Components Present:\n";
		DisplayText = f"{DisplayText}  Min: " + (HasMin ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Max: " + (HasMax ? "YES" : "NO") + "\n";
		DisplayText = f"{DisplayText}  Current: " + (HasCurrent ? "YES" : "NO") + "\n\n";

		auto MinValue = utils_integer_attribute::Get_FinalValue(PowerLevelAttribute, ECk_MinMaxCurrent::Min);
		auto MaxValue = utils_integer_attribute::Get_FinalValue(PowerLevelAttribute, ECk_MinMaxCurrent::Max);
		auto CurrentValue = utils_integer_attribute::Get_FinalValue(PowerLevelAttribute, ECk_MinMaxCurrent::Current);

		DisplayText = f"{DisplayText}Power Level:\n";
		DisplayText = f"{DisplayText}  Min: {MinValue} (Changes: {MinChangeCount})\n";
		DisplayText = f"{DisplayText}  Max: {MaxValue} (Changes: {MaxChangeCount})\n";
		DisplayText = f"{DisplayText}  Current: {CurrentValue} (Changes: {CurrentChangeCount})\n\n";

		// Visual representation
		auto PowerBar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1((CurrentValue - MinValue) / float32(MaxValue - MinValue)), 20, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);
		DisplayText = f"{DisplayText}[{PowerBar}]\n";
		DisplayText = f"{DisplayText}  {MinValue} <--- {CurrentValue} ---> {MaxValue}\n\n";

		DisplayText = f"{DisplayText}===== Commands =====\n";
		DisplayText = f"{DisplayText}Override components individually\n";
		DisplayText = f"{DisplayText}through modifiers (next station)";

		auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
		auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
		Fragment.Title = FText::FromString(TitleText);
		Fragment.Description = FText::FromString(DisplayText);
	}

	UFUNCTION()
	void OnMinChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
	{
		MinChangeCount++;
	}

	UFUNCTION()
	void OnMaxChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
	{
		MaxChangeCount++;
	}

	UFUNCTION()
	void OnCurrentChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
	{
		CurrentChangeCount++;
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		MinChangeCount = 0;
		MaxChangeCount = 0;
		CurrentChangeCount = 0;

		utils_integer_attribute::Request_Override(PowerLevelAttribute, 50, ECk_MinMaxCurrent::Current);
		utils_integer_attribute::Request_Override(PowerLevelAttribute, 10, ECk_MinMaxCurrent::Min);
		utils_integer_attribute::Request_Override(PowerLevelAttribute, 100, ECk_MinMaxCurrent::Max);
	}
}

//============================================================================
// MODIFIERS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_Modifiers : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	FString StationName = "Modifiers";

	FCk_Handle_IntegerAttribute DamageAttribute;
	TArray<FCk_Handle_IntegerAttributeModifier> ActiveModifiers;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_Modifiers");

		// Display update timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void DoBeginPlay(FCk_Handle InHandle)
	{
		auto SelfEntity = InHandle;

		// Create damage attribute with base value
		auto DamageParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Damage"),
			100);
		DamageParams.Set_MinMax(ECk_MinMax::Min);
		DamageParams.Set_MinValue(0);

		DamageAttribute = utils_integer_attribute::Add(SelfEntity, DamageParams);

		// Bind to messages
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_AddModifier, FCk_Delegate_Messaging_OnBroadcast(this, n"OnAddModifier"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_RemoveModifier, FCk_Delegate_Messaging_OnBroadcast(this, n"OnRemoveModifier"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_ClearModifiers, FCk_Delegate_Messaging_OnBroadcast(this, n"OnClearModifiers"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_ResetAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));

		// Add some default modifiers
		Request_AddDefaultModifiers();
	}

	void Request_AddDefaultModifiers()
	{
		if (ck::Is_NOT_Valid(DamageAttribute))
		{
			return;
		}

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
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		DisplayStats();
	}

	void DisplayStats()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TransformHandle = SelfEntity.As_Transform();

		auto TitleText = "INTEGER ATTRIBUTE MODIFIERS";
		auto DisplayText = "";

		auto BaseValue = utils_integer_attribute::Get_BaseValue(DamageAttribute);
		auto BonusValue = utils_integer_attribute::Get_BonusValue(DamageAttribute);
		auto FinalValue = utils_integer_attribute::Get_FinalValue(DamageAttribute);

		DisplayText = f"{DisplayText}===== Damage Attribute =====\n";
		DisplayText = f"{DisplayText}Base Value: {BaseValue}\n";
		DisplayText = f"{DisplayText}Bonus Value: {BonusValue}\n";
		DisplayText = f"{DisplayText}Final Value: {FinalValue}\n\n";

		DisplayText = f"{DisplayText}===== Active Modifiers =====\n";

		// List all modifiers
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
		auto DamageBar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(FinalValue / 200.0f), 20, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);
		DisplayText = f"{DisplayText}[{DamageBar}]\n\n";

		DisplayText = f"{DisplayText}===== Commands =====\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_AddWeaponBonus [value]\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_AddBuffBonus [value]\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_RemoveWeaponBonus\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_RemoveBuffBonus\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_ClearAllModifiers";

		auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
		auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
		Fragment.Title = FText::FromString(TitleText);
		Fragment.Description = FText::FromString(DisplayText);
	}

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
		OnClearModifiers(InHandle, InMessageName, InPayload);
		Request_AddDefaultModifiers();
	}
}

//============================================================================
// CLAMPING & SIGNALS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_Clamping : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	UPROPERTY(ExposeOnSpawn)
	FString StationName = "Clamping";

	FCk_Handle_IntegerAttribute ResourceAttribute;

	int32 MinClampCount = 0;
	int32 MaxClampCount = 0;
	int32 LastInputValue = 50;

	// Auto-cycling test values
	int32 CurrentTestValue = 50;
	bool IsIncreasing = true;

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_Clamping");

		// Display update timer
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto-update timer
		auto UpdateTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(1.5f));
		UpdateTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto UpdateTimer = utils_timer::Add(InHandle, UpdateTimerParams);
		UpdateTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"UpdateTick"));

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void DoBeginPlay(FCk_Handle InHandle)
	{
		auto SelfEntity = InHandle;

		// Create clamped resource attribute
		auto ResourceParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Resource"),
			50);
		ResourceParams.Set_MinMax(ECk_MinMax::MinMax);
		ResourceParams.Set_MinValue(0);
		ResourceParams.Set_MaxValue(100);

		ResourceAttribute = utils_integer_attribute::Add(SelfEntity, ResourceParams);

		// Bind to clamping signals
		auto MinClampDelegate = FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMinClamped");
		utils_integer_attribute::BindTo_OnMinClamped(
			ResourceAttribute,
			MinClampDelegate);

		auto MaxClampDelegate = FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMaxClamped");
		utils_integer_attribute::BindTo_OnMaxClamped(
			ResourceAttribute,
			MaxClampDelegate);

		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_ResetAttributes, FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_TestBoundaries, FCk_Delegate_Messaging_OnBroadcast(this, n"OnTestBoundaries"));
	}

	UFUNCTION()
	private void UpdateTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		Request_AutoUpdateValue();
	}

	void Request_AutoUpdateValue()
	{
		if (ck::Is_NOT_Valid(ResourceAttribute))
			return;

		// Cycle value to test clamping
		if (IsIncreasing)
		{
			CurrentTestValue += 20;
			if (CurrentTestValue >= 120)
			{
				IsIncreasing = false;
			}
		}
		else
		{
			CurrentTestValue -= 25;
			if (CurrentTestValue <= -20)
			{
				IsIncreasing = true;
			}
		}

		LastInputValue = CurrentTestValue;
		utils_integer_attribute::Request_Override(ResourceAttribute, CurrentTestValue);
	}

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		DisplayStats();
	}

	void DisplayStats()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto TransformHandle = SelfEntity.As_Transform();

		auto TitleText = "INTEGER CLAMPING & SIGNALS";
		auto DisplayText = "";

		DisplayText = f"{DisplayText}===== Clamping Events =====\n";
		DisplayText = f"{DisplayText}Min Clamps: {MinClampCount}\n";
		DisplayText = f"{DisplayText}Max Clamps: {MaxClampCount}\n\n";

		auto ResourceValue = utils_integer_attribute::Get_FinalValue(ResourceAttribute);
		auto ClampStatus = "";

		if (ResourceValue == 0 && LastInputValue < 0)
		{
			ClampStatus = " [MIN CLAMPED]";
		}
		else if (ResourceValue == 100 && LastInputValue > 100)
		{
			ClampStatus = " [MAX CLAMPED]";
		}
		else
		{
			ClampStatus = " [NORMAL]";
		}

		DisplayText = f"{DisplayText}Resource: {ResourceValue}/100\n";
		DisplayText = f"{DisplayText}Input Value: {LastInputValue}\n";
		DisplayText = f"{DisplayText}Status: " + ClampStatus + "\n";
		DisplayText = f"{DisplayText}Direction: " + (IsIncreasing ? "INCREASING" : "DECREASING") + "\n\n";

		// Visual representation
		auto ResourceBar = utils_debug_draw::Create_ASCII_ProgressBar(
			FCk_FloatRange_0to1(ResourceValue / 100.0f), 20, ECk_ForwardReverse::Forward, ECk_ASCII_ProgressBar_Style::Equal_Symbol);
		DisplayText = f"{DisplayText}[{ResourceBar}]\n\n";

		DisplayText = f"{DisplayText}===== Commands =====\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_TestBoundaries\n";
		DisplayText = f"{DisplayText}Ck_GymInteger_ResetClamping";

		auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
		auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
		Fragment.Title = FText::FromString(TitleText);
		Fragment.Description = FText::FromString(DisplayText);
	}

	UFUNCTION()
	void OnMinClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnClamped InPayload)
	{
		MinClampCount++;

		auto SelfEntity = ck::ToEntity(this);
		auto TransformHandle = SelfEntity.As_Transform();
		auto Transform = utils_transform::Get_EntityCurrentTransform(TransformHandle);
		auto ClampPos = Transform.GetLocation() + FVector(-50.0f, 0.0f, 150.0f);
		utils_debug_draw::DrawDebugSphere(ClampPos, 30.0f, 8, FLinearColor(0.0f, 0.0f, 1.0f, 1.0f), 2.0f, 3.0f);
	}

	UFUNCTION()
	void OnMaxClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnClamped InPayload)
	{
		MaxClampCount++;

		auto SelfEntity = ck::ToEntity(this);
		if (SelfEntity.Is_Transform())
		{
			auto Transform = utils_transform::Get_EntityCurrentTransform(SelfEntity.As_Transform());
			auto ClampPos = Transform.GetLocation() + FVector(50.0f, 0.0f, 150.0f);
			utils_debug_draw::DrawDebugSphere(ClampPos, 30.0f, 8, FLinearColor(1.0f, 0.0f, 0.0f, 1.0f), 2.0f, 3.0f);
		}
	}

	UFUNCTION()
	private void OnTestBoundaries(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		if (ck::Is_NOT_Valid(ResourceAttribute))
			return;

		// Test extreme values
		utils_integer_attribute::Request_Override(ResourceAttribute, -50);
		utils_integer_attribute::Request_Override(ResourceAttribute, 150);

		auto SelfEntity = ck::ToEntity(this);
		if (SelfEntity.Is_Transform())
		{
			auto Transform = utils_transform::Get_EntityCurrentTransform(SelfEntity.As_Transform());
			auto TestPos = Transform.GetLocation() + FVector(0.0f, 0.0f, 250.0f);
			utils_debug_draw::DrawDebugString(TestPos, "TESTING BOUNDARIES!", FLinearColor(1.0f, 1.0f, 0.0f, 1.0f), 3.0f);
		}
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		MinClampCount = 0;
		MaxClampCount = 0;
		CurrentTestValue = 50;
		LastInputValue = 50;
		IsIncreasing = true;

		utils_integer_attribute::Request_Override(ResourceAttribute, 50);
	}
}
