// Language=angelscript

//============================================================================
// CK ATTRIBUTE - AUTOMATION TEST: INTEGER MODIFIER STACKING
//============================================================================
//
// Integer-side parity with CkAutoTest_Attribute_FloatModifierStacking.
// Verifies that two simultaneously-active additive modifiers stack:
//   FinalValue = BaseValue + Modifier1.Delta + Modifier2.Delta
//
// Pattern: add Modifier1, wait for OnValueChanged. Then add Modifier2,
// wait for OnValueChanged again. Two adds in one frame would coalesce,
// hence the step-machine. See FloatModifierStacking for fuller rationale.
//
// NOTE - same Multiply-operation coverage gap noted in
// CkAutoTest_Attribute_FloatModifierStacking applies on the Integer side
// too: ECk_AttributeModifier_Operation::Multiply isn't exercised anywhere.
//============================================================================

class UCk_AutoTest_Attribute_IntegerModifierStacking : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private int32 _Step = 0;
    private bool _FirstObserved = false;
    private bool _SecondObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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

        Step1_AddFirstModifier();
    }

    private void Step1_AddFirstModifier()
    {
        _Step = 1;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(25);
        utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_AddSecondModifier()
    {
        _Step = 2;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(20);
        utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_FirstObserved)
        {
            _FirstObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 75,
                "After first modifier, FinalValue should be 75");
            Step2_AddSecondModifier();
            return;
        }

        if (_Step == 2 && !_SecondObserved)
        {
            _SecondObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_BonusValue(_Attribute), 45,
                "After two modifiers, BonusValue should stack to 45");
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 95,
                "After two modifiers, FinalValue should be 50 + 25 + 20 = 95");
            FinishSuccess();
        }
    }
}
