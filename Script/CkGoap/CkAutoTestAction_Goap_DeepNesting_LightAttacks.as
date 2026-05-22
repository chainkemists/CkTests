// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: LIGHT ATTACKS (DeepNesting test) — tier 3
//============================================================================
//
// Mid-tier composite under Engage's promoted planner. As an Action (visible
// to Engage's planner), its effect is EnemyAttacked=true — satisfying
// Engage's goal so Engage's plan = [LightAttacks]. As a Planner (promoted in
// the test), it plans toward EnemyHit=true and is expected to pick the
// cheaper of Light1 (cost 1.0) / Light2 (cost 2.0). Cost 1.0.
//============================================================================

class UCk_AutoTestAction_Goap_DeepNesting_LightAttacks : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.DeepNesting.WS.EnemyAttacked"), true);
        SetCost(1.0);
    }
}
