// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: NOT-REVOCABLE ADD COALESCES
//============================================================================
//
// Pins the Add coalescing contract from CkAttribute/CLAUDE.md:
//
//   | Add / Subtract | Accumulate — deltas sum into one modifier |
//
// `Add_NotRevocable` with `ECk_AttributeModifier_Operation::Add` is expected
// to find the existing non-revocable Add modifier on the attribute and SUM
// the new delta into it (one modifier entity, accumulated delta) — not
// create a second modifier entity.
//
// On Base=10:
//   Step 1: Add_NotRevocable(Add, 5) -> Final = 10 + 5 = 15
//   Step 2: Add_NotRevocable(Add, 7) -> deltas coalesce to 12,
//                                       Final = 10 + 12 = 22
//
// Note: NotRevocable Add modifiers feed into the BaseValue layer (not the
// revocable BonusValue layer), so BonusValue stays at 0 throughout — Final
// is the discriminator pinned here.
//
// Pattern A (signal-driven step machine), per gotcha #10.
//============================================================================

class UCk_AutoTest_Attribute_NotRevocable_AddCoalesces : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private int32 _Step = 0;
    private bool _Step1Observed = false;
    private bool _Step2Observed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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

        Step1_AddFive();
    }

    private void Step1_AddFive()
    {
        _Step = 1;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(5);
        utils_integer_attribute_modifier::Add_NotRevocable(
            _Attribute,
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_AddSeven()
    {
        _Step = 2;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(7);
        utils_integer_attribute_modifier::Add_NotRevocable(
            _Attribute,
            ECk_AttributeModifier_Operation::Add,
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
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 15,
                "After Add_NotRevocable(Add, 5), FinalValue should be 15");
            Step2_AddSeven();
            return;
        }

        if (_Step == 2 && _Step2Observed == false)
        {
            _Step2Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 22,
                "After second Add_NotRevocable(Add, 7), FinalValue should be 22 (deltas sum to 12)");
            FinishSuccess();
        }
    }
}
