// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: ROOT (WSInheritance test)
//============================================================================
//
// Root action for the WSInheritance and WSOverride tests.
//
// CDO effects: AKey=true — Root's _InitialGoal_RootOnly is set to {AKey=true}
// so the planner searches for a child that achieves AKey=true. Mid satisfies
// this with its own AKey=true effect.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_Root_WSInheritance : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        SetCost(1.0);
    }
}
