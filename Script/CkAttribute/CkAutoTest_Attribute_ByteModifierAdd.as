// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: BYTE MODIFIER ADD
//============================================================================
//
// Byte-side parity with the existing Integer/Float modifier tests.
// Verifies that adding a revocable additive byte modifier:
//   - Fires OnValueChanged on the attribute.
//   - FinalValue = BaseValue + ModifierDelta.
//   - BonusValue reflects the modifier delta.
//
// Stays inside [0, 255] domain to avoid signed-vs-unsigned weirdness on
// the byte backing.
//============================================================================

class UCk_AutoTest_Attribute_ByteModifierAdd : UCk_AutoTest_Base
{
    private FCk_Handle_ByteAttribute _Armor;
    private bool _Observed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Params = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Armor"),
            100);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(255);

        auto LocalHandle = InHandle;
        _Armor = utils_byte_attribute::Add(LocalHandle, Params);

        utils_byte_attribute::BindTo_OnValueChanged(
            _Armor,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged"));

        auto ModParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(25);
        utils_byte_attribute_modifier::Add_Revocable(
            _Armor,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Plate"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (_Observed) { return; }
        _Observed = true;

        Assert_Equals_Int(int32(utils_byte_attribute::Get_BaseValue(_Armor)), 100,
            "BaseValue should remain unchanged at 100");
        Assert_Equals_Int(int32(utils_byte_attribute::Get_BonusValue(_Armor)), 25,
            "BonusValue should reflect single +25 modifier");
        Assert_Equals_Int(int32(utils_byte_attribute::Get_FinalValue(_Armor)), 125,
            "FinalValue should be Base+Bonus = 125");

        FinishSuccess();
    }
}
