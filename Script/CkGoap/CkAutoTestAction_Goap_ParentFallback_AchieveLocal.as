// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST ACTION: PARENT-FALLBACK ACHIEVE-LOCAL
//============================================================================
//
// Shared by the ParentFallback tests. Its keys straddle the residency split:
// the precondition (Key.Shared) is pre-registered on the PARENT WS, so setup
// classifies it as an import alias on the sub-WS; the effect (Key.Local) is
// referenced nowhere else, so it registers sub-local.
//============================================================================

class UCk_AutoTestAction_Goap_ParentFallback_AchieveLocal : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ParentFallback.Key.Shared"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ParentFallback.Key.Local"), true);
        SetCost(1.0);
    }
}
