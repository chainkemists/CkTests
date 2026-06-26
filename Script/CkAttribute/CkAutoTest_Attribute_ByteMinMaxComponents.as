// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: BYTE MIN/MAX COMPONENT ROUTING
//============================================================================
//
// Byte-side parity with CkAutoTest_Attribute_FloatMinMaxComponents. Verifies a
// MinMax-bounded byte attribute exposes three separately-bindable signals
// (Min, Max, Current) and that overrides targeted at a specific component fire
// only that component's signal.
//   1. Add an attribute with Min=10, Max=200, Current=100.
//   2. Bind OnValueChanged on Min, Max, Current independently.
//   3. Override Min to 25  -> Min handler fires, Max/Current do not.
//   4. Override Max to 175 -> Max handler fires, Min/Current do not.
//============================================================================

class UCk_AutoTest_Attribute_ByteMinMaxComponents : UCk_AutoTest_Base
{
    private FCk_Handle_ByteAttribute _Power;
    private int32 _Step = 0;
    private int32 _MinFires = 0;
    private int32 _MaxFires = 0;
    private int32 _CurrentFires = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Armor"),
            100);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(10);
        Params.Set_MaxValue(200);

        _Power = utils_byte_attribute::Add(LocalHandle, Params);

        utils_byte_attribute::BindTo_OnValueChanged(
            _Power, ECk_MinMaxCurrent::Min,
            FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnMinChanged"));
        utils_byte_attribute::BindTo_OnValueChanged(
            _Power, ECk_MinMaxCurrent::Max,
            FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnMaxChanged"));
        utils_byte_attribute::BindTo_OnValueChanged(
            _Power, ECk_MinMaxCurrent::Current,
            FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnCurrentChanged"));

        Step1_OverrideMin();
    }

    private void Step1_OverrideMin()
    {
        _Step = 1;
        utils_byte_attribute::Request_Override(_Power, 25, ECk_MinMaxCurrent::Min);
    }

    private void Step2_OverrideMax()
    {
        _Step = 2;
        utils_byte_attribute::Request_Override(_Power, 175, ECk_MinMaxCurrent::Max);
    }

    UFUNCTION()
    private void OnMinChanged(FCk_Handle InOwner, FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        _MinFires++;

        if (_Step == 1)
        {
            Assert_Equals_Int(_MaxFires, 0, "Override on Min should not fire Max handler");
            Assert_Equals_Int(_CurrentFires, 0, "Override on Min should not fire Current handler");
            Assert_Equals_Int(int32(utils_byte_attribute::Get_BaseValue(_Power, ECk_MinMaxCurrent::Min)), 25,
                "Min BaseValue should be 25");
            Step2_OverrideMax();
        }
    }

    UFUNCTION()
    private void OnMaxChanged(FCk_Handle InOwner, FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        _MaxFires++;

        if (_Step == 2)
        {
            Assert_Equals_Int(_MinFires, 1, "Min handler should still have only 1 fire after Max override");
            Assert_Equals_Int(int32(utils_byte_attribute::Get_BaseValue(_Power, ECk_MinMaxCurrent::Max)), 175,
                "Max BaseValue should be 175");
            FinishSuccess();
        }
    }

    UFUNCTION()
    private void OnCurrentChanged(FCk_Handle InOwner, FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        _CurrentFires++;
    }
}
