// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: INTEGER BASIC
//============================================================================
//
// Verifies the CkAttribute integer-attribute API end-to-end:
//   1. Add a Health attribute (range 0-100, starting at 100).
//   2. Override the value to 42.
//   3. Bind OnValueChanged → expect signal with new=42.
//   4. Assert Get_FinalValue == 42.
//   5. Override to -50 → expect clamp to MinValue (0).
//
// This is the first non-Economy / non-BB-specific automation test, exercising
// the harness against a pure CkFoundation framework feature.
//============================================================================

class UCk_AutoTest_Attribute_IntegerBasic : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute HealthAttribute;
    private int32 _Step = 0;
    private bool _OverrideObserved = false;
    private bool _ClampObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Health"),
            100);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(100);

        auto LocalHandle = InHandle;
        HealthAttribute = utils_integer_attribute::Add(LocalHandle, Params);

        utils_integer_attribute::BindTo_OnValueChanged(
            HealthAttribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnHealthChanged"));

        Step1_OverrideTo42();
    }

    private void Step1_OverrideTo42()
    {
        _Step = 1;
        utils_integer_attribute::Request_Override(HealthAttribute, 42);
    }

    private void Step2_OverrideToNegative_ExpectClamp()
    {
        _Step = 2;
        utils_integer_attribute::Request_Override(HealthAttribute, -50);
    }

    UFUNCTION()
    private void OnHealthChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_OverrideObserved)
        {
            _OverrideObserved = true;
            auto FinalValue = utils_integer_attribute::Get_FinalValue(HealthAttribute);
            Assert_Equals_Int(FinalValue, 42, "Health attribute after Override(42)");
            Step2_OverrideToNegative_ExpectClamp();
            return;
        }

        if (_Step == 2 && !_ClampObserved)
        {
            _ClampObserved = true;
            auto FinalValue = utils_integer_attribute::Get_FinalValue(HealthAttribute);
            Assert_Equals_Int(FinalValue, 0, "Health attribute clamps to MinValue (0) when overridden to -50");
            FinishSuccess();
            return;
        }
    }
}
