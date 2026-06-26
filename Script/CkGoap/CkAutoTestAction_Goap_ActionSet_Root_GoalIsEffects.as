// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: ROOT (GoalIsEffects test)
//============================================================================
//
// Root action for the GoalIsEffects test.
//
// CDO effects: AKey=true  — forms Root's _GoalFromEffects (NOT used for
// Root's own planning since _InitialGoal_RootOnly is set explicitly).
// The test uses _InitialGoal_RootOnly={BKey=true} so Root's planner
// searches for an operator that achieves BKey. The DISTINCT AKey effect
// on this CDO means: if Mid's goal were incorrectly injected from Root's
// _GoalFromEffects (AKey=true) instead of Mid's own effects (BKey=true),
// Mid would pick Leaf_A instead of Leaf_B — detectable divergence.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects : UCk_GoapAction_EntityScript
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
