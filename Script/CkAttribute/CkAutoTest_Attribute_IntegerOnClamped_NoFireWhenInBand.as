// Language=angelscript

//============================================================================
// CK ATTRIBUTE - AUTOMATION TEST: INTEGER OnClamped fires only at boundary
//============================================================================
//
// Integer-side parity with CkAutoTest_Attribute_FloatOnClamped_NoFireWhenInBand.
// OnMaxClamped fires when an override pushes the value into clamp territory,
// but stays silent when the value lands strictly inside [Min, Max].
//   1. Add Integer attr Min=0, Max=100, starting=50.
//   2. Override to 30 (in-band) -> no clamp fire.
//   3. Override to 200 (clamps to Max=100) -> exactly one clamp fire.
//============================================================================

class UCk_AutoTest_Attribute_IntegerOnClamped_NoFireWhenInBand : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_IntegerAttribute _Attr;
    private int32 _ClampedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto AttrParams = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Health"),
            50);
        AttrParams.Set_MinMax(ECk_MinMax::MinMax);
        AttrParams.Set_MinValue(0);
        AttrParams.Set_MaxValue(100);

        _Attr = utils_integer_attribute::Add(LocalHandle, AttrParams);

        _Attr.BindTo_OnMaxClamped(FCk_Delegate_IntegerAttribute_OnClamped(this, n"OnClamped"));

        utils_integer_attribute::Request_Override(_Attr, 30, ECk_MinMaxCurrent::Current);
        WaitUntil(n"Check_InBandApplied", n"AfterInBand");
    }

    UFUNCTION()
    private void OnClamped(FCk_Handle InAttributeOwnerEntity, FCk_Payload_IntegerAttribute_OnClamped InPayload)
    {
        _ClampedCount += 1;
    }

    // The in-band override LANDING is the witness for a negative assertion:
    // once FinalValue reads the requested in-band value the override has been
    // applied end-to-end, so "and no clamp fired" is decisive rather than
    // merely delayed. A clamp that wrongly fired would have fired during that
    // same application, and the == 0 assertion reports it.
    UFUNCTION()
    private void Check_InBandApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_integer_attribute::Get_FinalValue(_Attr) == 30);
    }

    UFUNCTION()
    private void Check_ClampFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ClampedCount >= 1);
    }

    UFUNCTION()
    private void AfterInBand(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_ClampedCount, 0,
            "OnMaxClamped should NOT fire when override lands in-band (30 within [0,100])");

        utils_integer_attribute::Request_Override(_Attr, 200, ECk_MinMaxCurrent::Current);
        WaitUntil(n"Check_ClampFired", n"AfterAboveMax");
    }

    UFUNCTION()
    private void AfterAboveMax(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_ClampedCount, 1,
            "OnMaxClamped should fire exactly once when override pushes value above Max=100");
        Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attr), 100,
            "After above-Max override, FinalValue should clamp to Max=100");

        FinishSuccess();
    }
}
