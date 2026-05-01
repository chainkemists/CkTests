// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: FLOAT MODIFIER ADD
//============================================================================
//
// Verifies that adding a revocable additive modifier:
//   - Fires OnValueChanged on the attribute.
//   - FinalValue = BaseValue + ModifierDelta.
//   - BonusValue reflects the modifier delta.
//
// Mirrors the "Add weapon modifier (+25.5)" step in
// CkAttributeGym_Float_Modifiers.
//============================================================================

class UCk_AutoTest_Attribute_FloatModifierAdd : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _Attribute;
    private bool _Observed = false;

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

        auto ModParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(25.5f);
        utils_float_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (_Observed) { return; }
        _Observed = true;

        auto Base = utils_float_attribute::Get_BaseValue(_Attribute);
        auto Bonus = utils_float_attribute::Get_BonusValue(_Attribute);
        auto Final = utils_float_attribute::Get_FinalValue(_Attribute);

        Assert_True(Base == 50.0f,
            f"BaseValue should remain unchanged at 50 (got {Base})");
        Assert_True(Bonus == 25.5f,
            f"BonusValue should reflect single +25.5 modifier (got {Bonus})");
        Assert_True(Final == 75.5f,
            f"FinalValue should be Base+Bonus = 75.5 (got {Final})");

        FinishSuccess();
    }
}
