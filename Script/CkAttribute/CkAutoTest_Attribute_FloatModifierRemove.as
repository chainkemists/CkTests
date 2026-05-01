// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: FLOAT MODIFIER REMOVE
//============================================================================
//
// Verifies that removing a previously-added revocable modifier restores
// the attribute's FinalValue to the base value (with BonusValue=0).
//
// This is a high-value regression test because "modifier added" passing
// doesn't imply "modifier removed cleanly" — the failure mode where
// a removed modifier still contributes to the value is silent and easy
// to introduce.
//
// Pattern: add modifier, wait for OnValueChanged (Step 1: confirms add).
// Then remove modifier, wait for OnValueChanged again (Step 2: confirms
// removal). Each remove path is queued only after the add path is fully
// observed to avoid request coalescing.
//
// Mirrors the "Remove weapon modifier" step in CkAttributeGym_Float_Modifiers.
//============================================================================

class UCk_AutoTest_Attribute_FloatModifierRemove : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _Attribute;
    private FCk_Handle_FloatAttributeModifier _Modifier;
    private int32 _Step = 0;
    private bool _AddObserved = false;
    private bool _RemoveObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Params = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Damage"),
            50.0f);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0.0f);
        Params.Set_MaxValue(200.0f);

        auto LocalHandle = InHandle;
        _Attribute = utils_float_attribute::Add(LocalHandle, Params);

        utils_float_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));

        Step1_AddModifier();
    }

    private void Step1_AddModifier()
    {
        _Step = 1;

        auto ModParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(25.5f);
        _Modifier = utils_float_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_RemoveModifier()
    {
        _Step = 2;
        utils_float_attribute_modifier::Remove(_Modifier);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_AddObserved)
        {
            _AddObserved = true;
            auto Final = utils_float_attribute::Get_FinalValue(_Attribute);
            Assert_True(Final == 75.5f,
                f"After Add, FinalValue should be 75.5 (got {Final})");
            Step2_RemoveModifier();
            return;
        }

        if (_Step == 2 && !_RemoveObserved)
        {
            _RemoveObserved = true;
            auto Bonus = utils_float_attribute::Get_BonusValue(_Attribute);
            auto Final = utils_float_attribute::Get_FinalValue(_Attribute);
            Assert_True(Bonus == 0.0f,
                f"After Remove, BonusValue should be 0 (got {Bonus})");
            Assert_True(Final == 50.0f,
                f"After Remove, FinalValue should be back to BaseValue (50, got {Final})");
            FinishSuccess();
        }
    }
}
