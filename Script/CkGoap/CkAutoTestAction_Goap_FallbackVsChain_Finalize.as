// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST ACTION: FALLBACK-VS-CHAIN - FINALIZE STEP
//============================================================================
//
// Second step of the cheap chain. Precondition MidStep=true (provided by
// Setup); effect=Goal=true; cost 1.0. Total chain cost = 2.0, which must
// beat the Fallback's 999.0.
//============================================================================

class UCk_AutoTestAction_Goap_FallbackVsChain_Finalize : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.FallbackVsChain.WS.MidStep"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.FallbackVsChain.WS.Goal"), true);
        SetCost(1.0);
    }
}
