// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: TRIVIAL "DO IT" ACTION
//============================================================================
//
// Single-step action used by the ActionSet_RootOnly smoke test:
//   - ActionTag : AutoTest.Goap.ActionSet.Action.Simple
//   - Pre      : AutoTest.Goap.ActionSet.WS.Ready = false
//   - Effect   : AutoTest.Goap.ActionSet.WS.Ready = true
//   - Cost     : 1.0
//
// When the root tier's goal is Ready=true and WS starts with Ready=false,
// the planner should pick this action and produce a 1-element plan.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Simple : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        SetActionTag(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.Action.Simple"));
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.Ready"), false);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.Ready"), true);
        SetCost(1.0);
    }
}
