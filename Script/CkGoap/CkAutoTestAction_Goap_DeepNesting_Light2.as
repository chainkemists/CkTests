// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST ACTION: LIGHT2 (DeepNesting test) — tier 4 atomic
//============================================================================
//
// Atomic distractor leaf under LightAttacks' promoted planner. Effect:
// EnemyHit=true. Cost 2.0 — the more-expensive sibling of Light1 (cost 1.0).
// LightAttacks' planner must NOT pick this leaf — picking it would expose
// a regression in regressive A* tie-breaking-by-cost.
//============================================================================

class UCk_AutoTestAction_Goap_DeepNesting_Light2 : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.DeepNesting.WS.EnemyHit"), true);
        SetCost(2.0);
    }
}
