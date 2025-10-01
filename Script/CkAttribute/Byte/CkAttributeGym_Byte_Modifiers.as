//============================================================================
// BYTE MODIFIERS ENTITY SCRIPT
//============================================================================

class UCk_EntityScript_AttributeGym_ByteModifiers : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    FCk_Handle_ByteAttribute DamageAttribute;
    FCk_Handle_ByteAttribute DefenseAttribute;

    TArray<FCk_Handle_ByteAttributeModifier> ActiveModifiers;

    // Automation cycle state
    int32 CycleStep = 0;
    int32 ValueChangeCount = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::Replicates);
        utils_entity_tag::Add(InHandle, n"TAG_AttributeGym_ByteModifiers");

        Request_SetupTimers(InHandle);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Request_SetupAttributes(InHandle);
        Request_BindSignals(InHandle);
        Request_StartAutomationCycle();

        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_AttributeGym_ResetAttributes,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnResetAttributes"));
    }

    void Request_SetupTimers(FCk_Handle InHandle)
    {
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"DisplayTick"));

        auto AutoTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(2.5f));
        AutoTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto AutoTimer = utils_timer::Add(InHandle, AutoTimerParams);
        AutoTimer.BindTo_OnDone(ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"AutoTick"));
    }

    void Request_SetupAttributes(FCk_Handle InHandle)
    {
        // Damage: 10-200, starts at 50
        auto DamageParams = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Damage"), 50);
        DamageParams.Set_MinMax(ECk_MinMax::MinMax).Set_MinValue(10).Set_MaxValue(200);
        DamageAttribute = utils_byte_attribute::Add(InHandle, DamageParams);

        // Defense: 0-100, starts at 30
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
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing,
                FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnDamageValueChanged"));
        }

        if (ck::IsValid(DefenseAttribute))
        {
            utils_byte_attribute::BindTo_OnValueChanged(DefenseAttribute, ECk_MinMaxCurrent::Current,
                ECk_Signal_BindingPolicy::FireIfPayloadInFlight, ECk_Signal_PostFireBehavior::DoNothing,
                FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnDefenseValueChanged"));
        }
    }

    void Request_StartAutomationCycle()
    {
        // Add initial weapon modifier
        auto WeaponParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        WeaponParams.Set_ModifierDelta(25);

        auto WeaponMod = utils_byte_attribute_modifier::Add_Revocable(
            DamageAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            WeaponParams);

        if (ck::IsValid(WeaponMod))
        {
            ActiveModifiers.Add(WeaponMod);
        }
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Request_UpdateDisplay();
    }

    UFUNCTION()
    private void AutoTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Request_ExecuteAutomationStep();
    }

    void Request_ExecuteAutomationStep()
    {
        CycleStep++;

        switch (CycleStep)
        {
            case 1: Request_AddArmorModifier(); break;
            case 2: Request_AddBuffModifier(); break;
            case 3: Request_AddMultipleModifiers(); break;
            case 4: Request_RemoveWeaponModifier(); break;
            case 5: Request_ModifyExistingModifier(); break;
            case 6: Request_ClearAllModifiers(); break;
            case 7: Request_TestNotRevocableModifiers(); break;
            default:
                CycleStep = 0; // Reset cycle
                Request_StartAutomationCycle();
                break;
        }
    }

    void Request_AddArmorModifier()
    {
        if (ck::Is_NOT_Valid(DefenseAttribute)) return;

        auto ArmorParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        ArmorParams.Set_ModifierDelta(15);

        auto ArmorMod = utils_byte_attribute_modifier::Add_Revocable(
            DefenseAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Armor"),
            ECk_AttributeModifier_Operation::Add,
            ArmorParams);

        if (ck::IsValid(ArmorMod))
        {
            ActiveModifiers.Add(ArmorMod);
        }
    }

    void Request_AddBuffModifier()
    {
        if (ck::Is_NOT_Valid(DamageAttribute)) return;

        auto BuffParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        BuffParams.Set_ModifierDelta(20);

        auto BuffMod = utils_byte_attribute_modifier::Add_Revocable(
            DamageAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
            ECk_AttributeModifier_Operation::Add,
            BuffParams);

        if (ck::IsValid(BuffMod))
        {
            ActiveModifiers.Add(BuffMod);
        }
    }

    void Request_AddMultipleModifiers()
    {
        if (ck::Is_NOT_Valid(DefenseAttribute)) return;

        // Add shield modifier
        auto ShieldParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        ShieldParams.Set_ModifierDelta(10);

        auto ShieldMod = utils_byte_attribute_modifier::Add_Revocable(
            DefenseAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Shield"),
            ECk_AttributeModifier_Operation::Add,
            ShieldParams);

        if (ck::IsValid(ShieldMod))
        {
            ActiveModifiers.Add(ShieldMod);
        }

        // Add enchantment modifier
        auto EnchantParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        EnchantParams.Set_ModifierDelta(8);

        auto EnchantMod = utils_byte_attribute_modifier::Add_Revocable(
            DefenseAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Enchantment"),
            ECk_AttributeModifier_Operation::Add,
            EnchantParams);

        if (ck::IsValid(EnchantMod))
        {
            ActiveModifiers.Add(EnchantMod);
        }
    }

    void Request_RemoveWeaponModifier()
    {
        auto WeaponMod = utils_byte_attribute_modifier::TryGet(
            DamageAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_MinMaxCurrent::Current);

        if (ck::IsValid(WeaponMod))
        {
            utils_byte_attribute_modifier::Remove(WeaponMod);
            ActiveModifiers.Remove(WeaponMod);
        }
    }

    void Request_ModifyExistingModifier()
    {
        auto BuffMod = utils_byte_attribute_modifier::TryGet(
            DamageAttribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
            ECk_MinMaxCurrent::Current);

        if (ck::IsValid(BuffMod))
        {
            utils_byte_attribute_modifier::Override(BuffMod, 35); // Increase from 20 to 35
        }
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

        // Add non-revocable permanent modifier
        auto PermanentParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        PermanentParams.Set_ModifierDelta(12);

        utils_byte_attribute_modifier::Add_NotRevocable(
            DamageAttribute,
            ECk_AttributeModifier_Operation::Add,
            PermanentParams);
    }

    void Request_UpdateDisplay()
    {
        auto SelfEntity = ck::SelfEntity(this);
        auto TitleText = "BYTE MODIFIERS (" + CkGym_Common::Get_NetworkRoleTitle(SelfEntity) + ")";
        auto DisplayText = f"Cycle Step: {CycleStep}/7 | Changes: {ValueChangeCount}\n\n";

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

        // Display current automation phase
        auto PhaseText = Get_CurrentPhaseText();
        DisplayText = f"{DisplayText}AUTOMATION: {PhaseText}\n\n";

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

        CkGym_Common::Update_StationDisplay(SelfEntity, TitleText, DisplayText,
            "Cycles through 7 phases: adding/removing modifiers, testing non-revocable modifiers, \n" +
            "and clearing all. Displays Base + Bonus = Final calculations. Shows active modifier\n" +
            "count and individual delta values.");
    }

    FString Get_CurrentPhaseText()
    {
        switch (CycleStep)
        {
            case 0: return "Starting - Adding Weapon";
            case 1: return "Adding Armor Modifier";
            case 2: return "Adding Buff Modifier";
            case 3: return "Adding Multiple Modifiers";
            case 4: return "Removing Weapon Modifier";
            case 5: return "Modifying Existing Buff";
            case 6: return "Clearing All Modifiers";
            case 7: return "Adding Non-Revocable";
            default: return "Unknown Phase";
        }
    }

    // Signal callbacks
    UFUNCTION()
    void OnDamageValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        ValueChangeCount++;
    }

    UFUNCTION()
    void OnDefenseValueChanged(FCk_Handle InAttributeOwnerEntity, FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        ValueChangeCount++;
    }

    // Message handlers
    UFUNCTION()
    private void OnResetAttributes(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        CycleStep = 0;
        ValueChangeCount = 0;

        // Clear all modifiers
        utils_byte_attribute_modifier::Request_ClearAllModifiers(DamageAttribute, ECk_MinMaxCurrent::Current);
        utils_byte_attribute_modifier::Request_ClearAllModifiers(DefenseAttribute, ECk_MinMaxCurrent::Current);
        ActiveModifiers.Empty();

        // Reset base values
        if (ck::IsValid(DamageAttribute))
        {
            utils_byte_attribute::Request_Override(DamageAttribute, 50);
        }
        if (ck::IsValid(DefenseAttribute))
        {
            utils_byte_attribute::Request_Override(DefenseAttribute, 30);
        }

        // Restart automation
        Request_StartAutomationCycle();
    }
}