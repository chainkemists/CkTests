// Language=angelscript

//============================================================================
// CkGoapGym — Combat Brain station Actions  (4-tier canonical demo)
//
// Demonstrates spec §2.2's canonical 4-tier hierarchy with TWO mid-tier
// composites promoted to Planners under the same parent, exercising sibling
// branch selection by cost.
//
//   Alive_Planner            [Planner only]            goal: EnemyDead=true
//     Alive_Root              [Action; implicit root]   eff: EnemyDead    cost 0
//     Engage                  [Action + Planner]        pre: EnemyVisible
//                                                       eff: EnemyAttacked cost 1
//                                                       (sub-goal: EnemyHit=true)
//       LightAttacks          [Action + Planner]        pre: WeaponEquipped
//                                                       eff: EnemyHit      cost 1
//                                                       (sub-goal: EnemyHit=true)
//         Light1               [Action only]            eff: EnemyHit      cost 1
//         Light2               [Action only]            eff: EnemyHit      cost 2
//         Light3               [Action only]            eff: EnemyHit      cost 0.5
//       HeavyAttacks          [Action + Planner]        pre: StaminaHigh
//                                                       eff: EnemyHit      cost 1
//                                                       (sub-goal: EnemyHit=true)
//         Heavy1               [Action only]            eff: EnemyHit      cost 3
//         Heavy2               [Action only]            eff: EnemyHit      cost 5
//     Win                     [Action only]            pre: EnemyAttacked
//                                                       eff: EnemyDead     cost 1
//
// Initial WS:
//   EnemyVisible=false, WeaponEquipped=false, StaminaHigh=false,
//   EnemyHit=false, EnemyAttacked=false, EnemyDead=false.
//
// Player exploration:
//   - With all gates false, no plan exists (preconditions block Engage).
//   - SetEnemyVisible + SetWeaponEquipped → Alive plan = [Engage, Win],
//                                            Engage promoted plan = [LightAttacks],
//                                            LightAttacks promoted plan = [Light3]
//                                            (cost 0.5 < Light1 cost 1.0 < Light2).
//   - SetEnemyVisible + SetStaminaHigh (no weapon) → Engage promoted picks
//                                            HeavyAttacks (the only one whose
//                                            precondition is met), then Heavy1
//                                            (cost 3 < Heavy2 cost 5).
//   - Both gates on → light branch wins on cost.
//
// Buttons (Goap.CombatBrain.*):
//   SetEnemyVisible / ClearEnemyVisible
//   SetWeaponEquipped / ClearWeaponEquipped
//   SetStaminaHigh / ClearStaminaHigh
//   Reset    — all keys back to false
//   Complete — set every key true (drives the chain to terminal state)
//============================================================================

// ---- Tier 1: Alive root (implicit root of top-level Planner) ----

class UCk_GoapGym_CombatBrain_AliveRoot : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyDead"), true);
        SetCost(0.0);
    }
}

// ---- Tier 2: composites under Alive ----

// Engage: produces EnemyAttacked (consumed by Win). Gated by EnemyVisible so
// the user can flip a single WS key and watch the whole tree light up.
class UCk_GoapGym_CombatBrain_Engage : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyVisible"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyAttacked"), true);
        SetCost(1.0);
    }
}

// Win: atomic finisher under Alive. Precondition EnemyAttacked=true is
// produced by the Engage subtree, sequencing Alive's plan = [Engage, Win].
class UCk_GoapGym_CombatBrain_Win : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyAttacked"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyDead"), true);
        SetCost(1.0);
    }
}

// ---- Tier 3: composites under Engage's promoted Planner ----

// LightAttacks: produces EnemyAttacked (visible to Engage's planner) and
// promoted to a Planner with sub-goal EnemyHit=true. Gated by WeaponEquipped.
// Cost 1.0 — same as HeavyAttacks at this tier; cost difference plays out
// among the tier-4 leaves.
class UCk_GoapGym_CombatBrain_LightAttacks : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.WeaponEquipped"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyAttacked"), true);
        SetCost(1.0);
    }
}

// HeavyAttacks: sibling alternative under Engage. Gated by StaminaHigh.
// Same effect, same cost — Engage's regressive planner picks whichever's
// precondition is satisfiable.
class UCk_GoapGym_CombatBrain_HeavyAttacks : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.StaminaHigh"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyAttacked"), true);
        SetCost(1.0);
    }
}

// ---- Tier 4: atomic leaves under LightAttacks ----

class UCk_GoapGym_CombatBrain_Light1 : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyHit"), true);
        SetCost(1.0);
    }
}

class UCk_GoapGym_CombatBrain_Light2 : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyHit"), true);
        SetCost(2.0);
    }
}

// Light3: cheapest leaf — wins cost tie-break when WeaponEquipped is on.
class UCk_GoapGym_CombatBrain_Light3 : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyHit"), true);
        SetCost(0.5);
    }
}

// ---- Tier 4: atomic leaves under HeavyAttacks ----

class UCk_GoapGym_CombatBrain_Heavy1 : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyHit"), true);
        SetCost(3.0);
    }
}

class UCk_GoapGym_CombatBrain_Heavy2 : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.CombatBrain.EnemyHit"), true);
        SetCost(5.0);
    }
}
