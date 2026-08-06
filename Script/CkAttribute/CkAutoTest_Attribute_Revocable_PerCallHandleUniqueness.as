// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: REVOCABLE PER-CALL HANDLE UNIQUENESS
//============================================================================
//
// Pins the Revocable-modifier contract from CkAttribute/CLAUDE.md:
//
//   `Add_Revocable` always creates a *new* modifier entity per call. Use
//   for stackable equipment buffs, temporary status effects.
//
// On Base=10, three Add_Revocable(Add, ...) calls with distinct deltas
// (5, 7, 9) must produce three INDEPENDENT modifiers — verified by:
//   1. The three returned modifier handles each carry their own delta
//      (Get_Delta returns 5, 7, 9 respectively).
//   2. FinalValue stacks all three: 10 + 5 + 7 + 9 = 31.
//   3. Removing the middle modifier leaves the other two intact —
//      FinalValue drops to 10 + 5 + 9 = 24, and the surviving modifier
//      handles still pass Has() checks.
//
// If revocable modifiers coalesced (like non-revocable), the deltas would
// merge into one entity and removing one would clear the lot.
//
// Pattern A (signal-driven step machine), per gotcha #10.
//============================================================================

class UCk_AutoTest_Attribute_Revocable_PerCallHandleUniqueness : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private FCk_Handle_IntegerAttributeModifier _Mod1;
    private FCk_Handle_IntegerAttributeModifier _Mod2;
    private FCk_Handle_IntegerAttributeModifier _Mod3;
    private int32 _Step = 0;
    private bool _Step1Observed = false;
    private bool _Step2Observed = false;
    private bool _Step3Observed = false;
    private bool _Step4Observed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_IntegerAttribute_Spec(
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

        Step1_AddFirst();
    }

    private void Step1_AddFirst()
    {
        _Step = 1;
        auto ModParams = FCk_IntegerAttributeModifier_Spec();
        ModParams.Set_ModifierDelta(5);
        _Mod1 = utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_AddSecond()
    {
        _Step = 2;
        auto ModParams = FCk_IntegerAttributeModifier_Spec();
        ModParams.Set_ModifierDelta(7);
        _Mod2 = utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Buff"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step3_AddThird()
    {
        _Step = 3;
        auto ModParams = FCk_IntegerAttributeModifier_Spec();
        ModParams.Set_ModifierDelta(9);
        _Mod3 = utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step4_RemoveMiddle()
    {
        _Step = 4;
        utils_integer_attribute_modifier::Remove(_Mod2);
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
                "After Add_Revocable(+5), FinalValue should be 15");
            Step2_AddSecond();
            return;
        }

        if (_Step == 2 && _Step2Observed == false)
        {
            _Step2Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 22,
                "After Add_Revocable(+7), FinalValue should stack to 22");
            Step3_AddThird();
            return;
        }

        if (_Step == 3 && _Step3Observed == false)
        {
            _Step3Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 31,
                "After Add_Revocable(+9), FinalValue should stack to 31");

            Assert_Equals_Int(utils_integer_attribute_modifier::Get_Delta(_Mod1),
                5, "Mod1 should carry its own delta of 5");
            Assert_Equals_Int(utils_integer_attribute_modifier::Get_Delta(_Mod2),
                7, "Mod2 should carry its own delta of 7");
            Assert_Equals_Int(utils_integer_attribute_modifier::Get_Delta(_Mod3),
                9, "Mod3 should carry its own delta of 9");

            Step4_RemoveMiddle();
            return;
        }

        if (_Step == 4 && _Step4Observed == false)
        {
            _Step4Observed = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 24,
                "After Remove(Mod2), FinalValue should drop to 10+5+9 = 24");
            Assert_Equals_Int(utils_integer_attribute_modifier::Get_Delta(_Mod1), 5,
                "Mod1 should remain intact after Remove(Mod2) with its original delta of 5");
            Assert_Equals_Int(utils_integer_attribute_modifier::Get_Delta(_Mod3), 9,
                "Mod3 should remain intact after Remove(Mod2) with its original delta of 9");
            FinishSuccess();
        }
    }
}
