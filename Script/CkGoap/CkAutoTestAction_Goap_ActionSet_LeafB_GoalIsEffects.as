// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: LEAF_B (GoalIsEffects test)
//============================================================================
//
// Correct leaf for the GoalIsEffects test. Effect: BKey=true.
// Mid's goal (from Mid's own effects) is {BKey=true}, so the planner
// picks Leaf_B when Mid's goal is correctly set from Mid's own effects.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.BKey"), true);
        SetCost(1.0);
    }
}
