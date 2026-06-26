// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: FALLBACK-VS-CHAIN — SETUP STEP
//============================================================================
//
// First step of the cheap chain that beats the high-cost fallback. No
// preconditions; effect=MidStep=true; cost 1.0. Paired with Finalize (which
// gates on MidStep=true and produces Goal=true).
//============================================================================

class UCk_AutoTestAction_Goap_FallbackVsChain_Setup : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.FallbackVsChain.WS.MidStep"), true);
        SetCost(1.0);
    }
}
