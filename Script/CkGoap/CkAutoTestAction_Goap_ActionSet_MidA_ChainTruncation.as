// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: MID_A (ChainTruncation test)
//============================================================================
//
// Mid-level composite action A for the ChainTruncation test.
//
// CDO effects: AKey=true (satisfies Root's goal). Cost: 1.0 (cheaper than
// Mid_B at cost 2.0), so Root initially picks Mid_A.
//
// Mid_A is composite because Leaf_A is added as its child. This ensures
// ChainUpdate extends the chain to [Root, Mid_A] when Mid_A is chosen.
//
// After Request_SetActionCost bumps Mid_A's cost to 100, Root replans
// and picks Mid_B instead — triggering the chain truncation.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_MidA_ChainTruncation : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        SetCost(1.0);
    }
}
