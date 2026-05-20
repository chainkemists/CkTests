// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: LEAF_A / DISTRACTOR (GoalIsEffects test)
//============================================================================
//
// Distractor leaf for the GoalIsEffects test. Effect: AKey=true.
// Mid's planner should NOT pick this leaf when Mid's goal is correctly
// set to {BKey=true} (Mid's own effects). If Mid's goal were incorrectly
// injected from Root's _GoalFromEffects ({AKey=true}), this leaf would
// be selected — exposing the regression.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        SetCost(1.0);
    }
}
