// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: FLOAT MODIFIER STACKING
//============================================================================
//
// Verifies that two simultaneously-active additive modifiers stack:
//   FinalValue = BaseValue + Modifier1.Delta + Modifier2.Delta
//
// Why this is a separate test rather than implicit in ModifierAdd:
//   The gym demonstrates stacking visually across multiple steps but never
//   isolates the "two distinct modifiers contribute additively" guarantee.
//   A regression where the second modifier silently overwrites the first
//   (rather than stacking) would not be caught by ModifierAdd or
//   ModifierRemove individually — both would still pass.
//
// NOTE — GAP IN GYM COVERAGE (potential gym additions):
//   The Float_Modifiers gym only exercises ECk_AttributeModifier_Operation::Add.
//   The Multiply operation isn't tested anywhere — neither here nor in the
//   gym, neither in C++ nor in AngelScript. Worth a follow-up gym
//   step + paired AutoTest once we know the multiplier semantics
//   (delta as multiplier vs. delta as percentage). Same gap likely
//   exists for IntegerAttribute and ByteAttribute modifier ops.
//
// Pattern: add Modifier1, wait for OnValueChanged (confirms add). Then
// add Modifier2, wait for OnValueChanged again (confirms stacking). Two
// adds in one frame would coalesce, hence the step-machine.
//============================================================================

class UCk_AutoTest_Attribute_FloatModifierStacking : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _Attribute;
    private int32 _Step = 0;
    private bool _FirstObserved = false;
    private bool _SecondObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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

        Step1_AddFirstModifier();
    }

    private void Step1_AddFirstModifier()
    {
        _Step = 1;
        auto ModParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(25.5f);
        utils_float_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_AddSecondModifier()
    {
        _Step = 2;
        auto ModParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(20.25f);
        utils_float_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_FirstObserved)
        {
            _FirstObserved = true;
            auto Final = utils_float_attribute::Get_FinalValue(_Attribute);
            Assert_True(Final == 75.5f,
                f"After first modifier, FinalValue should be 75.5 (got {Final})");
            Step2_AddSecondModifier();
            return;
        }

        if (_Step == 2 && !_SecondObserved)
        {
            _SecondObserved = true;
            auto Bonus = utils_float_attribute::Get_BonusValue(_Attribute);
            auto Final = utils_float_attribute::Get_FinalValue(_Attribute);
            Assert_True(Bonus == 45.75f,
                f"After two modifiers, BonusValue should stack to 45.75 (got {Bonus})");
            Assert_True(Final == 95.75f,
                f"After two modifiers, FinalValue should be 50 + 25.5 + 20.25 = 95.75 (got {Final})");
            FinishSuccess();
        }
    }
}
