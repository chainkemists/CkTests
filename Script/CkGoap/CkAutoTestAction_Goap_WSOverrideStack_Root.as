// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: WSOverrideStack Root host
//============================================================================
//
// Implicit-root host for the WSOverrideStack tests. The planner's goal is
// {Goal=true}; OpA / OpB are the two candidate operators registered as
// children of this root. The root itself is never picked by the planner —
// only its children are. Effect declared so the action can be a valid root
// (CDO must have something to define).
//============================================================================

class UCk_AutoTestAction_Goap_WSOverrideStack_Root : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.WSOverrideStack.RootStub"), true);
        SetCost(1.0);
    }
}
