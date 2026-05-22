// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: TRIVIAL "DO IT" ACTION
//============================================================================
//
// Single action used by the Planner smoke test:
//   - Pre      : AutoTest.Goap.ActionSet.WS.Ready = false
//   - Effect   : AutoTest.Goap.ActionSet.WS.Ready = true
//   - Cost     : 1.0
//
// Identity tag is class-derived (UCk_GoapAction_EntityScript::
// Get_ActionTagForClass) — no SetActionTag call needed in the unified model.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Simple : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.Ready"), false);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.Ready"), true);
        SetCost(1.0);
    }
}
