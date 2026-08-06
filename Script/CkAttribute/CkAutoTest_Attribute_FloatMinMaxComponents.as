// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: FLOAT MIN/MAX COMPONENT ROUTING
//============================================================================
//
// Verifies that an attribute configured with MinMax bounds exposes three
// separately-bindable signals (Min, Max, Current) and that overrides
// targeted at a specific component fire only that component's signal:
//   1. Add an attribute with Min=10, Max=200, Current=100.
//   2. Bind OnValueChanged on Min, Max, Current independently.
//   3. Override Min to 25.5 → Min handler fires, Max/Current do not.
//   4. Override Max to 175.75 → Max handler fires, Min/Current do not.
//
// Mirrors CkAttributeGym_Float_MinMaxCurrent.
//============================================================================

class UCk_AutoTest_Attribute_FloatMinMaxComponents : UCk_AutoTest_Base
{
    private FCk_Handle_FloatAttribute _Power;
    private int32 _Step = 0;
    private int32 _MinFires = 0;
    private int32 _MaxFires = 0;
    private int32 _CurrentFires = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_FloatAttribute_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Power"),
            100.0f);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(10.0f);
        Params.Set_MaxValue(200.0f);

        _Power = utils_float_attribute::Add(LocalHandle, Params);

        utils_float_attribute::BindTo_OnValueChanged(
            _Power, ECk_MinMaxCurrent::Min,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnMinChanged"));
        utils_float_attribute::BindTo_OnValueChanged(
            _Power, ECk_MinMaxCurrent::Max,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnMaxChanged"));
        utils_float_attribute::BindTo_OnValueChanged(
            _Power, ECk_MinMaxCurrent::Current,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnCurrentChanged"));

        Step1_OverrideMin();
    }

    private void Step1_OverrideMin()
    {
        _Step = 1;
        utils_float_attribute::Request_Override(_Power, 25.5f, ECk_MinMaxCurrent::Min);
    }

    private void Step2_OverrideMax()
    {
        _Step = 2;
        utils_float_attribute::Request_Override(_Power, 175.75f, ECk_MinMaxCurrent::Max);
    }

    UFUNCTION()
    private void OnMinChanged(FCk_Handle InOwner, FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        _MinFires++;

        if (_Step == 1)
        {
            Assert_Equals_Int(_MaxFires, 0, "Override on Min should not fire Max handler");
            Assert_Equals_Int(_CurrentFires, 0, "Override on Min should not fire Current handler");
            auto MinValue = utils_float_attribute::Get_BaseValue(_Power, ECk_MinMaxCurrent::Min);
            Assert_True(MinValue == 25.5f, f"Min BaseValue should be 25.5 (got {MinValue})");
            Step2_OverrideMax();
        }
    }

    UFUNCTION()
    private void OnMaxChanged(FCk_Handle InOwner, FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        _MaxFires++;

        if (_Step == 2)
        {
            Assert_Equals_Int(_MinFires, 1, "Min handler should still have only 1 fire after Max override");
            auto MaxValue = utils_float_attribute::Get_BaseValue(_Power, ECk_MinMaxCurrent::Max);
            Assert_True(MaxValue == 175.75f, f"Max BaseValue should be 175.75 (got {MaxValue})");
            FinishSuccess();
        }
    }

    UFUNCTION()
    private void OnCurrentChanged(FCk_Handle InOwner, FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        _CurrentFires++;
    }
}
