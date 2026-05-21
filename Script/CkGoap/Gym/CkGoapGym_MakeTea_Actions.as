// Language=angelscript

//============================================================================
// CkGoapGym — Make Tea station Actions
//
// Four-step linear dependency chain:
//   BoilWater  pre {HasKettle, HasWater}        eff {WaterBoiled}
//   SteepLeaf  pre {WaterBoiled, HasTeaLeaves}  eff {TeaSteeped}
//   PourCup    pre {TeaSteeped, HasCup}         eff {TeaPoured}
//   Serve      pre {TeaPoured}                  eff {TeaServed}
//
// Root's goal is TeaServed=true. Planner backchains through each step,
// producing a 4-step ordered plan when the player has all the ingredients.
// Drop a precondition (e.g. HasWater=false) and the plan fails to resolve.
//============================================================================

class UCk_GoapGym_MakeTea_Root : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        // Marker effect so the planner registers the goal key in the WS.
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.TeaServed"), true);
        SetCost(0.0);
    }
}

class UCk_GoapGym_MakeTea_BoilWater : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.HasKettle"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.HasWater"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.WaterBoiled"), true);
        SetCost(2.0);
    }
}

class UCk_GoapGym_MakeTea_SteepLeaves : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.WaterBoiled"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.HasTeaLeaves"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.TeaSteeped"), true);
        SetCost(1.0);
    }
}

class UCk_GoapGym_MakeTea_PourCup : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.TeaSteeped"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.HasCup"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.TeaPoured"), true);
        SetCost(1.0);
    }
}

class UCk_GoapGym_MakeTea_Serve : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.TeaPoured"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.TeaServed"), true);
        SetCost(1.0);
    }
}
