// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: INTEGER MODIFIER ADD
//============================================================================
//
// Integer-side parity with CkAutoTest_Attribute_FloatModifierAdd. Verifies
// that adding a revocable additive modifier:
//   - Fires OnValueChanged on the attribute.
//   - FinalValue = BaseValue + ModifierDelta.
//   - BonusValue reflects the modifier delta.
//============================================================================

class UCk_AutoTest_Attribute_IntegerModifierAdd : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private bool _Observed = false;

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

        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(25);
        utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (_Observed) { return; }
        _Observed = true;

        Assert_Equals_Int(utils_integer_attribute::Get_BaseValue(_Attribute), 50,
            "BaseValue should remain unchanged at 50");
        Assert_Equals_Int(utils_integer_attribute::Get_BonusValue(_Attribute), 25,
            "BonusValue should reflect single +25 modifier");
        Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 75,
            "FinalValue should be Base+Bonus = 75");

        FinishSuccess();
    }
}
