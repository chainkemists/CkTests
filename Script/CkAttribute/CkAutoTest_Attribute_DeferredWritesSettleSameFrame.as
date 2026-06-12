// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: DEFERRED WRITES SETTLE SAME FRAME (PUMP)
//============================================================================
//
// Pins the scheduler-pump contract for the attribute pipeline: a modifier
// write issued AFTER the attribute composites' main-pass slot (EntityScript
// BeginPlay runs in FGroup_Gameplay_Script, after FGroup_Gameplay) must fold
// AND clamp within the SAME frame via pump passes — so a single WaitOneFrame
// suffices to read the exact settled value. No poll-until-settled loop on
// purpose: this test exists to fail if the attribute composites ever lose
// their pump eligibility again.
//
// Regression guard for: registered attribute composite processors carried
// Tick()/Pump() methods but no MarkedDirtyBy alias, so the scheduler never
// pumped them — folds were strictly once-per-frame at the composites' slot,
// and readers positioned before that slot (timer callbacks!) observed
// pre-fold values one frame late (empirically traced 2026-06-12; see
// docs/superpowers/reviews/2026-06-10-CkInventory-audit.md §3.1 correction).
//
// Two families on purpose: the clamp marker is family-typed, and each
// family's MinMaxClamp composite consumes it with a family-scoped Clear.
// Both families clamping correctly in one frame pins that one family's
// consume cannot eat the other family's pending clamp.
//
//============================================================================

class UCk_AutoTest_Attribute_DeferredWritesSettleSameFrame : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute _IntAttribute;
    private FCk_Handle_FloatAttribute _FloatAttribute;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto IntParams = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.AutoTest_PumpSettle"),
            5);
        IntParams.Set_MinMax(ECk_MinMax::MinMax);
        IntParams.Set_MinValue(0);
        IntParams.Set_MaxValue(20);
        _IntAttribute = utils_integer_attribute::Add(LocalHandle, IntParams);

        auto FloatParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"FloatAttribute.AutoTest_PumpSettle"),
            5.0f);
        FloatParams.Set_MinMax(ECk_MinMax::MinMax);
        FloatParams.Set_MinValue(0.0f);
        FloatParams.Set_MaxValue(30.0f);
        _FloatAttribute = utils_float_attribute::Add(LocalHandle, FloatParams);

        // Both writes exceed Max — settling requires the full pipeline to pump:
        // recompute -> modifier fold -> clamp (-> signals), per family.
        utils_integer_attribute::Request_Override(_IntAttribute, 50);
        utils_float_attribute::Request_Override(_FloatAttribute, 100.0f);

        // ONE frame, no polling — the contract under test.
        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(_IntAttribute), 20,
            "Integer override past Max must be folded AND clamped within one frame (pump-eligible pipeline)");

        auto FloatFinal = utils_float_attribute::Get_FinalValue(_FloatAttribute);
        Assert_True(FloatFinal == 30.0f,
            f"Float override past Max must be folded AND clamped within one frame (got {FloatFinal}, expected 30.0)");

        FinishSuccess();
    }
}
