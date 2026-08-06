// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: FLOAT PRE-CLAMP / OVERFLOW
//============================================================================
//
// Float-attribute equivalent of CkAutoTest_Attribute_IntegerOverflow. See
// that file for the full rationale on why this is split from the Clamping
// test (presence of signal vs accuracy of payload data) and why we read
// the payload values rather than polling Get_PreClampFinalValue.
//
//   1. Add a Resource attribute (range 0-100, starting at 50).
//   2. Override to 200 -> expect FinalValue=100, OnMaxClamped payload
//      reports PreClampFinalValue=200, ClampOverflow=+100.
//   3. Override to -50 -> expect FinalValue=0,   OnMinClamped payload
//      reports PreClampFinalValue=-50, ClampOverflow=-50.
//============================================================================

class UCk_AutoTest_Attribute_FloatOverflow : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _ResourceAttribute;
    private int32 _Step = 0;
    private bool _MaxObserved = false;
    private bool _MinObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_FloatAttribute_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Health"),
            50.0f);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0.0f);
        Params.Set_MaxValue(100.0f);

        auto LocalHandle = InHandle;
        _ResourceAttribute = utils_float_attribute::Add(LocalHandle, Params);

        utils_float_attribute::BindTo_OnMinClamped(_ResourceAttribute,
            FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMinClamped"));
        utils_float_attribute::BindTo_OnMaxClamped(_ResourceAttribute,
            FCk_Delegate_FloatAttribute_OnClamped(this, n"OnMaxClamped"));

        Step1_OverrideAboveMax();
    }

    private void Step1_OverrideAboveMax()
    {
        _Step = 1;
        utils_float_attribute::Request_Override(_ResourceAttribute, 200.0f, ECk_MinMaxCurrent::Current);
    }

    private void Step2_OverrideBelowMin()
    {
        _Step = 2;
        utils_float_attribute::Request_Override(_ResourceAttribute, -50.0f, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void OnMaxClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_FloatAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_MaxObserved)
        {
            _MaxObserved = true;
            Assert_True(InPayload.Get_PreClampFinalValue() == 200.0f,
                f"OnMaxClamped payload PreClampFinalValue should be 200 (got {InPayload.Get_PreClampFinalValue()})");
            Assert_True(InPayload.Get_ClampOverflow() == 100.0f,
                f"OnMaxClamped payload ClampOverflow should be +100 (got {InPayload.Get_ClampOverflow()})");
            Step2_OverrideBelowMin();
        }
    }

    UFUNCTION()
    private void OnMinClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_FloatAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 2 && !_MinObserved)
        {
            _MinObserved = true;
            Assert_True(InPayload.Get_PreClampFinalValue() == -50.0f,
                f"OnMinClamped payload PreClampFinalValue should be -50 (got {InPayload.Get_PreClampFinalValue()})");
            Assert_True(InPayload.Get_ClampOverflow() == -50.0f,
                f"OnMinClamped payload ClampOverflow should be -50 (got {InPayload.Get_ClampOverflow()})");
            FinishSuccess();
        }
    }
}
