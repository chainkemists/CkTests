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
//============================================================================

class UCk_GoapGym_CrossRiver_Root : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CrossRiver.Crossed"), true);
        SetCost(0.0);
    }
}

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
