// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: INTEGER PRE-CLAMP / OVERFLOW
//============================================================================
//
// Verifies that the OnMin/MaxClamped signal payload carries accurate
// pre-clamp value and overflow delta information:
//
//   1. Add a Resource attribute (range 0-100, starting at 50).
//   2. Override to 200 -> expect FinalValue=100, OnMaxClamped payload
//      reports PreClampFinalValue=200, ClampOverflow=+100.
//   3. Override to -50 -> expect FinalValue=0,   OnMinClamped payload
//      reports PreClampFinalValue=-50, ClampOverflow=-50.
//
// Why this is separate from CkAutoTest_Attribute_IntegerClamping:
//   - IntegerClamping verifies the clamp SIGNALS fire on both directions
//     (presence + count), which is what game code uses to react to over-
//     /under-flow ("you took overkill damage", "you tried to overspend").
//   - IntegerOverflow verifies the signal PAYLOAD's pre-clamp data is
//     accurate, which is what game code reads to compute things like
//     overkill amount or how far over budget the player went.
//   - Splitting them gives two independent regression signals: a future
//     change that breaks payload computation but keeps signal emission
//     fails this test alone, with a focused "expected X, got Y" message
//     instead of bundling failure modes together.
//
// Why use the SIGNAL PAYLOAD's pre-clamp values rather than polling
// Get_PreClampFinalValue / Get_ClampOverflow at settle time:
//   Per CkAttribute/CLAUDE.md, the two TFragment_Attribute_PreClampFinalValue
//   fragments are not symmetric — Min-before-Max ordering means the Max
//   fragment captures pre-min-clamp value, not pre-any-clamp. The
//   utility accessors abstract over this asymmetry, but the SIGNAL PAYLOAD
//   carries the correct pre-clamp value for THIS direction at fire time,
//   which is what gameplay code reading the event actually wants. Testing
//   the payload tests the path callers actually use.
//
// Pattern A (signal-driven step machine) — same as IntegerClamping. Two
// requests in one frame would coalesce (gotcha #10), so each step waits
// for its own signal before triggering the next.
//============================================================================

class UCk_AutoTest_Attribute_IntegerOverflow : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _ResourceAttribute;
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
            // Override(200) on a 0..100 range:
            //   PreClampFinalValue: what the modifier chain would have produced (200)
            //   ClampOverflow:      signed delta over max, +100 (200 - 100)
            Assert_Equals_Int(InPayload.Get_PreClampFinalValue(), 200,
                "OnMaxClamped payload PreClampFinalValue reflects raw pre-clamp value (200)");
            Assert_Equals_Int(InPayload.Get_ClampOverflow(), 100,
                "OnMaxClamped payload ClampOverflow is signed delta over max (+100)");
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
            // Override(-50) on a 0..100 range:
            //   PreClampFinalValue: -50
            //   ClampOverflow:      signed delta under min, -50 (-50 - 0)
            Assert_Equals_Int(InPayload.Get_PreClampFinalValue(), -50,
                "OnMinClamped payload PreClampFinalValue reflects raw pre-clamp value (-50)");
            Assert_Equals_Int(InPayload.Get_ClampOverflow(), -50,
                "OnMinClamped payload ClampOverflow is signed delta under min (-50)");
            FinishSuccess();
        }
    }
}