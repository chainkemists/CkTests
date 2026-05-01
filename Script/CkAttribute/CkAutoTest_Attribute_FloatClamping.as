// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: FLOAT CLAMPING & CLAMP SIGNALS
//============================================================================
//
// Float-attribute equivalent of CkAutoTest_Attribute_IntegerClamping. See
// that file for the full rationale on why this is a separate test from the
// Basic version (signal observability) and why a step-machine is required
// (request coalescing).
//
//   1. Add a Resource attribute (range 0-100, starting at 50).
//   2. Bind OnMinClamped + OnMaxClamped.
//   3. Override to 200 -> expect OnMaxClamped to fire, FinalValue=100.
//   4. Override to -50 -> expect OnMinClamped to fire, FinalValue=0.
//============================================================================

class UCk_AutoTest_Attribute_FloatClamping : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _ResourceAttribute;
    private int32 _Step = 0;
    private bool _MaxObserved = false;
    private bool _MinObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Params = FCk_Fragment_FloatAttribute_ParamsData(
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
        utils_float_attribute::Request_Override(_ResourceAttribute, 200.0f);
    }

    private void Step2_OverrideBelowMin()
    {
        _Step = 2;
        utils_float_attribute::Request_Override(_ResourceAttribute, -50.0f);
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
            auto FinalValue = utils_float_attribute::Get_FinalValue(_ResourceAttribute);
            Assert_True(FinalValue == 100.0f,
                f"Value clamps to MaxValue (100) when overriding to 200 (got {FinalValue})");
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
            auto FinalValue = utils_float_attribute::Get_FinalValue(_ResourceAttribute);
            Assert_True(FinalValue == 0.0f,
                f"Value clamps to MinValue (0) when overriding to -50 (got {FinalValue})");
            FinishSuccess();
        }
    }
}
