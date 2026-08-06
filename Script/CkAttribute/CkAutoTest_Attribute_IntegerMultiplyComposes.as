// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: INTEGER MULTIPLY COMPOSES
//============================================================================
//
// Pins the Multiply coalescing contract in CkAttribute/CLAUDE.md:
//
//   | Multiply / Divide | factors compose into one modifier |
//
// `Add_NotRevocable` with `ECk_AttributeModifier_Operation::Multiply` is
// expected to coalesce into a single modifier whose successive applications
// compound (not replace, not stack as separate). Issuing two multiply
// modifiers across two ticks (signal-driven step machine to avoid coalescing
// inside one frame) on Base=10:
//
//   Step 1: Mul(2) -> processor applies, Base = 10 * 2 = 20
//   Step 2: Mul(3) -> processor applies, Base = 20 * 3 = 60
//
// If multiplication did NOT compose (e.g. latest-wins), Step 2 would yield
// Base = 30, not 60. Asserting 60 pins composition.
//
// Pattern A (signal-driven step machine), per gotcha #10.
//============================================================================

class UCk_AutoTest_Attribute_IntegerMultiplyComposes : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private int32 _Step = 0;
    private bool _Step1Observed = false;
    private bool _Step2Observed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_IntegerAttribute_Spec(
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

        Step1_MultiplyByTwo();
    }

    private void Step1_MultiplyByTwo()
    {
        _Step = 1;
        auto ModParams = FCk_IntegerAttributeModifier_Spec();
        ModParams.Set_ModifierDelta(2);
        utils_integer_attribute_modifier::Add_NotRevocable(
            _Attribute,
            ECk_AttributeModifier_Operation::Multiply,
            ModParams);
    }

    private void Step2_MultiplyByThree()
    {
        _Step = 2;
        auto ModParams = FCk_IntegerAttributeModifier_Spec();
        ModParams.Set_ModifierDelta(3);
        utils_integer_attribute_modifier::Add_NotRevocable(
            _Attribute,
            ECk_AttributeModifier_Operation::Multiply,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && _Step1Observed == false)
        {
            _Step1Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 20,
                "After Mul(2), FinalValue should be Base*2 = 20");
            Step2_MultiplyByThree();
            return;
        }

        if (_Step == 2 && _Step2Observed == false)
        {
            _Step2Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 60,
                "After Mul(3) following Mul(2), FinalValue should compose to 20*3 = 60 (not 30)");
            FinishSuccess();
        }
    }
}
