// Language=angelscript

//============================================================================
// CK ATTRIBUTE - AUTOMATION TEST: REVOKE MODIFIER DURING ON-VALUE-CHANGED
//============================================================================
//
// Pins re-entrancy safety for revocable modifier removal triggered from
// inside an OnValueChanged handler. The signal handler observes the *first*
// OnValueChanged (modifier added; FinalValue = 75) and immediately calls
// Remove() on the modifier. The framework must:
//
//   - Not crash / assert under re-entrant request.
//   - Process the revoke on a subsequent tick.
//   - Fire a *second* OnValueChanged whose FinalValue reflects revocation
//     (back to BaseValue = 50).
//
// Pattern A across two ticks. The Remove() request is enqueued from inside
// the first OnValueChanged callback; the processor drains it on the next
// tick and re-fires OnValueChanged for the now-revoked state.
//============================================================================

class UCk_AutoTest_Attribute_RevokeModifierDuringValueChanged : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private FCk_Handle_IntegerAttributeModifier _Modifier;
    private int32 _Step = 0;
    private bool _AddObserved = false;
    private bool _RemoveObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Damage"),
            50);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0);
        Params.Set_MaxValue(200);

        auto LocalHandle = InHandle;
        _Attribute = utils_integer_attribute::Add(LocalHandle, Params);

        utils_integer_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnValueChanged"));

        _Step = 1;
        auto ModParams = FCk_Fragment_IntegerAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(25);
        _Modifier = utils_integer_attribute_modifier::Add_Revocable(
            _Attribute,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        if (_Step == 1 && _AddObserved == false)
        {
            _AddObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 75,
                "After Add, FinalValue should be Base+Delta = 75");

            // Re-entrant revoke: enqueue Remove from inside the value-changed
            // signal handler. Framework must handle this safely.
            _Step = 2;
            utils_integer_attribute_modifier::Remove(_Modifier);
            return;
        }

        if (_Step == 2 && _RemoveObserved == false)
        {
            _RemoveObserved = true;
            Assert_Equals_Int(utils_integer_attribute::Get_BonusValue(_Attribute), 0,
                "After re-entrant Remove, BonusValue should be 0");
            Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 50,
                "After re-entrant Remove, FinalValue should be back to BaseValue (50)");
            FinishSuccess();
        }
    }
}
