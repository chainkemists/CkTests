// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: Float refill clamps + holds at Max
//============================================================================
//
// Pins the RefillPolicy_StopsAtMax contract: once a running refill
// saturates the attribute at MaxValue, subsequent ticks leave the value
// unchanged. The existing FloatRefill test exits the moment value
// reaches 100; this test goes further and asserts the value REMAINS
// at 100 across additional refill processor passes (no overshoot,
// no spurious decrement, no oscillation).
//
// Flow:
//   1. Add a Float attribute Min=0, Max=100, starting=100 with refill
//      rate 200/s and Running state.
//   2. Override Current to 50 (drain).
//   3. Wait for refill to bring value back to 100 (saturation).
//   4. After saturation, wait 0.3s of additional refill processor ticks.
//   5. Assert value is still exactly 100.0 — the refill stopped
//      advancing once Max was reached.
//============================================================================

class UCk_AutoTest_Attribute_FloatRefill_StopsAtMax : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_FloatAttribute _Energy;
    private bool _DrainIssued = false;
    private bool _Saturated = false;
    private float32 _SaturatedAtSeconds = 0.0f;
    private float32 _ElapsedSinceSaturation = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto RefillParams = FCk_Fragment_FloatAttributeRefill_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_Energy_StopsAtMax.Refill"),
            200.0f);
        RefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

        auto EnergyParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_Energy_StopsAtMax"),
            100.0f);
        EnergyParams.Set_MinMax(ECk_MinMax::MinMax);
        EnergyParams.Set_MinValue(0.0f);
        EnergyParams.Set_MaxValue(100.0f);
        EnergyParams.Set_EnableRefill(true);
        EnergyParams.Set_RefillParams(RefillParams);

        _Energy = utils_float_attribute::Add(LocalHandle, EnergyParams);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!_DrainIssued)
        {
            utils_float_attribute::Request_Override(_Energy, 50.0f);
            _DrainIssued = true;
            return;
        }

        auto Current = utils_float_attribute::Get_FinalValue(_Energy);

        if (!_Saturated)
        {
            if (Current >= 100.0f)
            {
                _Saturated = true;
                _ElapsedSinceSaturation = 0.0f;
            }
            return;
        }

        // After saturation, observe across additional ticks.
        _ElapsedSinceSaturation += float32(InDeltaT.Get_Seconds());

        // Catch any drift from 100 immediately — the refill processor must
        // not push the value past Max or accidentally roll it back.
        Assert_True(Current == 100.0f,
            f"After saturating at Max=100, value must stay at exactly 100 — got {Current} after {_ElapsedSinceSaturation}s of additional refill ticks");

        if (_ElapsedSinceSaturation >= 0.30f)
        {
            FinishSuccess();
        }
    }
}
