//============================================================================
// BYTE MODIFIERS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_AttributeGym_ByteModifiers : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_ByteAttribute DamageAttribute;
    FCk_Handle_ByteAttribute DefenseAttribute;
    TArray<FCk_Handle_ByteAttributeModifier> ActiveModifiers;

    FCk_Handle_Timer AutoTimer;
    bool AutoRunning = true;
    int32 AutoStep = 0;
    FCkGym_AutoConfig AutoConfig;
    int32 ValueChangeCount = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_ByteModifiers");

        // Display timer
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        // Auto timer
        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.5f));

        // Auto config
        AutoConfig.TotalSteps = 8;
        AutoConfig.Description = "Cycles through modifier operations: add/remove/modify/clear.\nDemonstrates revocable and non-revocable modifier patterns.";
        AutoConfig.GlobalAutoCommand = "panel [T] Auto-cycle all stations";
        AutoConfig.PerStationAutoCommand = "panel [2] Modifiers station auto";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add weapon modifier", 0, 0));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add armor modifier", 1, 1));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add buff modifier", 2, 2));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add multiple modifiers", 3, 3));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Remove weapon modifier", 4, 4));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Modify existing buff", 5, 5));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Clear all modifiers", 6, 6));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add non-revocable modifier", 7, 7));
        AutoConfig.ManualCommands.Add("panel [G] Add modifier · [N] Clear modifiers");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        Request_SetupAttributes(InHandle);
        Request_BindSignals(InHandle);
        Request_StartAutomationCycle();

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ByteGym_AddModifier,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualAddModifier"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ByteGym_ClearModifiers,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualClearModifiers"));
    }

    void Request_SetupAttributes(FCk_Handle InHandle)
    {
        auto DamageParams = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Damage"), 50);
        DamageParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(10).Set_MaxValue(200);
        DamageAttribute = utils_byte_attribute::Add(InHandle, DamageParams);

        auto DefenseParams = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Defense"), 30);
        DefenseParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0).Set_MaxValue(100);
        DefenseAttribute = utils_byte_attribute::Add(InHandle, DefenseParams);
    }

    void Request_BindSignals(FCk_Handle InHandle)
    {
        if (ck::IsValid(DamageAttribute))
        {
            utils_byte_attribute::BindTo_OnValueChanged(DamageAttribute, ECk_MinMaxCurrent::Current,
                FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnDamageValueChanged"));
        }
        if (ck::IsValid(DefenseAttribute))
        {
            utils_byte_attribute::BindTo_OnValueChanged(DefenseAttribute, ECk_MinMaxCurrent::Current,
                FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnDefenseValueChanged"));
        }
    }

    void Request_StartAutomationCycle()
    {
        auto WeaponParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        WeaponParams.Set_ModifierDelta(25);
        auto WeaponMod = utils_byte_attribute_modifier::Add_Revocable(DamageAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"), ECk_AttributeModifier_Operation::Add, WeaponParams);
        if (ck::IsValid(WeaponMod)) { ActiveModifiers.Add(WeaponMod); }
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

        if (Step == 0) { Request_StartAutomationCycle(); }
        else if (Step == 1) { Request_AddArmorModifier(); }
        else if (Step == 2) { Request_AddBuffModifier(); }
        else if (Step == 3) { Request_AddMultipleModifiers(); }
        else if (Step == 4) { Request_RemoveWeaponModifier(); }
        else if (Step == 5) { Request_ModifyExistingModifier(); }
        else if (Step == 6) { Request_ClearAllModifiers(); }
        else if (Step == 7) { Request_TestNotRevocableModifiers(); }

        AutoStep++;
    }

    UFUNCTION()
    private void OnAutoSet(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::HandleAutoSet(InPayload, AutoTimer, AutoRunning);
    }

    void Request_AddArmorModifier()
    {
        if (ck::Is_NOT_Valid(DefenseAttribute)) return;
        auto ArmorParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        ArmorParams.Set_ModifierDelta(15);
        auto ArmorMod = utils_byte_attribute_modifier::Add_Revocable(DefenseAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Armor"), ECk_AttributeModifier_Operation::Add, ArmorParams);
        if (ck::IsValid(ArmorMod)) { ActiveModifiers.Add(ArmorMod); }
    }

    void Request_AddBuffModifier()
    {
        if (ck::Is_NOT_Valid(DamageAttribute)) return;
        auto BuffParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        BuffParams.Set_ModifierDelta(20);
        auto BuffMod = utils_byte_attribute_modifier::Add_Revocable(DamageAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"), ECk_AttributeModifier_Operation::Add, BuffParams);
        if (ck::IsValid(BuffMod)) { ActiveModifiers.Add(BuffMod); }
    }

    void Request_AddMultipleModifiers()
    {
        if (ck::Is_NOT_Valid(DefenseAttribute)) return;
        auto ShieldParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        ShieldParams.Set_ModifierDelta(10);
        auto ShieldMod = utils_byte_attribute_modifier::Add_Revocable(DefenseAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Shield"), ECk_AttributeModifier_Operation::Add, ShieldParams);
        if (ck::IsValid(ShieldMod)) { ActiveModifiers.Add(ShieldMod); }

        auto EnchantParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        EnchantParams.Set_ModifierDelta(8);
        auto EnchantMod = utils_byte_attribute_modifier::Add_Revocable(DefenseAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Enchantment"), ECk_AttributeModifier_Operation::Add, EnchantParams);
        if (ck::IsValid(EnchantMod)) { ActiveModifiers.Add(EnchantMod); }
    }

    void Request_RemoveWeaponModifier()
    {
        auto WeaponMod = utils_byte_attribute_modifier::TryGet(DamageAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"), ECk_MinMaxCurrent::Current);
        if (ck::IsValid(WeaponMod)) { utils_byte_attribute_modifier::Remove(WeaponMod); ActiveModifiers.Remove(WeaponMod); }
    }

    void Request_ModifyExistingModifier()
    {
        auto BuffMod = utils_byte_attribute_modifier::TryGet(DamageAttribute, utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"), ECk_MinMaxCurrent::Current);
        if (ck::IsValid(BuffMod)) { utils_byte_attribute_modifier::Override(BuffMod, 35); }
    }

    void Request_ClearAllModifiers()
    {
        utils_byte_attribute_modifier::Request_ClearAllModifiers(DamageAttribute, ECk_MinMaxCurrent::Current);
        utils_byte_attribute_modifier::Request_ClearAllModifiers(DefenseAttribute, ECk_MinMaxCurrent::Current);
        ActiveModifiers.Empty();
    }

    void Request_TestNotRevocableModifiers()
    {
        if (ck::Is_NOT_Valid(DamageAttribute)) return;
        auto PermanentParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        PermanentParams.Set_ModifierDelta(12);
        utils_byte_attribute_modifier::Add_NotRevocable(DamageAttribute, ECk_AttributeModifier_Operation::Add, PermanentParams);
    }

    void Request_UpdateDisplay()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "BYTE MODIFIERS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        DisplayText = f"{DisplayText}Changes: {ValueChangeCount}\n\n";

        if (ck::IsValid(DamageAttribute))
        {
            auto BaseValue = utils_byte_attribute::Get_BaseValue(DamageAttribute);
            auto BonusValue = utils_byte_attribute::Get_BonusValue(DamageAttribute);
            auto FinalValue = utils_byte_attribute::Get_FinalValue(DamageAttribute);
            auto DamageBar = CkGym_Attribute::Create_ProgressBar(FinalValue, 200.0f, 20);
            DisplayText = f"{DisplayText}Damage: {BaseValue} + {BonusValue} = {FinalValue}/200\n";
            DisplayText = f"{DisplayText}[{DamageBar}]\n\n";
        }

        if (ck::IsValid(DefenseAttribute))
        {
            auto BaseValue = utils_byte_attribute::Get_BaseValue(DefenseAttribute);
            auto BonusValue = utils_byte_attribute::Get_BonusValue(DefenseAttribute);
            auto FinalValue = utils_byte_attribute::Get_FinalValue(DefenseAttribute);
            auto DefenseBar = CkGym_Attribute::Create_ProgressBar(FinalValue, 100.0f, 20, ECk_ASCII_ProgressBar_Style::HashTag_Symbol);
            DisplayText = f"{DisplayText}Defense: {BaseValue} + {BonusValue} = {FinalValue}/100\n";
            DisplayText = f"{DisplayText}[{DefenseBar}]\n\n";
        }

        DisplayText = f"{DisplayText}Active Modifiers: {ActiveModifiers.Num()}\n";
        auto ModifierCount = 0;
        for (auto Modifier : ActiveModifiers)
        {
            if (ck::IsValid(Modifier))
            {
                auto Delta = utils_byte_attribute_modifier::Get_Delta(Modifier);
                ModifierCount++;
                DisplayText = f"{DisplayText}  Mod {ModifierCount}: +{Delta}\n";
            }
        }

        DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
    }

    UFUNCTION()
    private void OnManualAddModifier(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        Request_AddBuffModifier();
    }

    UFUNCTION()
    private void OnManualClearModifiers(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        Request_ClearAllModifiers();
    }

    UFUNCTION() void OnDamageValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
    UFUNCTION() void OnDefenseValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload) { ValueChangeCount++; }

    UFUNCTION()
    private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        AutoStep = 0;
        ValueChangeCount = 0;
        Request_ClearAllModifiers();
        if (ck::IsValid(DamageAttribute)) { utils_byte_attribute::Request_Override(DamageAttribute, 50, ECk_MinMaxCurrent::Current); }
        if (ck::IsValid(DefenseAttribute)) { utils_byte_attribute::Request_Override(DefenseAttribute, 30, ECk_MinMaxCurrent::Current); }
        Request_StartAutomationCycle();

        AutoRunning = true;
        utils_timer::Request_Resume(AutoTimer);
    }
}
