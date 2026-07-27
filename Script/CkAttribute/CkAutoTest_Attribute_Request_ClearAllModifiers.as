// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: REQUEST_CLEARALLMODIFIERS
//============================================================================
//
// Pins the `Request_ClearAllModifiers` contract: a single Clear call drops
// every Revocable modifier from the attribute, while Non-Revocable modifiers
// (Add/Mul) are PRESERVED on the BaseValue layer.
//
// Setup on Base=10 (signal-driven step machine to avoid coalescing).
// NotRev Add/Mul feed the BaseValue layer; Revocable mods stack on top as
// Bonus. So composition is `(Base + NotRev_Add) * NotRev_Mul + Revocable_Bonus`:
//   Step 1: Add_Revocable(+5)       -> Final = 10 + 5 = 15
//   Step 2: Add_Revocable(+7)       -> Final = 10 + 12 = 22
//   Step 3: Add_Revocable(+9)       -> Final = 10 + 21 = 31
//   Step 4: Add_NotRevocable(+4)    -> Final = 14 + 21 = 35
//   Step 5: Add_NotRevocable(Mul,2) -> Final = 14*2 + 21 = 49
//   Step 6: Request_ClearAllModifiers — revocables are dropped; NotRev Add(+4)
//                                       and NotRev Mul(*2) remain on the Base
//                                       layer. Final = (10+4)*2 + 0 = 28.
//                                       BonusValue (from revocables) = 0.
//
// We also pin that ClearAllModifiers fires ONE OnValueChanged (not one per
// dropped modifier) by resetting a counter immediately before the call and
// asserting it == 1 after the processor settles.
//
// NOTE: The audit `docs/superpowers/specs/test-coverage-backfill.md` documents
// the expected behavior as "Final drops back to BaseValue" (i.e. all modifier
// types cleared). The framework today only clears Revocables — if that is
// changed to also clear NotRev modifiers, update the post-Clear Final to 10.
//============================================================================

class UCk_AutoTest_Attribute_Request_ClearAllModifiers : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private int32 _Step = 0;
    private bool _Step1Observed = false;
    private bool _Step2Observed = false;
    private bool _Step3Observed = false;
    private bool _Step4Observed = false;
    private bool _Step5Observed = false;
    private bool _CountingForClear = false;
    private int32 _ClearSignalCount = 0;

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

        Step1_AddFiveRevocable();
    }

    private void Step1_AddFiveRevocable()
    {
        _Step = 1;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(5);
        utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_AddSevenRevocable()
    {
        _Step = 2;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(7);
        utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step3_AddNineRevocable()
    {
        _Step = 3;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(9);
        utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step4_AddFourNotRevocable()
    {
        _Step = 4;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(4);
        utils_integer_attribute_modifier::Add_NotRevocable(
            _Attribute,
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step5_MultiplyByTwoNotRevocable()
    {
        _Step = 5;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(2);
        utils_integer_attribute_modifier::Add_NotRevocable(
            _Attribute,
            ECk_AttributeModifier_Operation::Multiply,
            ModParams);
    }

    private void Step6_ClearAll()
    {
        _Step = 6;
        _ClearSignalCount = 0;
        _CountingForClear = true;
        utils_integer_attribute_modifier::Request_ClearAllModifiers(_Attribute, ECk_MinMaxCurrent::Current);
        WaitUntil(n"Check_ClearSignalFired", n"OnSettled_AfterClear");
    }

    UFUNCTION()
    private void Check_ClearSignalFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ClearSignalCount >= 1);
    }

    UFUNCTION()
    private void OnSettled_AfterClear(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 28,
            "After ClearAllModifiers, revocables are dropped but NotRev Add(+4)/Mul(*2) persist: (10+4)*2 = 28");
        Assert_Equals_Int(utils_integer_attribute::Get_BonusValue(_Attribute), 0,
            "After ClearAllModifiers, BonusValue (revocable contribution) should be 0");
        Assert_Equals_Int(_ClearSignalCount, 1,
            "ClearAllModifiers should fire exactly ONE OnValueChanged, not one per dropped modifier");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_CountingForClear)
        {
            _ClearSignalCount += 1;
            return;
        }

        if (_Step == 1 && _Step1Observed == false)
        {
            _Step1Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 15,
                "After Add_Revocable(+5), FinalValue should be 15");
            Step2_AddSevenRevocable();
            return;
        }

        if (_Step == 2 && _Step2Observed == false)
        {
            _Step2Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 22,
                "After Add_Revocable(+7), FinalValue should be 22");
            Step3_AddNineRevocable();
            return;
        }

        if (_Step == 3 && _Step3Observed == false)
        {
            _Step3Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 31,
                "After Add_Revocable(+9), FinalValue should be 31");
            Step4_AddFourNotRevocable();
            return;
        }

        if (_Step == 4 && _Step4Observed == false)
        {
            _Step4Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 35,
                "After Add_NotRevocable(Add,4), FinalValue should be 35");
            Step5_MultiplyByTwoNotRevocable();
            return;
        }

        if (_Step == 5 && _Step5Observed == false)
        {
            _Step5Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 49,
                "After Add_NotRevocable(Mul,2), FinalValue should be (Base+NotRev_Add)*NotRev_Mul + Revocable_Bonus = 14*2 + 21 = 49");
            Step6_ClearAll();
            return;
        }
    }
}
