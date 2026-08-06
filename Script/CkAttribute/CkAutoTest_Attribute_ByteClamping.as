// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: BYTE CLAMPING & CLAMP SIGNALS
//============================================================================
//
// Byte-side parity with CkAutoTest_Attribute_IntegerClamping. Verifies the
// dedicated OnMin/MaxClamped notification signals fire on both ends of a
// byte attribute's range. The uint8 backing can't represent negative values,
// so the min-clamp case uses a non-zero MinValue (20) and overrides below it.
//
//   1. Add a Durability attribute (range 20-200, starting at 100).
//   2. Bind OnMinClamped + OnMaxClamped.
//   3. Override to 250 -> expect OnMaxClamped, FinalValue=200.
//   4. Override to 5   -> expect OnMinClamped, FinalValue=20.
//
// Pattern A (signal-driven step machine) — back-to-back overrides in one frame
// coalesce, so each step waits for its own signal before issuing the next.
//============================================================================

class UCk_AutoTest_Attribute_ByteClamping : UCk_AutoTest_Base
{
    private FCk_Handle_ByteAttribute _Durability;
    private int32 _Step = 0;
    private bool _MaxObserved = false;
    private bool _MinObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_ByteAttribute_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Armor"),
            100);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(20);
        Params.Set_MaxValue(200);

        auto LocalHandle = InHandle;
        _Durability = utils_byte_attribute::Add(LocalHandle, Params);

        utils_byte_attribute::BindTo_OnMinClamped(_Durability,
            FCk_Delegate_ByteAttribute_OnClamped(this, n"OnMinClamped"));
        utils_byte_attribute::BindTo_OnMaxClamped(_Durability,
            FCk_Delegate_ByteAttribute_OnClamped(this, n"OnMaxClamped"));

        Step1_OverrideAboveMax();
    }

    private void Step1_OverrideAboveMax()
    {
        _Step = 1;
        utils_byte_attribute::Request_Override(_Durability, 250, ECk_MinMaxCurrent::Current);
    }

    private void Step2_OverrideBelowMin()
    {
        _Step = 2;
        utils_byte_attribute::Request_Override(_Durability, 5, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void OnMaxClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_ByteAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_MaxObserved)
        {
            _MaxObserved = true;
            Assert_Equals_Int(int32(utils_byte_attribute::Get_FinalValue(_Durability)), 200,
                "Value clamps to MaxValue (200) when overriding to 250");
            Step2_OverrideBelowMin();
        }
    }

    UFUNCTION()
    private void OnMinClamped(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_ByteAttribute_OnClamped InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 2 && !_MinObserved)
        {
            _MinObserved = true;
            Assert_Equals_Int(int32(utils_byte_attribute::Get_FinalValue(_Durability)), 20,
                "Value clamps to MinValue (20) when overriding to 5");
            FinishSuccess();
        }
    }
}
