// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: PARENT-FALLBACK PROBE-ONLY
//============================================================================
//
// The adversarial-ordering probe (AdversarialOrdering test). Key.Probe is
// referenced by THIS sub-action ONLY — never by a top-level action — so its
// residency is decided purely by whether the parent WS pre-registered it. A
// second referencing action would make the misclassification half of the test
// iteration-order flaky, which is the exact nondeterminism the test pins.
//============================================================================

class UCk_AutoTestAction_Goap_ParentFallback_ProbeOnly : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ParentFallback.Key.Probe"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ParentFallback.Key.Local"), true);
        SetCost(1.0);
    }
}
