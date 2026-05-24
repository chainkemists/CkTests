// Language=angelscript

//============================================================================
// CkGoapGym — Survival Decision station Actions
//
// Two independent Planners on the SAME entity, demonstrating Planner
// isolation. Each Planner plans independently against the shared WS.
//
// Planner "Hunger" (goal {Hungry=false}):
//   ├── EatFood  pre {HasFood}  eff {Hungry=false}  cost 1
//   └── Forage   pre {}         eff {HasFood=true}  cost 4
//   When HasFood=false, Hunger has NO valid single-step plan (Forage doesn't
//   directly resolve Hungry=false). With HasFood=true, EatFood is selected.
//
// Planner "Defense" (goal {SafeFromThreat=true}):
//   ├── FightEnemy  pre {ThreatActive, HasWeapon}  eff {SafeFromThreat=true}  cost 1
//   └── RunAway    pre {ThreatActive}              eff {SafeFromThreat=true}  cost 3
//   When ThreatActive=true and HasWeapon=true, FightEnemy wins (cheaper).
//   Drop HasWeapon → planner falls back to RunAway.
//
// Both Planners are top-level on the same entity — proving
// utils_goap_planner::Add supports multiple decision domains.
//
// PR-B.1b Stage 5: the implicit-root model is gone — operators are direct
// children of each Planner.
//============================================================================

// -------------------- Hunger Planner --------------------

class UCk_GoapGym_Survival_EatFood : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.HasFood"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.Hungry"), false);
        SetCost(1.0);
    }
}

class UCk_GoapGym_Survival_Forage : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.HasFood"), true);
        SetCost(4.0);
    }
}

// -------------------- Defense Planner --------------------

class UCk_GoapGym_Survival_FightEnemy : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.ThreatActive"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.HasWeapon"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.SafeFromThreat"), true);
        SetCost(1.0);
    }
}

class UCk_GoapGym_Survival_RunAway : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.ThreatActive"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.SafeFromThreat"), true);
        SetCost(3.0);
    }
}
