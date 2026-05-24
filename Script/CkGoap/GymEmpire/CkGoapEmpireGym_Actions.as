// Language=angelscript

//============================================================================
// CkGoapEmpire_Gym — Empire-research Actions
//
// 5-step plan resolving Feudal-age research from raw gathering:
//   GatherFood     pre {}                              eff {Food.Have}      cost 3
//   GatherGold     pre {}                              eff {Gold.Have}      cost 4
//   GatherWood     pre {}                              eff {Wood.Have}      cost 2
//   BuildBarracks  pre {Food.Have, Gold.Have, Wood.Have}  eff {Barracks.Built} cost 5
//   ResearchFeudal pre {Barracks.Built, Food.Have}      eff {Feudal.Researched} cost 6
//
// Planner goal {FeudalResearched=true}. Initial WS has all booleans false.
// Plan = [GatherWood, GatherFood, GatherGold, BuildBarracks, ResearchFeudal]
// (gather order is by cost — wood cheapest, gold dearest).
//
// PR-B.1b Stage 5: the implicit-root model is gone — operators are direct
// children of the Planner. ResearchFeudal is the only candidate whose effect
// satisfies the goal, so the backchain naturally orders the dependency chain.
//============================================================================

class UCk_GoapGym_Empire_GatherFood : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.HasFood"), true);
        SetCost(3.0);
    }
}

class UCk_GoapGym_Empire_GatherGold : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.HasGold"), true);
        SetCost(4.0);
    }
}

class UCk_GoapGym_Empire_GatherWood : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.HasWood"), true);
        SetCost(2.0);
    }
}

class UCk_GoapGym_Empire_BuildBarracks : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.HasFood"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.HasGold"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.HasWood"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.BarracksBuilt"), true);
        SetCost(5.0);
    }
}

class UCk_GoapGym_Empire_ResearchFeudal : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.BarracksBuilt"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.HasFood"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.FeudalResearched"), true);
        SetCost(6.0);
    }
}

// Always-valid-plan tenet fallback (CkGoap/CLAUDE.md § "Design tenets").
// ResearchFeudal carries hard preconditions on BarracksBuilt + HasFood — the
// real path goes through all five resource/build steps. Without this fallback
// the Planner has no unconditional path to FeudalResearched and the tenet
// check fires. Semantically: "wait for orders from the ruler; FeudalResearched
// satisfied via off-screen / external decree." Cost 999 ensures it only wins
// when no real research chain is viable.
class UCk_GoapGym_Empire_WaitForOrders : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Empire.FeudalResearched"), true);
        SetCost(999.0);
    }
}
