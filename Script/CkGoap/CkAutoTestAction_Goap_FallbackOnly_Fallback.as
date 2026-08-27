// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST ACTION: FALLBACK-ONLY - FALLBACK
//============================================================================
//
// Always-valid-plan tenet fallback for the FallbackOnly test catalog. No
// preconditions; effect=Goal=true; cost 999.0. Wins because the only other
// goal-satisfier (Gated) is precondition-blocked and no Action produces the
// gate's required key.
//============================================================================

class UCk_AutoTestAction_Goap_FallbackOnly_Fallback : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.FallbackOnly.WS.Goal"), true);
        SetCost(999.0);
    }
}
