// Language=angelscript

//============================================================================
// CK CROSS-CUTTING — AUTOMATION TEST: SAME-FRAME ATTRIBUTE OVERRIDE COALESCES
//============================================================================
//
// Pins the documented same-frame coalescing contract for CkAttribute (see
// CkAttribute/CLAUDE.md anti-pattern #3 / CkAutoTest_CreationSpecification.txt
// gotcha #10):
//   Two Request_Override calls in one tick yield ONE OnValueChanged
//   broadcast carrying the FINAL value (latest-write-wins).
//
// The refactor is expected to simplify the attribute modifier processor.
// This test catches a regression where simplification fires per-request
// (two OnValueChanged broadcasts) or drops the second write entirely.
//
// Setup:
//   - Add an Integer Health attribute, starting at 50, range [0, 100].
//   - Bind OnValueChanged with a counter.
//   - Issue Request_Override(75) then Request_Override(25) in one tick.
//   - WaitOneFrame for the modifier processor to drain.
//
// Pass: OnValueChanged fired exactly once; FinalValue == 25 (the second
//   write); payload reflects the coalesced result.
// Fail: counter != 1 (two fires, or none) or FinalValue != 25.
//============================================================================

class UCk_AutoTest_CrossCutting_SameFrame_AttributeOverrideCoalesces : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_IntegerAttribute _Attribute;
    private int32 _ValueChangedCount = 0;

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
        _Attribute = utils_integer_attribute::Add(LocalHandle, Params);

        utils_integer_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnValueChanged"));

        // Two writes in one frame — the processor's coalesce contract says
        // exactly one OnValueChanged fires, carrying 25 (latest-write-wins).
        utils_integer_attribute::Request_Override(_Attribute, 75);
        utils_integer_attribute::Request_Override(_Attribute, 25);

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        _ValueChangedCount++;
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_ValueChangedCount, 1,
            "Two same-frame Request_Override calls should coalesce into ONE OnValueChanged broadcast");

        auto FinalValue = utils_integer_attribute::Get_FinalValue(_Attribute);
        Assert_Equals_Int(FinalValue, 25,
            "FinalValue should equal the second (latest) Override write, 25");

        FinishSuccess();
    }
}
