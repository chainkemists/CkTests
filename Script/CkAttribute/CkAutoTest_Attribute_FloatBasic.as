// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: FLOAT BASIC
//============================================================================
//
// Float-attribute equivalent of CkAutoTest_Attribute_IntegerBasic. Verifies
// the float attribute API end-to-end:
//   1. Add a Health attribute (range 0-100, starting at 100).
//   2. Override the value to 42.5.
//   3. Bind OnValueChanged → expect signal with new=42.5.
//   4. Assert Get_FinalValue == 42.5.
//   5. Override to -50 → expect clamp to MinValue (0).
//
// Same step-machine pattern as the Integer test — coalescing applies to
// float requests too, so each step waits for its signal before queuing the
// next.
//============================================================================

class UCk_AutoTest_Attribute_FloatBasic : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _HealthAttribute;
    private int32 _Step = 0;
    private bool _OverrideObserved = false;
    private bool _ClampObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Params = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Health"),
            100.0f);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0.0f);
        Params.Set_MaxValue(100.0f);

        auto LocalHandle = InHandle;
        _HealthAttribute = utils_float_attribute::Add(LocalHandle, Params);

        utils_float_attribute::BindTo_OnValueChanged(
            _HealthAttribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnHealthChanged"));

        Step1_OverrideTo42p5();
    }

    private void Step1_OverrideTo42p5()
    {
        _Step = 1;
        utils_float_attribute::Request_Override(_HealthAttribute, 42.5f);
    }

    private void Step2_OverrideToNegative_ExpectClamp()
    {
        _Step = 2;
        utils_float_attribute::Request_Override(_HealthAttribute, -50.0f);
    }

    UFUNCTION()
    private void OnHealthChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_OverrideObserved)
        {
            _OverrideObserved = true;
            auto FinalValue = utils_float_attribute::Get_FinalValue(_HealthAttribute);
            Assert_True(FinalValue == 42.5f,
                f"Health attribute after Override(42.5) should be 42.5 (got {FinalValue})");
            Step2_OverrideToNegative_ExpectClamp();
            return;
        }

        if (_Step == 2 && !_ClampObserved)
        {
            _ClampObserved = true;
            auto FinalValue = utils_float_attribute::Get_FinalValue(_HealthAttribute);
            Assert_True(FinalValue == 0.0f,
                f"Health attribute clamps to MinValue (0) when overridden to -50 (got {FinalValue})");
            FinishSuccess();
            return;
        }
    }
}
