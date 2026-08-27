// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST ACTION: CycleA (DependencyCycleDetection test)
//============================================================================
//
// Sibling Action used by the DependencyCycleDetection test to construct a
// real precondition/effect cycle. Pairs with CycleB:
//
//   CycleA: precondition BKey=true,  effect AKey=true
//   CycleB: precondition AKey=true,  effect BKey=true
//
// Edge model: CycleB -> CycleA (CycleB's effect BKey satisfies CycleA's
// precondition BKey), CycleA -> CycleB (CycleA's effect AKey satisfies
// CycleB's precondition AKey). The two form an SCC of size 2, which is
// what the cycle-detection diagnostic must catch.
//============================================================================

class UCk_AutoTestAction_Goap_ActionSet_CycleA : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.BKey"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.ActionSet.WS.AKey"), true);
        SetCost(1.0);
    }
}
