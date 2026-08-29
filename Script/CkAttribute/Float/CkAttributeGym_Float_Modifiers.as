//============================================================================
// FLOAT MODIFIERS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_AttributeGym_FloatModifiers : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_FloatAttribute DamageAttribute;
    FCk_Handle_FloatAttribute DefenseAttribute;
    TArray<FCk_Handle_FloatAttributeModifier> ActiveModifiers;

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
        utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_FloatModifiers");

        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        AutoTimer = gym_auto::Setup(InHandle, this, FCk_Time(2.5f));

        AutoConfig.TotalSteps = 8;
        AutoConfig.Description = "Tests modifier system with add/multiply operations.\nShows Base + Bonus = Final with stacking modifiers.";
        AutoConfig.GlobalAutoCommand = "panel [T] Auto-cycle all stations";
        AutoConfig.PerStationAutoCommand = "panel [3] Modifiers station auto";
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add weapon modifier (+25.5)", 0, 0));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add armor modifier (+15.75)", 1, 1));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add buff modifier (+20.25)", 2, 2));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add shield + enchant modifiers", 3, 3));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Remove weapon modifier", 4, 4));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Modify existing buff (20.25 -> 35.75)", 5, 5));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Clear all modifiers", 6, 6));
        AutoConfig.Steps.Add(FCkGym_AutoStep("Add non-revocable modifier (+12.5)", 7, 7));
        AutoConfig.ManualCommands.Add("panel [K] Modifiers ring · add weapon / revoke weapon / clear all");

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        Request_SetupAttributes(InHandle);
        Request_BindSignals(InHandle);

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_AddModifier,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualAddWeapon"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_RevokeAll,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualRemoveWeapon"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_FloatGym_ClearModifiers,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnManualClearMods"));
    }

    void Request_SetupAttributes(FCk_Handle InHandle)
    {
        auto DamageParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Damage"), 50.0f);
        DamageParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(10.0f).Set_MaxValue(200.0f);
        DamageAttribute = utils_float_attribute::Add(InHandle, DamageParams);

        auto DefenseParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Defense"), 30.0f);
        DefenseParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(0.0f).Set_MaxValue(100.0f);
        DefenseAttribute = utils_float_attribute::Add(InHandle, DefenseParams);
    }

    void Request_BindSignals(FCk_Handle InHandle)
    {
        if (ck::IsValid(DamageAttribute))
        {
            utils_float_attribute::BindTo_OnValueChanged(DamageAttribute, ECk_MinMaxCurrent::Current,
                FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnDamageValueChanged"));
        }
        if (ck::IsValid(DefenseAttribute))
        {
            utils_float_attribute::BindTo_OnValueChanged(DefenseAttribute, ECk_MinMaxCurrent::Current,
                FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnDefenseValueChanged"));
        }
    }

    UFUNCTION() private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT) { Request_UpdateDisplay(); }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Step = AutoStep % AutoConfig.TotalSteps;

        if (Step == 0) { Request_AddWeaponModifier(); }
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

    void Request_AddWeaponModifier()
    {
        auto WeaponParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        WeaponParams.Set_ModifierDelta(25.5f);
        auto WeaponMod = utils_float_attribute_modifier::Add_Revocable(DamageAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"), ECk_AttributeModifier_Operation::Add, WeaponParams);
        if (ck::IsValid(WeaponMod)) { ActiveModifiers.Add(WeaponMod); }
    }

    void Request_AddArmorModifier()
    {
        if (ck::Is_NOT_Valid(DefenseAttribute)) return;
        auto ArmorParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        ArmorParams.Set_ModifierDelta(15.75f);
        auto ArmorMod = utils_float_attribute_modifier::Add_Revocable(DefenseAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Armor"), ECk_AttributeModifier_Operation::Add, ArmorParams);
        if (ck::IsValid(ArmorMod)) { ActiveModifiers.Add(ArmorMod); }
    }

    void Request_AddBuffModifier()
    {
        if (ck::Is_NOT_Valid(DamageAttribute)) return;
        auto BuffParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        BuffParams.Set_ModifierDelta(20.25f);
        auto BuffMod = utils_float_attribute_modifier::Add_Revocable(DamageAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"), ECk_AttributeModifier_Operation::Add, BuffParams);
        if (ck::IsValid(BuffMod)) { ActiveModifiers.Add(BuffMod); }
    }

    void Request_AddMultipleModifiers()
    {
        if (ck::Is_NOT_Valid(DefenseAttribute)) return;
        auto ShieldParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        ShieldParams.Set_ModifierDelta(10.5f);
        auto ShieldMod = utils_float_attribute_modifier::Add_Revocable(DefenseAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Shield"), ECk_AttributeModifier_Operation::Add, ShieldParams);
        if (ck::IsValid(ShieldMod)) { ActiveModifiers.Add(ShieldMod); }

        auto EnchantParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        EnchantParams.Set_ModifierDelta(8.3f);
        auto EnchantMod = utils_float_attribute_modifier::Add_Revocable(DefenseAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Enchantment"), ECk_AttributeModifier_Operation::Add, EnchantParams);
        if (ck::IsValid(EnchantMod)) { ActiveModifiers.Add(EnchantMod); }
    }

    void Request_RemoveWeaponModifier()
    {
        auto WeaponMod = utils_float_attribute_modifier::TryGet(DamageAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"), ECk_MinMaxCurrent::Current);
        if (ck::IsValid(WeaponMod)) { utils_float_attribute_modifier::Remove(WeaponMod); ActiveModifiers.Remove(WeaponMod); }
    }

    void Request_ModifyExistingModifier()
    {
        auto BuffMod = utils_float_attribute_modifier::TryGet(DamageAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"), ECk_MinMaxCurrent::Current);
        if (ck::IsValid(BuffMod)) { utils_float_attribute_modifier::Override(BuffMod, 35.75f); }
    }

    void Request_ClearAllModifiers()
    {
        utils_float_attribute_modifier::Request_ClearAllModifiers(DamageAttribute, ECk_MinMaxCurrent::Current);
        utils_float_attribute_modifier::Request_ClearAllModifiers(DefenseAttribute, ECk_MinMaxCurrent::Current);
        ActiveModifiers.Empty();
    }

    void Request_TestNotRevocableModifiers()
    {
        if (ck::Is_NOT_Valid(DamageAttribute)) return;
        auto PermanentParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        PermanentParams.Set_ModifierDelta(12.5f);
        utils_float_attribute_modifier::Add_NotRevocable(DamageAttribute, ECk_AttributeModifier_Operation::Add, PermanentParams);
    }

    void Request_UpdateDisplay()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto TitleText = "FLOAT MODIFIERS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
        auto DisplayText = gym_auto::FormatHeader(AutoConfig, AutoRunning);

        DisplayText = f"{DisplayText}Changes: {ValueChangeCount}\n\n";

        if (ck::IsValid(DamageAttribute))
        {
            auto BaseValue = utils_float_attribute::Get_BaseValue(DamageAttribute);
            auto BonusValue = utils_float_attribute::Get_BonusValue(DamageAttribute);
            auto FinalValue = utils_float_attribute::Get_FinalValue(DamageAttribute);
            auto DamageBar = CkGym_Attribute::Create_ProgressBar(FinalValue, 200.0f, 20);
            DisplayText = f"{DisplayText}Damage: {BaseValue} + {BonusValue} = {FinalValue}/200\n";
            DisplayText = f"{DisplayText}[{DamageBar}]\n\n";
        }

        if (ck::IsValid(DefenseAttribute))
        {
            auto BaseValue = utils_float_attribute::Get_BaseValue(DefenseAttribute);
            auto BonusValue = utils_float_attribute::Get_BonusValue(DefenseAttribute);
            auto FinalValue = utils_float_attribute::Get_FinalValue(DefenseAttribute);
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
                auto Delta = utils_float_attribute_modifier::Get_Delta(Modifier);
                ModifierCount++;
                DisplayText = f"{DisplayText}  Mod {ModifierCount}: +{Delta}\n";
            }
        }

        DisplayText = DisplayText + "\n" + gym_auto::FormatAutoAndCommands(AutoConfig, AutoStep, AutoRunning);
        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText, "");
    }

    UFUNCTION() void OnDamageValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { ValueChangeCount++; }
    UFUNCTION() void OnDefenseValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnValueChanged InPayload) { ValueChangeCount++; }

    UFUNCTION()
    private void OnManualAddWeapon(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        Request_AddWeaponModifier();
    }

    UFUNCTION()
    private void OnManualRemoveWeapon(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        Request_RemoveWeaponModifier();
    }

    UFUNCTION()
    private void OnManualClearMods(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        gym_auto::StopAuto(AutoTimer, AutoRunning);
        Request_ClearAllModifiers();
    }

    UFUNCTION()
    private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        AutoStep = 0;
        ValueChangeCount = 0;

        utils_float_attribute_modifier::Request_ClearAllModifiers(DamageAttribute, ECk_MinMaxCurrent::Current);
        utils_float_attribute_modifier::Request_ClearAllModifiers(DefenseAttribute, ECk_MinMaxCurrent::Current);
        ActiveModifiers.Empty();

        if (ck::IsValid(DamageAttribute)) { utils_float_attribute::Request_Override(DamageAttribute, 50.0f, ECk_MinMaxCurrent::Current); }
        if (ck::IsValid(DefenseAttribute)) { utils_float_attribute::Request_Override(DefenseAttribute, 30.0f, ECk_MinMaxCurrent::Current); }
    }
}
