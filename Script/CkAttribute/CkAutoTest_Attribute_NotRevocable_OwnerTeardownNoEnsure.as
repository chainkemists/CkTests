// Language=angelscript

//============================================================================
// CK ATTRIBUTE - AUTOMATION TEST: NOT-REVOCABLE COALESCE DURING OWNER TEARDOWN
//============================================================================
//
// Regression pin for the owner-aware pending-destroy guard in
// TUtils_AttributeModifier::Add_NotRevocable (CkAttribute_Utils.inl.h).
//
// Add_NotRevocable coalesces into an existing NotRevocable modifier of the
// same operation. If that modifier's owning attribute is being torn down this
// frame, entity-lifetime cascade stamps the attribute AND its child modifiers
// pending-destroy synchronously. A same-frame Add_NotRevocable then finds a
// pending-destroy coalesce target - which is BENIGN (the whole attribute is
// going away, the write is moot) and must NOT ensure.
//
// This reproduces exactly what happens in the wild when an attribute's owner
// is destroyed the same frame something writes the attribute - e.g. the Float
// refill processor (TProcessor_Attribute_Refill) applying its per-tick
// Add_NotRevocable to an attribute whose owner just got destroyed, or an item's
// StackCount being adjusted the frame the item entity is removed.
//
// PASS CONDITION: no CkEnsure Error is logged. The automation framework
// captures Error-level log output and fails the test on it (spec GOTCHA 1), so
// a spurious tripwire firing here fails this test automatically. Pre-fix this
// test fails (the guard ensured unconditionally); post-fix it passes.
//
// Pattern A (signal-driven step machine): step 1 creates the modifier via the
// first Add_NotRevocable, and OnValueChanged guarantees the modifier ENTITY
// exists before step 2 destroys the owner and coalesces into the doomed target.
//============================================================================

class UCk_AutoTest_Attribute_NotRevocable_OwnerTeardownNoEnsure : UCk_AutoTest_Base
{
    private FCk_Handle              _Owner;
    private FCk_Handle_FloatAttribute _Attribute;
    private int32 _Step = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto LocalHandle = InHandle;
        _Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Params = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.Damage"),
            50.0f);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0.0f);
        Params.Set_MaxValue(200.0f);
        _Attribute = utils_float_attribute::Add(_Owner, Params);

        utils_float_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnValueChanged"));

        _Step = 1;
        AddNotRevocable(5.0f);
    }

    private void AddNotRevocable(float32 InDelta)
    {
        auto ModParams = FCk_Fragment_FloatAttributeModifier_ParamsData();
        ModParams.Set_ModifierDelta(InDelta);
        utils_float_attribute_modifier::Add_NotRevocable(
            _Attribute,
            ECk_AttributeModifier_Operation::Add,
            ModParams);
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (_Step != 1) { return; }
        _Step = 2;

        // The NotRevocable Add modifier now exists. Destroy the owner: cascade
        // stamps the owner, the attribute and the modifier pending-destroy this
        // same frame. The following Add_NotRevocable finds the doomed modifier
        // as its coalesce target - the exact tripwire condition. With the
        // owner-aware guard it drops the moot write silently (no ensure); without
        // it, an ensure fires and the framework fails this test.
        utils_entity_lifetime::Request_DestroyEntity(_Owner);
        AddNotRevocable(7.0f);

        FinishSuccess();
    }
}
