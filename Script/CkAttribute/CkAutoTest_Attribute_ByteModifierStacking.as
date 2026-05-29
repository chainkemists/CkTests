// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: BYTE MODIFIER STACKING
//============================================================================
//
// Byte-side parity with CkAutoTest_Attribute_IntegerModifierStacking. Verifies
// two distinct revocable additive modifiers stack (their deltas sum into
// BonusValue), and that removing one leaves the other intact.
//   1. Base 100. Add +25 (Weapon) and +10 (Plate) -> Final 135, Bonus 35.
//   2. Remove Weapon -> Final 110, Bonus 10.
//
// Both modifiers are added in the same frame; their OnValueChanged signals
// coalesce into one, so Step 1 asserts the combined result after a single fire.
//============================================================================

class UCk_AutoTest_Attribute_ByteModifierStacking : UCk_AutoTest_Base
{
    private FCk_Handle_ByteAttribute _Armor;
    private FCk_Handle_ByteAttributeModifier _WeaponMod;
    private int32 _Step = 0;
    private bool _AddObserved = false;
    private bool _RemoveObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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

        Step1_AddBothModifiers();
    }

    private void Step1_AddBothModifiers()
    {
        _Step = 1;

        auto WeaponParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        WeaponParams.Set_ModifierDelta(25);
        _WeaponMod = utils_byte_attribute_modifier::Add_Revocable(
            _Armor,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Weapon"),
            ECk_AttributeModifier_Operation::Add,
            WeaponParams);

        auto PlateParams = FCk_Fragment_ByteAttributeModifier_ParamsData();
        PlateParams.Set_ModifierDelta(10);
        utils_byte_attribute_modifier::Add_Revocable(
            _Armor,
            utils_gameplay_tag::ResolveGameplayTag(n"Modifier.Plate"),
            ECk_AttributeModifier_Operation::Add,
            PlateParams);
    }

    private void Step2_RemoveWeapon()
    {
        _Step = 2;
        utils_byte_attribute_modifier::Remove(_WeaponMod);
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
            Assert_Equals_Int(int32(utils_byte_attribute::Get_BonusValue(_Armor)), 35,
                "Two stacked additive modifiers should sum to BonusValue 35");
            Assert_Equals_Int(int32(utils_byte_attribute::Get_FinalValue(_Armor)), 135,
                "FinalValue should be Base+Bonus = 135");
            Step2_RemoveWeapon();
            return;
        }

        if (_Step == 2 && !_RemoveObserved)
        {
            _RemoveObserved = true;
            Assert_Equals_Int(int32(utils_byte_attribute::Get_BonusValue(_Armor)), 10,
                "After removing Weapon, only Plate's +10 remains");
            Assert_Equals_Int(int32(utils_byte_attribute::Get_FinalValue(_Armor)), 110,
                "FinalValue should be 110 after removing Weapon");
            FinishSuccess();
        }
    }
}
