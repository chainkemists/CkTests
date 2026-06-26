// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: OnClamped fires only at Min/Max boundary
//============================================================================
//
// Pins the OnClamped fire-gating: the signal fires when an Override or
// Adjust pushes the attribute's final value INTO clamp territory (Min or
// Max boundary hit), but stays silent when the value lands strictly
// inside the [Min, Max] band.
//
// Catches the regression where OnClamped fires on every value change
// regardless of clamp state.
//
// Flow:
//   1. Add Float attr Min=0, Max=100, starting=50.
//   2. Bind OnClamped to counter delegate.
//   3. Override to 30 (in-band) → wait one frame → count must stay 0.
//   4. Override to 200 (clamps to Max=100) → wait one frame → count
//      must be 1.
//
// Closes the OnClamped_NoFireWhenInBand audit gap.
//============================================================================

class UCk_AutoTest_Attribute_FloatOnClamped_NoFireWhenInBand : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_FloatAttribute _Attr;
    private int32 _ClampedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto AttrParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_ClampBand"),
            50.0f);
        AttrParams.Set_MinMax(ECk_MinMax::MinMax);
        AttrParams.Set_MinValue(0.0f);
        AttrParams.Set_MaxValue(100.0f);

        _Attr = utils_float_attribute::Add(LocalHandle, AttrParams);

        // CkAttribute exposes two separate boundary signals (OnMinClamped
        // and OnMaxClamped), not a single OnClamped. We test the Max path
        // because we're forcing a value above 100 — OnMinClamped would not
        // fire for that direction. Audit row name preserved on the test
        // class for grep-ability.
        _Attr.BindTo_OnMaxClamped(FCk_Delegate_FloatAttribute_OnClamped(this, n"OnClamped"));

        // Step 1: in-band override — no clamp expected.
        utils_float_attribute::Request_Override(_Attr, 30.0f);

        WaitOneFrame(n"AfterInBand");
    }

    UFUNCTION()
    private void OnClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_FloatAttribute_OnClamped InPayload)
    {
        _ClampedCount += 1;
    }

    UFUNCTION()
    private void AfterInBand(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_ClampedCount, 0,
            "OnClamped should NOT fire when override lands in-band (30 within [0,100])");

        // Step 2: above-Max override — clamp expected.
        utils_float_attribute::Request_Override(_Attr, 200.0f);

        WaitOneFrame(n"AfterAboveMax");
    }

    UFUNCTION()
    private void AfterAboveMax(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_ClampedCount, 1,
            "OnClamped should fire exactly once when override pushes value above Max=100");

        auto FinalValue = utils_float_attribute::Get_FinalValue(_Attr);
        Assert_True(FinalValue == 100.0f,
            f"After above-Max override, FinalValue should clamp to Max=100 (got {FinalValue})");

        FinishSuccess();
    }
}
