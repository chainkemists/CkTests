// Language=angelscript

//============================================================================
// CkGoapAutoReplan_Gym — shared Actions
//
// All three AutoReplan stations use the same minimal action set (Planner goal
// is Goal=true; FlipOp / AltOp are registered directly on the Planner):
//   FlipOp    eff {Goal=true}  cost 1
//   AltOp     eff {Goal=true}  cost 2 (used by OnCostDirty station)
//
// PR-B.1b Stage 5: the implicit-root model is gone — operators are direct
// children of the Planner.
//
// Always-valid-plan tenet (CkGoap/CLAUDE.md § "Design tenets"):
//   FlipOp has no preconditions and its effect matches the Planner's goal
//   exactly — it IS the unconditional fallback. The tenet check passes
//   without any extra Action. (AltOp likewise qualifies.) The stations
//   don't need a dedicated cost-999 fallback because the real operator is
//   already unconditional.
//============================================================================

class UCk_GoapGym_AutoReplan_FlipOp : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.AutoReplan.Goal"), true);
        SetCost(1.0);
    }
}

class UCk_GoapGym_AutoReplan_AltOp : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.AutoReplan.Goal"), true);
        SetCost(2.0);
    }
}
