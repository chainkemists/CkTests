// Language=angelscript

//============================================================================
// CK ATTRIBUTE - AUTOMATION TEST: FLOAT INCREMENT / DECREMENT HELPERS
//============================================================================
//
// Verifies the float attribute mixin's increment/decrement helpers:
//   - IncrementNotRevocable() raises BonusValue by +1 (stays after applied).
//   - IncrementRevocable() returns a modifier handle; removing the modifier
//     restores the previous BonusValue.
//   - DecrementNotRevocable() lowers BonusValue by -1.
//
// Mirrors CkAttributeGym_Float_IncrementDecrement.
//============================================================================

class UCk_AutoTest_Attribute_FloatIncrement : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _Counter;
    private int32 _Step = 0;
    private bool _Step1Observed = false;
    private bool _Step2Observed = false;
    private bool _Step3Observed = false;
    private FCk_Handle_FloatAttributeModifier _RevocableMod;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Counter"),
            25.0f);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0.0f);
        Params.Set_MaxValue(50.0f);

        _Counter = utils_float_attribute::Add(LocalHandle, Params);

        utils_float_attribute::BindTo_OnValueChanged(
            _Counter,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));

        Step1_IncrementNotRevocable();
    }

    private void Step1_IncrementNotRevocable()
    {
        _Step = 1;
        _Counter.IncrementNotRevocable();
    }

    private void Step2_IncrementRevocable()
    {
        _Step = 2;
        _RevocableMod = _Counter.IncrementRevocable();
    }

    private void Step3_DecrementNotRevocable()
    {
        _Step = 3;
        _Counter.DecrementNotRevocable();
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_Step1Observed)
        {
            _Step1Observed = true;
            Assert_True(utils_float_attribute::Get_FinalValue(_Counter) == 26.0f,
                f"After IncrementNotRevocable, FinalValue should be 26 (got {utils_float_attribute::Get_FinalValue(_Counter)})");
            Step2_IncrementRevocable();
            return;
        }

        if (_Step == 2 && !_Step2Observed)
        {
            _Step2Observed = true;
            Assert_True(ck::IsValid(_RevocableMod),
                "IncrementRevocable should return a valid modifier handle");
            Assert_True(utils_float_attribute::Get_FinalValue(_Counter) == 27.0f,
                f"After IncrementRevocable, FinalValue should be 27 (got {utils_float_attribute::Get_FinalValue(_Counter)})");
            Step3_DecrementNotRevocable();
            return;
        }

        if (_Step == 3 && !_Step3Observed)
        {
            _Step3Observed = true;
            Assert_True(utils_float_attribute::Get_FinalValue(_Counter) == 26.0f,
                f"After DecrementNotRevocable, FinalValue should be back to 26 (got {utils_float_attribute::Get_FinalValue(_Counter)})");
            FinishSuccess();
            return;
        }
    }
}
