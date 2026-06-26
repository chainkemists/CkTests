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
        auto _CkPerfScope = ck::ScopedStat();
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
        auto _CkPerfScope = ck::ScopedStat();
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
        auto _CkPerfScope = ck::ScopedStat();
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
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.ThreatActive"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.SafeFromThreat"), true);
        SetCost(3.0);
    }
}

// -------------------- Tenet fallbacks --------------------
//
// Both Survival Planners (Hunger and Defense) need an unconditional fallback
// Action per CkGoap/CLAUDE.md § "Design tenets / Every Planner must always
// produce a valid plan". EatFood requires HasFood, Forage doesn't directly
// satisfy Hungry=false. FightEnemy and RunAway both require ThreatActive.
// In other words: drop HasFood (or set ThreatActive=false), and without a
// fallback both Planners hit PlanFailed — the framework treats that as a
// catalog misconfiguration. The fallbacks below cover both goals at cost 999.

// HuddleInPlace: Hunger fallback — "curl up and ride out the hunger; goal
// satisfied by attrition / time-out". Effect = Hungry=false (matches Hunger
// Planner's goal exactly).
class UCk_GoapGym_Survival_HuddleInPlace : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.Hungry"), false);
        SetCost(999.0);
    }
}

// RemainAlert: Defense fallback — "stand still and stay vigilant; threat
// passes / safety achieved by survival in place". Effect = SafeFromThreat=true.
class UCk_GoapGym_Survival_RemainAlert : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.SafeFromThreat"), true);
        SetCost(999.0);
    }
}
