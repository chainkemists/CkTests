//============================================================================
// INTEGER BASIC ATTRIBUTES ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_IntegerGym_Basic : UCk_GenericEntityScript_UE
{
	default _Replication = ECk_Replication::DoesNotReplicate;

	UPROPERTY(ExposeOnSpawn)
	FTransform InitialTransform = FTransform::Identity;

	// Attribute handles
	FCk_Handle_IntegerAttribute HealthAttribute;
	FCk_Handle_IntegerAttribute ArmorAttribute;
	FCk_Handle_IntegerAttribute ExperienceAttribute;

	// Auto mode
	FCk_Handle_Timer AutoTimer;
	bool AutoRunning = true;
	int32 AutoStep = 0;
	FCkGym_AutoConfig AutoConfig;

	// Signal counters
	int32 HealthChangeCount = 0;
	int32 ArmorChangeCount = 0;
	int32 ExperienceChangeCount = 0;

	//------------------------------------------------------------------------
	// Construction & Initialization
	//------------------------------------------------------------------------

	UFUNCTION(BlueprintOverride)
	ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
	{
		utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
		utils_entity_tag::Add(InHandle, n"TAG_IntegerGym_Basic");

		// Display timer (every frame)
		auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
		DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
		auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
		DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

		// Auto timer (2s cycle)
		AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.0f));

		// Auto config
		AutoConfig.TotalSteps = 6;
		AutoConfig.Description = "Tests integer attributes: Health (0-100), Armor (0-50), Experience (0+).";
		AutoConfig.GlobalAutoCommand = "Ck_GymInteger_Auto [0/1]";
		AutoConfig.PerStationAutoCommand = "Ck_GymInteger_AutoBasic";
		AutoConfig.Steps.Add(FCkGym_AutoStep("SetHealth 50, SetArmor 25, SetExperience 500", 0, 0));
		AutoConfig.Steps.Add(FCkGym_AutoStep("SetHealth 95, SetArmor 45, SetExperience 2000", 1, 1));
		AutoConfig.Steps.Add(FCkGym_AutoStep("TestBoundaries (push past max)", 2, 2));
		AutoConfig.Steps.Add(FCkGym_AutoStep("SetHealth 10, SetArmor 5, SetExperience 100", 3, 3));
		AutoConfig.Steps.Add(FCkGym_AutoStep("SetHealth -10, SetArmor -5 (push past min)", 4, 4));
		AutoConfig.Steps.Add(FCkGym_AutoStep("ResetToDefaults", 5, 5));
		AutoConfig.ManualCommands.Add("Ck_GymInteger_SetHealth [value]");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_SetArmor [value]");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_SetExperience [value]");
		AutoConfig.ManualCommands.Add("Ck_GymInteger_ResetAll");

		return ECk_EntityScript_ConstructionFlow::Finished;
	}

	UFUNCTION(BlueprintOverride)
	void DoBeginPlay(FCk_Handle InHandle)
	{
		Request_SetupAttributes(InHandle);
		Request_BindSignals();
		Request_BindMessages(InHandle);
	}

	void Request_SetupAttributes(FCk_Handle InHandle)
	{
		// Health: 0-100, starts at 100
		auto HealthParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Health"),
			100);
		HealthParams.Set_MinMax(ECk_MinMax::MinMax);
		HealthParams.Set_MinValue(0);
		HealthParams.Set_MaxValue(100);
		HealthAttribute = utils_integer_attribute::Add(InHandle, HealthParams);

		// Armor: 0-50, starts at 25
		auto ArmorParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Armor"),
			25);
		ArmorParams.Set_MinMax(ECk_MinMax::MinMax);
		ArmorParams.Set_MinValue(0);
		ArmorParams.Set_MaxValue(50);
		ArmorAttribute = utils_integer_attribute::Add(InHandle, ArmorParams);

		// Experience: 0-unlimited, starts at 0
		auto ExperienceParams = FCk_Fragment_IntegerAttribute_ParamsData(
			utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Experience"),
			0);
		ExperienceParams.Set_MinMax(ECk_MinMax::Min);
		ExperienceParams.Set_MinValue(0);
		ExperienceAttribute = utils_integer_attribute::Add(InHandle, ExperienceParams);
	}

	void Request_BindSignals()
	{
		utils_integer_attribute::BindTo_OnValueChanged(HealthAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnHealthChanged"));
		utils_integer_attribute::BindTo_OnValueChanged(ArmorAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnArmorChanged"));
		utils_integer_attribute::BindTo_OnValueChanged(ExperienceAttribute, ECk_MinMaxCurrent::Current,
			FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnExperienceChanged"));
	}

	void Request_BindMessages(FCk_Handle InHandle)
	{
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_SetHealth,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetHealth"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_SetArmor,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetArmor"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_IntegerGym_SetExperience,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetExperience"));
		utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
			FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
	}

	//------------------------------------------------------------------------
	// Signal Callbacks
	//------------------------------------------------------------------------

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

	//------------------------------------------------------------------------
	// Message Handlers
	//------------------------------------------------------------------------

	UFUNCTION()
	private void OnSetHealth(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Typed = InPayload.Get(FCk_Message_IntegerGym_SetHealth);
		utils_integer_attribute::Request_Override(HealthAttribute, Typed.Value);
	}

	UFUNCTION()
	private void OnSetArmor(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Typed = InPayload.Get(FCk_Message_IntegerGym_SetArmor);
		utils_integer_attribute::Request_Override(ArmorAttribute, Typed.Value);
	}

	UFUNCTION()
	private void OnSetExperience(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::StopAuto(AutoTimer, AutoRunning);
		auto Typed = InPayload.Get(FCk_Message_IntegerGym_SetExperience);
		utils_integer_attribute::Request_Override(ExperienceAttribute, Typed.Value);
	}

	UFUNCTION()
	private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		AutoStep = 0;
		HealthChangeCount = 0;
		ArmorChangeCount = 0;
		ExperienceChangeCount = 0;

		Request_ResetToDefaults();

		// Restart auto mode
		AutoRunning = true;
		utils_timer::Request_Resume(AutoTimer);
	}

	UFUNCTION()
	private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
	{
		gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
	}

	//------------------------------------------------------------------------
	// Auto Mode
	//------------------------------------------------------------------------

	UFUNCTION()
	private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		auto Step = AutoStep % AutoConfig.TotalSteps;
		AutoStep++;

		switch (Step)
		{
			case 0: // SetHealth 50, SetArmor 25, SetExperience 500
				Request_SetAllValues(50, 25, 500);
				break;

			case 1: // SetHealth 95, SetArmor 45, SetExperience 2000
				Request_SetAllValues(95, 45, 2000);
				break;

			case 2: // TestBoundaries — push past max
				Request_TestBoundariesMax();
				break;

			case 3: // SetHealth 10, SetArmor 5, SetExperience 100
				Request_SetAllValues(10, 5, 100);
				break;

			case 4: // Push past min — Health -10 (clamps to 0), Armor -5 (clamps to 0)
				Request_SetAllValues(-10, -5, -50);
				break;

			case 5: // Reset to defaults
				Request_ResetToDefaults();
				break;
		}
	}

	// Shared operations used by both auto steps and manual message handlers
	void Request_SetAllValues(int32 InHealth, int32 InArmor, int32 InExperience)
	{
		utils_integer_attribute::Request_Override(HealthAttribute, InHealth);
		utils_integer_attribute::Request_Override(ArmorAttribute, InArmor);
		utils_integer_attribute::Request_Override(ExperienceAttribute, InExperience);
	}

	void Request_TestBoundariesMax()
	{
		utils_integer_attribute::Request_Override(HealthAttribute, 120);
		utils_integer_attribute::Request_Override(ArmorAttribute, 60);
		utils_integer_attribute::Request_Override(ExperienceAttribute, 99999);
	}

	void Request_ResetToDefaults()
	{
		if (ck::IsValid(HealthAttribute))
		{
			utils_integer_attribute::Request_Override(HealthAttribute, 100);
		}
		if (ck::IsValid(ArmorAttribute))
		{
			utils_integer_attribute::Request_Override(ArmorAttribute, 25);
		}
		if (ck::IsValid(ExperienceAttribute))
		{
			utils_integer_attribute::Request_Override(ExperienceAttribute, 0);
		}
	}

	//------------------------------------------------------------------------
	// Display
	//------------------------------------------------------------------------

	UFUNCTION()
	private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
	{
		DisplayCurrentValues();
	}

	void DisplayCurrentValues()
	{
		auto SelfEntity = ck::ToEntity(this);
		auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);
		auto TitleText = "INTEGER BASIC (" + NetworkRole + ")";

		auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

		// Attribute values
		DisplayText = DisplayText + "===== Attribute Values =====\n";

		auto HealthValue = utils_integer_attribute::Get_FinalValue(HealthAttribute);
		auto HealthBar = CkGym_Attribute::Create_ProgressBar(HealthValue, 100.0f, 20);
		DisplayText = f"{DisplayText}Health: {HealthValue}/100\n";
		DisplayText = f"{DisplayText}[{HealthBar}]\n\n";

		auto ArmorValue = utils_integer_attribute::Get_FinalValue(ArmorAttribute);
		auto ArmorBar = CkGym_Attribute::Create_ProgressBar(ArmorValue, 50.0f, 20, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
		DisplayText = f"{DisplayText}Armor: {ArmorValue}/50\n";
		DisplayText = f"{DisplayText}[{ArmorBar}]\n\n";

		auto XPValue = utils_integer_attribute::Get_FinalValue(ExperienceAttribute);
		DisplayText = f"{DisplayText}Experience: {XPValue} (no max)\n\n";

		auto TotalChanges = HealthChangeCount + ArmorChangeCount + ExperienceChangeCount;
		DisplayText = f"{DisplayText}Changes: {TotalChanges} (H:{HealthChangeCount} A:{ArmorChangeCount} XP:{ExperienceChangeCount})\n";

		DisplayText = DisplayText + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

		auto Owner = utils_entity_lifetime::Get_LifetimeOwner(SelfEntity);
		auto& Fragment = Owner.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
		Fragment.Title = FText::FromString(TitleText);
		Fragment.Description = FText::FromString(DisplayText);
	}
}
