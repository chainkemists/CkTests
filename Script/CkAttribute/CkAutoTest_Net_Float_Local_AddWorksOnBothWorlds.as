// Language=angelscript

//============================================================================
// CK ATTRIBUTE - NET AUTOMATION TEST: LOCAL FLOAT ADD WORKS ON BOTH WORLDS
//============================================================================
//
// First test of the `ServerAndClientsIndependent` netmode. The harness sets
// up multi-PIE just like the Replicated tests do, but this test exercises a
// feature that doesn't *use* replication - a `DoesNotReplicate` Float
// attribute added locally to each world's TransientEntity.
//
// What this proves: the same code path that works on a server-side world
// must also work on a client-side world. Lots of CkFoundation behaviour is
// purely local (UI, transient state, non-replicated values). It can break in
// subtle ways under NetMode_Client - e.g. processors gated to authority,
// validators that skip on client worlds, etc. - that single-PIE Standalone
// tests can't catch. Running the same body on both worlds in parallel
// catches that class of regression.
//
// Author contract: each world's body runs independently. No `Get_SubjectEntity`,
// no cross-world handle lookup, no NetSubject actor in the C++ stub. The body
// uses InHandle (its own per-world TransientEntity child) and operates locally.
//============================================================================

class UCk_AutoTest_Net_Float_Local_AddWorksOnBothWorlds : UCk_AutoTest_NetBase
{
    // Independent mode - no cross-world coordination expected. Each PIE world runs DoBeginPlay
    // independently against its own ECS state.
    // default _NetMode = ECk_AutoTest_NetMode::ServerAndClientsIndependent;

    private FName _AttributeTagName = n"FloatAttribute.Health";
    private float32 _InitialValue = 42.5f;
    private float32 _OverrideValue = 75.0f;

    // Stored across the OnValueChanged signal so the callback can read it back without a
    // re-lookup.
    private FCk_Handle_FloatAttribute _Attribute;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Params = FCk_Fragment_FloatAttribute_ParamsData(Tag, _InitialValue);
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(0.0f);
        Params.Set_MaxValue(100.0f);

        // DoesNotReplicate is the whole point - exercise the non-replicated path on a world
        // that may not be authority. If a "client-side never runs this" regression sneaks in,
        // this assertion catches it on the client PIE world before Standalone ever does.
        _Attribute = utils_float_attribute::Add(LocalHandle, Params, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(_Attribute))
        {
            FinishFailure("local Add returned invalid - non-replicated attribute setup broken on this world");
            return;
        }

        auto InitialReadback = utils_float_attribute::Get_FinalValue(_Attribute, ECk_MinMaxCurrent::Current);
        Assert_True(InitialReadback == _InitialValue,
            f"initial FinalValue should match (expected {_InitialValue}, got {InitialReadback})");

        // Signal-driven wait - fires exactly when the attribute's value changes, no race with
        // tick scheduling. Mirrors the pattern used by the standalone CkAutoTest_Attribute_FloatBasic
        // test. A WaitOneFrame timer (0.05s) can race the override-application processor under
        // PIE's faster-than-20fps tick rate and read the stale value.
        utils_float_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_FloatAttribute_OnValueChanged(this, n"OnLocalValueChanged"));

        _Attribute.Request_Override(_OverrideValue, ECk_MinMaxCurrent::Current);
    }

    UFUNCTION()
    private void OnLocalValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_FloatAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        auto OverrideReadback = utils_float_attribute::Get_FinalValue(_Attribute, ECk_MinMaxCurrent::Current);
        Assert_True(OverrideReadback == _OverrideValue,
            f"local FinalValue after Request_Override should match (expected {_OverrideValue}, got {OverrideReadback})");

        FinishSuccess();
    }
}
