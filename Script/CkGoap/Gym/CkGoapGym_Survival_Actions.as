// Language=angelscript

//============================================================================
// CkGoapGym — Survival Decision station Actions
//
// Two independent ActionSets on the SAME entity, demonstrating ActionSet
// isolation. Each ActionSet plans independently against the shared WS.
//
// ActionSet "Hunger":
//   Root goal {Hungry=false}
//     ├── EatFood  pre {HasFood}  eff {Hungry=false}  cost 1
//     └── Forage   pre {}         eff {HasFood=true}  cost 4
//   When HasFood=false, Hunger has NO valid single-step plan (Forage doesn't
//   directly resolve Hungry=false). With HasFood=true, EatFood is selected.
//
// ActionSet "Defense":
//   Root goal {SafeFromThreat=true}
//     ├── FightEnemy  pre {ThreatActive, HasWeapon}  eff {SafeFromThreat=true}  cost 1
//     └── RunAway    pre {ThreatActive}              eff {SafeFromThreat=true}  cost 3
//   When ThreatActive=true and HasWeapon=true, FightEnemy wins (cheaper).
//   Drop HasWeapon → planner falls back to RunAway.
//
// Both ActionSets are top-level in the same Goap root — proving
// utils_goap_action_set::AddActionSet supports multiple decision domains.
//============================================================================

// -------------------- Hunger ActionSet --------------------

class UCk_GoapGym_Survival_HungerRoot : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        // Marker effect — the Hungry=false goal is supplied via params.
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.Hungry"), false);
        SetCost(0.0);
    }
}

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

// -------------------- Defense ActionSet --------------------

class UCk_GoapGym_Survival_DefenseRoot : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Survival.SafeFromThreat"), true);
        SetCost(0.0);
    }
}

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
