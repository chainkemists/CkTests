// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: ROOT A (MultiActionSet test)
//============================================================================
//
// Root action for ActionSet A in the MultiActionSet test.
//   - Effect  : AutoTest.Goap.ActionSet.WS.AKey = true
//   - Goal    : _InitialGoal_RootOnly set to {AKey=true} in the test
//   - Cost    : 1.0
//
// WS starts AKey=false → planner finds an empty plan (effect already
// matches goal once WS is pre-seeded with AKey=true) or a non-empty plan
// depending on the test setup. For MultiActionSet the WS is pre-set to
// AKey=true so the goal is immediately satisfied → empty plan → PlanFound.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Root_MultiA : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        SetCost(1.0);
    }
}
