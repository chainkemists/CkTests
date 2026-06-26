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
// Planner goal is TeaServed=true. Planner backchains through each step,
// producing a 4-step ordered plan when the player has all the ingredients.
// Drop a precondition (e.g. HasWater=false) and the plan fails to resolve.
//
// PR-B.1b Stage 5: the implicit-root model is gone. The four operators are
// registered directly on the Planner; Serve is the only one whose effect
// satisfies TeaServed, so the backchain naturally orders the dependency chain.
//============================================================================

class UCk_GoapGym_MakeTea_BoilWater : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
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
        auto _CkPerfScope = ck::ScopedStat();
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
        auto _CkPerfScope = ck::ScopedStat();
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
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.TeaPoured"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Tea.TeaServed"), true);
        SetCost(1.0);
    }
}
