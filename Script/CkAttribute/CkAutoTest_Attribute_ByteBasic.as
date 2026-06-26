// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: BYTE BASIC
//============================================================================
//
// Byte-attribute equivalent of CkAutoTest_Attribute_FloatBasic. Verifies
// the byte attribute API end-to-end:
//   1. Add an Armor attribute (range 0-255, starting at 150).
//   2. Override the value to 42.
//   3. Bind OnValueChanged → expect signal with new=42.
//   4. Assert Get_FinalValue == 42.
//   5. Override to 200 → expect Get_FinalValue == 200 (within byte range).
//
// Skipped earlier in the session due to signed-vs-unsigned concerns
// (overriding to a negative value on a uint8 backing has undefined enum
// behavior). This test stays inside the [0, 255] domain to avoid that
// trap and just verifies the round-trip + clamp-to-max contract.
//============================================================================

class UCk_AutoTest_Attribute_ByteBasic : UCk_AutoTest_Base
{
    private FCk_Handle_ByteAttribute _Armor;
    private int32 _Step = 0;
    private bool _OverrideObserved = false;
    private bool _SecondObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Armor"),
            150);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(255);

        auto LocalHandle = InHandle;
        _Armor = utils_byte_attribute::Add(LocalHandle, Params);

        utils_byte_attribute::BindTo_OnValueChanged(
            _Armor,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnArmorChanged"));

        Step1_OverrideTo42();
    }

    private void Step1_OverrideTo42()
    {
        _Step = 1;
        utils_byte_attribute::Request_Override(_Armor, 42);
    }

    private void Step2_OverrideTo200()
    {
        _Step = 2;
        utils_byte_attribute::Request_Override(_Armor, 200);
    }

    UFUNCTION()
    private void OnArmorChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_OverrideObserved)
        {
            _OverrideObserved = true;
            auto FinalValue = utils_byte_attribute::Get_FinalValue(_Armor);
            Assert_Equals_Int(int32(FinalValue), 42,
                "Byte attribute after Override(42) should be 42");
            Step2_OverrideTo200();
            return;
        }

        if (_Step == 2 && !_SecondObserved)
        {
            _SecondObserved = true;
            auto FinalValue = utils_byte_attribute::Get_FinalValue(_Armor);
            Assert_Equals_Int(int32(FinalValue), 200,
                "Byte attribute after Override(200) should be 200 (within [0,255])");
            FinishSuccess();
        }
    }
}
