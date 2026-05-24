// Language=angelscript

//============================================================================
// CkGoapGym — Cross River station Actions
//
// Branching with cost sensitivity. Root goal is Crossed=true. Three operators
// satisfy it with different preconditions + costs:
//
//   UseBridge   pre {BridgeIsOpen}   eff {Crossed}   cost 2  (preferred)
//   UseFerry    pre {HasCoin}        eff {Crossed}   cost 4
//   SwimAcross  pre {}               eff {Crossed}   cost 8  (last resort)
//
// Toggling BridgeIsOpen / HasCoin in WS forces the planner to swap branches
// — demonstrating cost-sensitive plan selection + OnWorldStateDirty replan.
//
// Always-valid-plan tenet (CkGoap/CLAUDE.md § "Design tenets"):
//   SwimAcross has no preconditions and its effect is the Planner's goal —
//   that makes it the unconditional fallback for this Planner. Even with
//   both BridgeIsOpen and HasCoin false, the planner still produces
//   [SwimAcross] (cost 8) instead of PlanFailed. The cost is intentionally
//   lower than the conventional 999.0 fallback cost because cost sensitivity
//   between SwimAcross and the gated branches IS the teaching point of this
//   gym — but 8.0 still loses to UseBridge (2) and UseFerry (4) whenever
//   their preconditions hold, so the cheap-when-viable / fallback-when-not
//   semantics still hold.
//
// PR-B.1b Stage 5: the implicit-root model is gone. The three operators are
// registered directly on the Planner; the Planner's regressive search picks
// the cheapest whose preconditions are satisfied.
//============================================================================

class UCk_GoapGym_CrossRiver_UseBridge : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CrossRiver.BridgeIsOpen"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CrossRiver.Crossed"), true);
        SetCost(2.0);
    }
}

class UCk_GoapGym_CrossRiver_UseFerry : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CrossRiver.HasCoin"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CrossRiver.Crossed"), true);
        SetCost(4.0);
    }
}

class UCk_GoapGym_CrossRiver_SwimAcross : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CrossRiver.Crossed"), true);
        SetCost(8.0);
    }
}
