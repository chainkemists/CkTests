// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: NOT-REVOCABLE OVERRIDE REPLACES
//============================================================================
//
// Pins the Override coalescing contract from CkAttribute/CLAUDE.md:
//
//   | Override | Replace — latest value wins |
//
// `Add_NotRevocable` with `ECk_AttributeModifier_Operation::Override` is
// expected to find the existing non-revocable Override modifier on the
// attribute and REPLACE its delta — not stack, not sum, not compose.
//
// On Base=10:
//   Step 1: Add_NotRevocable(Override, 50) -> Final = 50
//   Step 2: Add_NotRevocable(Override, 30) -> Final = 30 (not 80, not 50)
//
// If Override stacked or composed, Step 2 would yield 80 or some product.
// Asserting Final == 30 after Step 2 pins "latest-wins" semantics.
//
// Pattern A (signal-driven step machine), per gotcha #10.
//
// Note: Override is unavailable as a Revocable operation (the binding has
// `InvalidEnumValues="Override"` on Add_Revocable). This contract is
// therefore only exercised through Add_NotRevocable.
//============================================================================

class UCk_AutoTest_Attribute_NotRevocable_OverrideReplaces : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private int32 _Step = 0;
    private bool _Step1Observed = false;
    private bool _Step2Observed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Damage"),
            10);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(1000);

        auto LocalHandle = InHandle;
        _Attribute = utils_integer_attribute::Add(LocalHandle, Params);

        utils_integer_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnValueChanged"));

        Step1_OverrideFifty();
    }

    private void Step1_OverrideFifty()
    {
        _Step = 1;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(50);
        utils_integer_attribute_modifier::Add_NotRevocable(
            _Attribute,
            ECk_AttributeModifier_Operation::Override,
            ModParams);
    }

    private void Step2_OverrideThirty()
    {
        _Step = 2;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(30);
        utils_integer_attribute_modifier::Add_NotRevocable(
            _Attribute,
            ECk_AttributeModifier_Operation::Override,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && _Step1Observed == false)
        {
            _Step1Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 50,
                "After Add_NotRevocable(Override, 50), FinalValue should be 50");
            Step2_OverrideThirty();
            return;
        }

        if (_Step == 2 && _Step2Observed == false)
        {
            _Step2Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 30,
                "After Override(30) following Override(50), FinalValue should replace to 30 (not 80, not 50)");
            FinishSuccess();
        }
    }
}
