// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: BYTE MODIFIER REMOVE
//============================================================================
//
// Byte-side parity with CkAutoTest_Attribute_IntegerModifierRemove. Verifies
// that removing a previously-added revocable modifier restores the attribute's
// FinalValue to the base value (BonusValue back to 0).
//
// Pattern: add modifier, wait for OnValueChanged (Step 1: confirms add). Then
// remove modifier, wait for OnValueChanged again (Step 2: confirms removal).
//============================================================================

class UCk_AutoTest_Attribute_ByteModifierRemove : UCk_AutoTest_Base
{
    private FCk_Handle_ByteAttribute _Armor;
    private FCk_Handle_ByteAttributeModifier _Modifier;
    private int32 _Step = 0;
    private bool _AddObserved = false;
    private bool _RemoveObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_Fragment_ByteAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Armor"),
            100);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(255);

        auto LocalHandle = InHandle;
        _Armor = utils_byte_attribute::Add(LocalHandle, Params);

        utils_byte_attribute::BindTo_OnValueChanged(
            _Armor,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_ByteAttribute_OnValueChanged(this, n"OnValueChanged"));

        Step1_AddModifier();
    }

    private void Step1_AddModifier()
    {
        _Step = 1;

        auto ModParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(25);
        _Modifier = utils_byte_attribute_modifier::Add_Revocable(
            _Armor,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Plate"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    private void Step2_RemoveModifier()
    {
        _Step = 2;
        utils_byte_attribute_modifier::Remove(_Modifier);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_ByteAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && !_AddObserved)
        {
            _AddObserved = true;
            Assert_Equals_Int(int32(utils_byte_attribute::Get_FinalValue(_Armor)), 125,
                "After Add, FinalValue should be 125");
            Step2_RemoveModifier();
            return;
        }

        if (_Step == 2 && !_RemoveObserved)
        {
            _RemoveObserved = true;
            Assert_Equals_Int(int32(utils_byte_attribute::Get_BonusValue(_Armor)), 0,
                "After Remove, BonusValue should be 0");
            Assert_Equals_Int(int32(utils_byte_attribute::Get_FinalValue(_Armor)), 100,
                "After Remove, FinalValue should be back to BaseValue (100)");
            FinishSuccess();
        }
    }
}
