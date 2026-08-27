// Language=angelscript

//============================================================================
// CK ATTRIBUTE - AUTOMATION TEST: VECTOR MODIFIER ADD
//============================================================================
//
// Vector-side parity with the Float/Integer/Byte ModifierAdd tests. Verifies a
// revocable additive vector modifier composes per-component into BonusValue and
// FinalValue.
//   - Base (100,100,100). Add modifier delta (25,10,5).
//   - BonusValue = (25,10,5); FinalValue = (125,110,105).
//============================================================================

class UCk_AutoTest_Attribute_VectorModifierAdd : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_VectorAttribute _Attribute;
    private bool _Observed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_VectorAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"VectorAttribute.AutoTest_PerComponent"),
            FVector(100.0f, 100.0f, 100.0f));

        _Attribute = utils_vector_attribute::Add(LocalHandle, Params);

        utils_vector_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_VectorAttribute_OnValueChanged(this, n"OnValueChanged"));

        auto ModParams = FCk_Fragment_VectorAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(FVector(25.0f, 10.0f, 5.0f));
        utils_vector_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_VectorAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (_Observed) { return; }
        _Observed = true;

        auto Bonus = utils_vector_attribute::Get_BonusValue(_Attribute);
        Assert_True(Bonus.Equals(FVector(25.0f, 10.0f, 5.0f), 0.01f),
            f"BonusValue should reflect per-component modifier delta (got {Bonus})");

        auto Final = utils_vector_attribute::Get_FinalValue(_Attribute);
        Assert_True(Final.Equals(FVector(125.0f, 110.0f, 105.0f), 0.01f),
            f"FinalValue should be Base+Bonus per-component (got {Final})");

        FinishSuccess();
    }
}
