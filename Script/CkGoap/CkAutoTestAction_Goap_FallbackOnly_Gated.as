// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: FALLBACK-ONLY — GATED CHAIN STEP
//============================================================================
//
// Cheap (cost 1.0) Action that produces Goal=true, but gated on a precondition
// (Unreachable=true) that no other Action in the catalog ever produces. From
// the planner's perspective the chain through this Action is structurally
// unreachable — only the Fallback can satisfy the goal.
//
// Used by FallbackWinsWhenChainBlocked to prove the fallback wins when its
// the only viable goal-satisfier in the catalog.
//============================================================================

class UCk_AutoTestAction_Goap_FallbackOnly_Gated : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.FallbackOnly.WS.Unreachable"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.FallbackOnly.WS.Goal"), true);
        SetCost(1.0);
    }
}
