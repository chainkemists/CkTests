// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: LEAF_B (ChainTruncation test)
//============================================================================
//
// Leaf action for Mid_B in the ChainTruncation test.
//
// Effect: AKey=true (satisfies Mid_B's goal, which is derived from Mid_B's
// own effects: AKey=true). Atomic (no children). Makes Mid_B composite by
// being added as its child.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_LeafB_ChainTruncation : UCk_GoapAction_EntityScript
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
