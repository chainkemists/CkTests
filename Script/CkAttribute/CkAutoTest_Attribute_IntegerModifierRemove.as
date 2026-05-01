// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: INTEGER MODIFIER REMOVE
//============================================================================
//
// Integer-side parity with CkAutoTest_Attribute_FloatModifierRemove.
// Verifies that removing a previously-added revocable modifier restores
// the attribute's FinalValue to the base value (with BonusValue=0).
//
// Pattern: add modifier, wait for OnValueChanged (Step 1: confirms add).
// Then remove modifier, wait for OnValueChanged again (Step 2: confirms
// removal). Step-machine to avoid request coalescing.
//============================================================================

class UCk_AutoTest_Attribute_IntegerModifierRemove : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private FCk_Handle_IntegerAttributeModifier _Modifier;
    private int32 _Step = 0;
    private bool _AddObserved = false;
    private bool _RemoveObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Damage"),
            50);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(200);

        auto LocalHandle = InHandle;
        _Attribute = utils_integer_attribute::Add(LocalHandle, Params);

        utils_integer_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnValueChanged"));

        Step1_AddModifier();
    }

    private void Step1_AddModifier()
    {
        _Step = 1;

        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(25);
        _Modifier = utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_RemoveModifier()
    {
        _Step = 2;
        utils_integer_attribute_modifier::Remove(_Modifier);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_AddObserved)
        {
            _AddObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 75,
                "After Add, FinalValue should be 75");
            Step2_RemoveModifier();
            return;
        }

        if (_Step == 2 && !_RemoveObserved)
        {
            _RemoveObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_BonusValue(_Attribute), 0,
                "After Remove, BonusValue should be 0");
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 50,
                "After Remove, FinalValue should be back to BaseValue (50)");
            FinishSuccess();
        }
    }
}
