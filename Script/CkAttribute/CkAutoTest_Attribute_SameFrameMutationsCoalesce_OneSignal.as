// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: SAME-FRAME MUTATIONS COALESCE TO ONE SIGNAL
//============================================================================
//
// Pins the documented coalescing-before-signal contract from
// CkAttribute/CLAUDE.md anti-pattern #3:
//
//   Two `Request_Override(attr, A)` then `Request_Override(attr, B)` in the
//   same tick produce a single processor pass that sees only `B` — you get
//   ONE `OnValueChanged` reflecting `B`. The `A` mutation is silently
//   overwritten in the modifier.
//
// This is the WRONG-shape pattern documented in CkAutoTest creation spec
// gotcha #10 — pinned here as an explicit regression test so a future change
// that fired one-signal-per-Request_Override would be caught.
//
// On Base=10:
//   Same tick: Request_Override(attr, 50); Request_Override(attr, 30);
//   Processor sees only the final mutation (30) → ONE OnValueChanged.
//   Final == 30, signal count == 1.
//============================================================================

class UCk_AutoTest_Attribute_SameFrameMutationsCoalesce_OneSignal : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _Attribute;
    private int32 _SignalCount = 0;
    private bool _MutationsFired = false;

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

        // Let any initial-setup signals from Add drain BEFORE we bind, so they
        // cannot inflate the count this test exists to pin at 1. Deliberately a
        // frame settle, not a condition: the attribute's base value is written
        // at Add, so a value predicate would return on its first poll and defeat
        // the isolation this wait provides. Frames are the unit the processor
        // pass advances in; the 0.05s timer this replaces was wall-clock.
        WaitFrames(2, n"OnSettled_BeforeBind");
    }

    UFUNCTION()
    private void OnSettled_BeforeBind(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        utils_integer_attribute::BindTo_OnValueChanged(
            _Attribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnValueChanged"));

        // Two Request_Override calls in the SAME tick — the second should
        // overwrite the first in the persistent non-revocable Override
        // modifier before any processor sees the first.
        utils_integer_attribute::Request_Override(_Attribute, 50, ECk_MinMaxCurrent::Current);
        utils_integer_attribute::Request_Override(_Attribute, 30, ECk_MinMaxCurrent::Current);
        _MutationsFired = true;

        // The coalesced signal arriving is the settling event; that it arrives
        // exactly ONCE is the contract and stays an assertion, so a
        // one-signal-per-Override regression is reported rather than hanging.
        WaitUntil(n"Check_SignalFired", n"OnSettled_AfterFire");
    }

    UFUNCTION()
    private void Check_SignalFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_SignalCount >= 1);
    }

    UFUNCTION()
    private void OnSettled_AfterFire(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SignalCount, 1,
            "Two same-tick Request_Override calls should fire exactly ONE OnValueChanged");
        Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_Attribute), 30,
            "Single coalesced signal should carry the second (latest) value 30");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (_MutationsFired == false) { return; }
        _SignalCount += 1;
    }
}
