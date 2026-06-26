// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: FLOAT REFILL
//============================================================================
//
// Verifies the refill mixin restores a drained attribute over time:
//   1. Add a Float attribute with Min=0, Max=100, starting at 100.
//   2. Configure refill at 200 units/sec, StartingState=Running.
//   3. Override Current to 50 (drain).
//   4. After several ticks, the value should have refilled past the
//      drain point — i.e. > 50 and trending toward 100.
//   5. We finish when value reaches 100 (clamped to Max).
//
// We use a fast refill rate (200/s) so the test completes well within
// the 5s harness timeout regardless of frame rate. Harness timeout
// catches the regression case where refill never advances.
//============================================================================

class UCk_AutoTest_Attribute_FloatRefill : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _Energy;
    private bool _DrainIssued = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto RefillParams = FCk_Fragment_FloatAttributeRefill_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_Energy.Refill"),
            200.0f);
        RefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

        auto EnergyParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_Energy"),
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
            // Wait one tick after construction before draining so the refill
            // processor has had a chance to settle, then drop value to 50.
            utils_float_attribute::Request_Override(_Energy, 50.0f);
            _DrainIssued = true;
            return;
        }

        auto Current = utils_float_attribute::Get_FinalValue(_Energy);
        if (Current >= 100.0f)
        {
            Assert_True(Current == 100.0f,
                f"After refill saturates, FinalValue should clamp at Max=100 (got {Current})");
            FinishSuccess();
        }
    }
}
