// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: VECTOR MODIFIER REMOVE
//============================================================================
//
// Vector-side parity with the Float/Integer/Byte ModifierRemove tests. Verifies
// removing a previously-added revocable vector modifier restores the attribute's
// FinalValue to base (BonusValue back to zero), per-component.
//   1. Base (100,100,100). Add modifier delta (25,10,5) -> Final (125,110,105).
//   2. Remove -> Final (100,100,100), Bonus (0,0,0).
//============================================================================

class UCk_AutoTest_Attribute_VectorModifierRemove : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_VectorAttribute _Attribute;
    private FCk_Handle_VectorAttributeModifier _Modifier;
    private int32 _Step = 0;
    private bool _AddObserved = false;
    private bool _RemoveObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_VectorAttribute_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"VectorAttribute.AutoTest_PerComponent"),
            FVector(100.0f, 100.0f, 100.0f));

        _Attribute = utils_vector_attribute::Add(LocalHandle, Params);

        utils_vector_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_VectorAttribute_OnValueChanged(this, n"OnValueChanged"));

        Step1_AddModifier();
    }

    private void Step1_AddModifier()
    {
        _Step = 1;

        auto ModParams = FCk_VectorAttributeModifier_Spec();
        ModParams.Set_ModifierDelta(FVector(25.0f, 10.0f, 5.0f));
        _Modifier = utils_vector_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_RemoveModifier()
    {
        _Step = 2;
        utils_vector_attribute_modifier::Remove(_Modifier);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_VectorAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_AddObserved)
        {
            _AddObserved = true;
            auto Final = utils_vector_attribute::Get_FinalValue(_Attribute);
            Assert_True(Final.Equals(FVector(125.0f, 110.0f, 105.0f), 0.01f),
                f"After Add, FinalValue should be (125,110,105) (got {Final})");
            Step2_RemoveModifier();
            return;
        }

        if (_Step == 2 && !_RemoveObserved)
        {
            _RemoveObserved = true;
            auto Bonus = utils_vector_attribute::Get_BonusValue(_Attribute);
            Assert_True(Bonus.Equals(FVector::ZeroVector, 0.01f),
                f"After Remove, BonusValue should be zero (got {Bonus})");
            auto Final = utils_vector_attribute::Get_FinalValue(_Attribute);
            Assert_True(Final.Equals(FVector(100.0f, 100.0f, 100.0f), 0.01f),
                f"After Remove, FinalValue should be back to base (100,100,100) (got {Final})");
            FinishSuccess();
        }
    }
}
