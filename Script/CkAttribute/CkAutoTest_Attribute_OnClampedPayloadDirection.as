// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: ON-CLAMPED PAYLOAD DIRECTION VALUES
//============================================================================
//
// Pins the per-direction payload contract in CkAttribute/CLAUDE.md:
//
//   The signal payload (`FCk_Payload_*Attribute_OnClamped`) is unaffected
//   [by fragment asymmetry] — it carries event-time values that are correct
//   for the direction whose signal fires.
//
// Existing test `CkAutoTest_Attribute_IntegerClamping` only asserts that
// each clamp signal fires and that the *post-clamp* FinalValue is correct.
// This test extends that: it asserts the payload itself (PreClampFinalValue,
// FinalClampedValue, ClampOverflow) carries the right values for each
// direction, NOT the values from the wrong direction's fragment.
//
// Range [0,100], starting at 50:
//   Step 1: Override(200) -> OnMaxClamped fires.
//           Payload.PreClampFinalValue == 200, FinalClampedValue == 100,
//           ClampOverflow == +100.
//   Step 2: Override(-50) -> OnMinClamped fires.
//           Payload.PreClampFinalValue == -50, FinalClampedValue == 0,
//           ClampOverflow == -50.
//
// Pattern A (signal-driven step machine), per gotcha #10.
//============================================================================

class UCk_AutoTest_Attribute_OnClampedPayloadDirection : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private int32 _Step = 0;
    private bool _MaxObserved = false;
    private bool _MinObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_IntegerAttribute_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Health"),
            50);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(100);

        auto LocalHandle = InHandle;
        _Attribute = utils_integer_attribute::Add(LocalHandle, Params);

        utils_integer_attribute::BindTo_OnMaxClamped(_Attribute,
            FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMaxClamped"));
        utils_integer_attribute::BindTo_OnMinClamped(_Attribute,
            FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMinClamped"));

        _Step = 1;
        utils_integer_attribute::Request_Override(_Attribute, 200, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void OnMaxClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && _MaxObserved == false)
        {
            _MaxObserved = true;
            Assert_Equals_Int(InPayload.Get_PreClampFinalValue(), 200,
                "OnMaxClamped payload PreClampFinalValue should be 200 (the raw pre-clamp value)");
            Assert_Equals_Int(InPayload.Get_FinalClampedValue(), 100,
                "OnMaxClamped payload FinalClampedValue should be 100 (the post-clamp Max)");
            Assert_Equals_Int(InPayload.Get_ClampOverflow(), 100,
                "OnMaxClamped payload ClampOverflow should be +100 (positive = over max)");

            _Step = 2;
            utils_integer_attribute::Request_Override(_Attribute, -50, ECk_MinMaxCurrent::Current);
        }
    }

    UFUNCTION()
    private void OnMinClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 2 && _MinObserved == false)
        {
            _MinObserved = true;
            Assert_Equals_Int(InPayload.Get_PreClampFinalValue(), -50,
                "OnMinClamped payload PreClampFinalValue should be -50 (event-time pre-clamp, NOT the asymmetric fragment value)");
            Assert_Equals_Int(InPayload.Get_FinalClampedValue(), 0,
                "OnMinClamped payload FinalClampedValue should be 0 (the post-clamp Min)");
            Assert_Equals_Int(InPayload.Get_ClampOverflow(), -50,
                "OnMinClamped payload ClampOverflow should be -50 (negative = under min)");
            FinishSuccess();
        }
    }
}
