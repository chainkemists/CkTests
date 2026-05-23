// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: WSOverrideStack OpA
//============================================================================
//
// Operator A for the WSOverrideStack BasicPushPop test. Precondition KeyA=true,
// effect Goal=true, cost 1.0. With base WS {KeyA=true, KeyB=false}, OpA is
// the only viable plan step satisfying the goal.
//============================================================================

class UCk_AutoTestAction_Goap_WSOverrideStack_OpA : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.WSOverrideStack.KeyA"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.WSOverrideStack.Goal"), true);
        SetCost(1.0);
    }
}
