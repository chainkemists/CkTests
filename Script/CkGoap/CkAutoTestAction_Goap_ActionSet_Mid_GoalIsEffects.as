// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: MID / COMPOSITE (GoalIsEffects test)
//============================================================================
//
// Mid-level composite action for the GoalIsEffects test.
//
// CDO effects: BKey=true — this is also Mid's _GoalFromEffects. When Mid
// activates, ChainUpdate injects this as Mid's runtime goal, so Mid's
// planner searches for an operator that achieves BKey=true. The correct
// leaf to pick is Leaf_B (effect BKey=true), NOT Leaf_A (effect AKey=true).
//
// If ChainUpdate were buggy and injected Root's _GoalFromEffects (AKey=true)
// instead, Mid's planner would pick Leaf_A — discriminating the regression.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects : UCk_GoapAction_EntityScript
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
