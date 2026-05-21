// Language=angelscript

//============================================================================
// CkGoapAutoReplan_Gym — shared Actions
//
// All three AutoReplan stations use the same minimal action set:
//   Root      goal {Goal=true} (root effect Goal=true)
//   FlipOp    eff {Goal=true}  cost 1
//   AltOp     eff {Goal=true}  cost 2 (used by OnCostDirty station)
//============================================================================

class UCk_GoapGym_AutoReplan_Root : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.AutoReplan.Goal"), true);
        SetCost(0.0);
    }
}

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
