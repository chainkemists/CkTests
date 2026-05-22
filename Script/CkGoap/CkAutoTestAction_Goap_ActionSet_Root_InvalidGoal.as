// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: ROOT (InvalidGoal test)
//============================================================================
//
// Root action for the InvalidGoal test. Effect: Ready=true. Used purely as
// a class reference for SetRootAction; its CDO registers the Ready key in
// the WS. No goal set on PlannerParams, so the root plans with an empty
// goal (immediately PlanFound with empty plan). The test overrides the goal
// via utils_goap_planner::Request_SetGoal with an unregistered key to populate
// _InvalidGoal diagnostics.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Root_InvalidGoal : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.Ready"), true);
        SetCost(1.0);
    }
}
