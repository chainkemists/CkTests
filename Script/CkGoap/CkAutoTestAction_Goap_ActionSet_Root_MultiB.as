// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST ACTION: ROOT B (TwoPeerPlanners test)
//============================================================================
//
// Root action for Planner B in the TwoPeerPlanners test.
//   - Effect  : AutoTest.Goap.ActionSet.WS.BKey = true
//   - Goal    : _InitialGoal_RootOnly set to {BKey=true} in the test
//   - Cost    : 1.0
//
// WS is pre-set to BKey=true so the goal is immediately satisfied ->
// empty plan -> PlanFound. This keeps the two Planners symmetric and
// ensures they fire independently.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Root_MultiB : UCk_GoapAction_EntityScript
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
