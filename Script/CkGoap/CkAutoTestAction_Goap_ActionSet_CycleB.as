// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: CycleB (DependencyCycleDetection test)
//============================================================================
//
// Sibling Action used by the DependencyCycleDetection test to construct a
// real precondition/effect cycle. See CycleA's header for the cycle model.
//
//   CycleA: precondition BKey=true,  effect AKey=true
//   CycleB: precondition AKey=true,  effect BKey=true
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_CycleB : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.BKey"), true);
        SetCost(1.0);
    }
}
