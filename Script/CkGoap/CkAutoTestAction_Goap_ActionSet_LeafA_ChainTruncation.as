// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: LEAF_A (ChainTruncation test)
//============================================================================
//
// Leaf action for Mid_A in the ChainTruncation test.
//
// Effect: AKey=true (satisfies Mid_A's goal, which is derived from Mid_A's
// own effects: AKey=true). Atomic (no children). Makes Mid_A composite by
// being added as its child.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_LeafA_ChainTruncation : UCk_GoapAction_EntityScript
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
