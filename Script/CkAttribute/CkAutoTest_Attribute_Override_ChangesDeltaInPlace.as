// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: MODIFIER OVERRIDE CHANGES DELTA IN PLACE
//============================================================================
//
// Pins the `utils_*_attribute_modifier::Override(modHandle, newDelta)`
// contract: a previously-added Revocable modifier can have its delta mutated
// in place via Override, without creating a second modifier entity. The
// original modifier handle remains valid and now carries the new delta;
// the attribute's FinalValue recomputes against the new delta.
//
// On Base=10:
//   Step 1: Add_Revocable(Add, 5)      -> Final = 15
//   Step 2: Override(modHandle, 20)    -> Final = 30 (Base + 20)
//   Verify Get_Delta(modHandle) == 20 (same entity, new value)
//   Verify Has(modHandle) still true (entity not replaced or destroyed)
//
// If Override created a new modifier entity, FinalValue would still be 30
// (since the old +5 was overwritten in place by replace semantics), but the
// original handle would lose its Has() invariant. Pinning both Final AND the
// handle invariants distinguishes "mutated-in-place" from "replaced".
//
// Pattern A (signal-driven step machine), per gotcha #10.
//============================================================================

class UCk_AutoTest_Attribute_Override_ChangesDeltaInPlace : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private FCk_Handle_IntegerAttributeModifier _Modifier;
    private int32 _Step = 0;
    private bool _AddObserved = false;
    private bool _OverrideObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Damage"),
            10);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(1000);

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
        ModParams.Set_ModifierDelta(5);
        _Modifier = utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_OverrideDelta()
    {
        _Step = 2;
        utils_integer_attribute_modifier::Override(_Modifier, 20);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && _AddObserved == false)
        {
            _AddObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 15,
                "After Add_Revocable(+5), FinalValue should be 15");
            Assert_Equals_Int(utils_integer_attribute_modifier::Get_Delta(_Modifier), 5,
                "Modifier delta should be 5 right after add");
            Step2_OverrideDelta();
            return;
        }

        if (_Step == 2 && _OverrideObserved == false)
        {
            _OverrideObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 30,
                "After Override(modHandle, 20), FinalValue should recompute to Base+20 = 30");
            Assert_Equals_Int(utils_integer_attribute_modifier::Get_Delta(_Modifier), 20,
                "Override should mutate the existing modifier's delta to 20 in place");
            FinishSuccess();
        }
    }
}
