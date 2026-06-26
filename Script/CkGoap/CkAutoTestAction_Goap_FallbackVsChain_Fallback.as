// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: FALLBACK-VS-CHAIN — FALLBACK
//============================================================================
//
// The always-valid-plan tenet fallback. No preconditions; effect=Goal=true;
// cost 999.0. The whole point of FallbackLosesWhenChainViable is that the
// cheaper [Setup, Finalize] chain (cost 2.0) wins the A* search even though
// this fallback satisfies the goal trivially (no preconditions, single step).
//============================================================================

class UCk_AutoTestAction_Goap_FallbackVsChain_Fallback : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.FallbackVsChain.WS.Goal"), true);
        SetCost(999.0);
    }
}
