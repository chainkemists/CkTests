// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: LIGHT1 (DeepNesting test) — tier 4 atomic
//============================================================================
//
// Atomic leaf under LightAttacks' promoted planner. Effect: EnemyHit=true.
// Cost 1.0 — cheaper than Light2 (cost 2.0). LightAttacks' regressive
// planner picks this leaf when both are present.
//============================================================================

class UCk_AutoTestAction_Goap_DeepNesting_Light1 : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.DeepNesting.WS.EnemyHit"), true);
        SetCost(1.0);
    }
}
