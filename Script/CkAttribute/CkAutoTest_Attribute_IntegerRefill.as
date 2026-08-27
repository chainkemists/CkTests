// Language=angelscript

//============================================================================
// CK ATTRIBUTE - AUTOMATION TEST: INTEGER REFILL
//============================================================================
//
// Integer-side parity with CkAutoTest_Attribute_FloatRefill. Verifies the
// refill mixin restores a drained integer attribute over time:
//   1. Add an Integer attribute Min=0, Max=100, starting at 100, refill 200/s.
//   2. Drain Current to 50.
//   3. After ticks, value refills and saturates at Max=100.
//============================================================================

class UCk_AutoTest_Attribute_IntegerRefill : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Energy;
    private bool _DrainIssued = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto RefillParams = FCk_Fragment_IntegerAttributeRefill_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.AutoTest_Energy.Refill"),
            200.0f);
        RefillParams.Set_StartingState(ECk_Attribute_RefillState::Running);

        auto EnergyParams = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.AutoTest_Energy"),
            100);
        EnergyParams.Set_MinMax(ECk_MinMax::MinMax);
        EnergyParams.Set_MinValue(0);
        EnergyParams.Set_MaxValue(100);
        EnergyParams.Set_EnableRefill(true);
        EnergyParams.Set_RefillParams(RefillParams);

        _Energy = utils_integer_attribute::Add(LocalHandle, EnergyParams);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!_DrainIssued)
        {
            utils_integer_attribute::Request_Override(_Energy, 50, ECk_MinMaxCurrent::Current);
            _DrainIssued = true;
            return;
        }

        auto Current = utils_integer_attribute::Get_FinalValue(_Energy);
        if (Current >= 100)
        {
            Assert_Equals_Int(Current, 100,
                "After refill saturates, FinalValue should clamp at Max=100");
            FinishSuccess();
        }
    }
}
