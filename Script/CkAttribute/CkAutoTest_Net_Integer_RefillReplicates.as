// Language=angelscript

//============================================================================
// CK ATTRIBUTE — NET AUTOMATION TEST: INTEGER REFILL REPLICATES
//============================================================================
//
// Integer parity with the C++ Float_Refill_Replicates spec. Refill is a
// continuous per-tick value change (in contrast to the discrete one-shot
// Override / ModifierAdd mutations), and rides the same templated refill +
// FCk_RepData_IntegerAttributes container-replication path as Float.
//
// The refill subject's entity-script adds a replicated IntegerAttribute.AutoTest_Energy
// (initial 0, refill 20/s, Min 0 / Max 100, StartingState Running) on both
// worlds. No mutation is issued — the refill processor drives the value up on
// the authoritative world and the container fragment carries the climbing
// value to the client. Both worlds poll until the energy attribute has risen
// clear of its initial value.
//============================================================================

class UCk_AutoTest_Net_Integer_RefillReplicates : UCk_AutoTest_NetBase
{
    // Refill-enabled subject (its entity-script adds the Float + Integer energy attributes).
    default _NetSubjectClass = ACk_AutoTest_NetSubject_Refill;

    private FName _AttributeTagName = n"IntegerAttribute.AutoTest_Energy";

    // Initial value is 0; refill at 20/s saturates toward Max=100. A threshold of 5 is
    // comfortably above the initial and reached within a few ticks, while staying well below
    // saturation so the assertion fires before clamping flattens the signal.
    private int _MinExpectedValue = 5;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Attribute = utils_integer_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        { FinishFailure("Integer refill attribute not found on subject"); return; }

        // No authority branch — refill runs automatically on the authoritative world and the
        // climbing value replicates. Both worlds poll for the same observable: value rose above
        // the initial. (Server confirms the refill processor ran; client confirms it replicated.)
        WaitOneFrame(n"OnPollValue");
    }

    UFUNCTION()
    private void OnPollValue(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { WaitOneFrame(n"OnPollValue"); return; }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_AttributeTagName);
        auto Attribute = utils_integer_attribute::TryGet(Subject, Tag);
        if (ck::Is_NOT_Valid(Attribute))
        { WaitOneFrame(n"OnPollValue"); return; }

        if (utils_integer_attribute::Get_FinalValue(Attribute) > _MinExpectedValue)
        {
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollValue");
    }
}
