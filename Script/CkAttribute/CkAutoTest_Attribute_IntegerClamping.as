// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: INTEGER CLAMPING & CLAMP SIGNALS
//============================================================================
//
// Verifies that integer-attribute clamping AND its dedicated clamp signals
// behave correctly on BOTH ends of the range:
//
//   1. Add a Resource attribute (range 0-100, starting at 50).
//   2. Bind OnMinClamped + OnMaxClamped.
//   3. Override to 200 -> expect OnMaxClamped to fire, FinalValue=100.
//   4. Override to -50 -> expect OnMinClamped to fire, FinalValue=0.
//
// Why this is separate from CkAutoTest_Attribute_IntegerBasic:
//   - IntegerBasic verifies the value clamps via the OnValueChanged signal
//     and final-value check — proving the clamp BOUNDARY is correct.
//   - This test verifies the dedicated OnMin/MaxClamped notification
//     signals fire when clamping happens — proving that clamping is
//     OBSERVABLE to game code that wants to react ("you took overkill
//     damage", "you tried to spend more gold than you have", etc.).
//
// IMPORTANT — REQUEST COALESCING:
//   Two Request_Override calls issued back-to-back in the same frame
//   coalesce — the second overwrites the first BEFORE the processor reads
//   it, so only the second override ever runs and only one of the two
//   clamp signals would fire. The original draft of this test made that
//   mistake. The correct shape is a signal-driven step machine: issue the
//   first override, WAIT for OnMaxClamped, then issue the second override
//   and wait for OnMinClamped. That guarantees the processor drains each
//   request fully before the next one is queued.
//
// Pattern A (signal-driven step machine).
//============================================================================

class UCk_AutoTest_Attribute_IntegerClamping : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _ResourceAttribute;
    private int32 _Step = 0;
    private bool _MaxObserved = false;
    private bool _MinObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Health"),
            50);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(100);

        auto LocalHandle = InHandle;
        _ResourceAttribute = utils_integer_attribute::Add(LocalHandle, Params);

        utils_integer_attribute::BindTo_OnMinClamped(_ResourceAttribute,
            FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMinClamped"));
        utils_integer_attribute::BindTo_OnMaxClamped(_ResourceAttribute,
            FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnMaxClamped"));

        Step1_OverrideAboveMax();
    }

    private void Step1_OverrideAboveMax()
    {
        _Step = 1;
        utils_integer_attribute::Request_Override(_ResourceAttribute, 200, ECk_MinMaxCurrent::Current);
    }

    private void Step2_OverrideBelowMin()
    {
        _Step = 2;
        utils_integer_attribute::Request_Override(_ResourceAttribute, -50, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void OnMaxClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_MaxObserved)
        {
            _MaxObserved = true;
            auto FinalValue = utils_integer_attribute::Get_FinalValue(_ResourceAttribute);
            Assert_Equals_Int(FinalValue, 100,
                "Value clamps to MaxValue (100) when overriding to 200");
            Step2_OverrideBelowMin();
        }
    }

    UFUNCTION()
    private void OnMinClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 2 && !_MinObserved)
        {
            _MinObserved = true;
            auto FinalValue = utils_integer_attribute::Get_FinalValue(_ResourceAttribute);
            Assert_Equals_Int(FinalValue, 0,
                "Value clamps to MinValue (0) when overriding to -50");
            FinishSuccess();
        }
    }
}
