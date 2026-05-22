// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: ENGAGE (DeepNesting test) — tier 2
//============================================================================
//
// Mid-tier composite under Alive. Promoted to Planner role in the test with
// goal EnemyAttacked=true. As an Action (visible to Alive's planner), its
// effect is EnemyAttacked=true — satisfying the precondition of Win and
// enabling Alive's plan = [Engage, Win]. As a Planner, it plans toward
// EnemyAttacked=true and is expected to pick LightAttacks (whose effect
// matches). Cost 1.0.
//============================================================================

class UCk_AutoTestAction_Goap_DeepNesting_Engage : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.DeepNesting.WS.EnemyAttacked"), true);
        SetCost(1.0);
    }
}
