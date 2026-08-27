// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST ACTION: MID_B (ChainTruncation test)
//============================================================================
//
// Mid-level composite action B for the ChainTruncation test.
//
// CDO effects: AKey=true (satisfies Root's goal). Cost: 2.0 (more expensive
// than Mid_A at cost 1.0), so Root initially skips Mid_B in favour of Mid_A.
//
// Mid_B is composite because Leaf_B is added as its child. This ensures
// ChainUpdate can extend the chain to [Root, Mid_B] when Mid_B is chosen
// after the replan triggered by the Mid_A cost bump.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_MidB_ChainTruncation : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        SetCost(2.0);
    }
}
