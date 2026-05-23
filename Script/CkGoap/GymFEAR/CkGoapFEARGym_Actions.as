// Language=angelscript

//============================================================================
// CkGoapFEAR_Gym — F.E.A.R. combat-AI Actions
//
// Adapted from Jeff Orkin's F.E.A.R. AI paper. One top-level Planner
// (FEAR_Combatant) with a sub-Planner promoted at AttackEnemy.
//
//   FEAR_Combatant            [Planner]   goal: EnemyNeutralized=true
//     Combatant_Root           [Action]   eff: EnemyNeutralized   cost 0
//     AttackEnemy              [Action + Planner]                 cost 1
//                              pre: HasAmmo, EnemyVisible
//                              eff: EnemyNeutralized
//                              (sub-goal: EnemyNeutralized=true)
//       AttackFromCover        [Action]   pre: AtCover, HasAmmo, EnemyVisible
//                                          eff: EnemyNeutralized   cost 1.0
//       AttackFromFlank        [Action]   pre: BehindEnemy, HasAmmo, EnemyVisible
//                                          eff: EnemyNeutralized   cost 0.5
//       AttackOpen             [Action]   pre: HasAmmo, EnemyVisible
//                                          eff: EnemyNeutralized   cost 2.0
//     Flank                    [Action]   pre: EnemyVisible
//                                          eff: BehindEnemy        cost 2.0
//     TakeCover                [Action]   pre: (none)
//                                          eff: AtCover            cost 1.0
//     Reload                   [Action]   pre: HasAmmoReserve
//                                          eff: HasAmmo            cost 0.5
//     Investigate              [Action]   pre: HeardSound
//                                          eff: EnemyVisible       cost 1.5
//     Patrol                   [Action]   pre: (none)
//                                          eff: Patrolling         cost 3.0
//
// Scenarios (see CkGoapFEARGym_Station.as header for the full table):
//   Default reset           → PLAN FAILED (no EnemyVisible)
//   EnemyVisible            → [AttackEnemy -> AttackOpen]    cost 2.0
//   EnemyVisible + AtCover  → [AttackEnemy -> AttackFromCover] cost 1.0
//   EnemyVisible + BehindEnemy → [AttackEnemy -> AttackFromFlank] cost 0.5  ← iconic
//   HeardSound (no Visible) → [Investigate -> AttackEnemy -> AttackOpen]
//   HasAmmo=false + Reserve → [Reload -> AttackEnemy -> AttackOpen]
//============================================================================

// ---- Tier-1 implicit root of FEAR_Combatant ----

class UCk_GoapFEARGym_Combatant_Root : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized"), true);
        SetCost(0.0);
    }
}

// ---- Tier-1 children under FEAR_Combatant ----

// AttackEnemy: promoted to sub-Planner. Same effect as the sub-Planner's
// leaves so it can be selected by the top planner; the sub-Planner expands
// it into one of three concrete attacks.
class UCk_GoapFEARGym_AttackEnemy : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.HasAmmo"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyVisible"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized"), true);
        SetCost(1.0);
    }
}

// Flank: rotate around the target so a later AttackFromFlank becomes viable.
class UCk_GoapFEARGym_Flank : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyVisible"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.BehindEnemy"), true);
        SetCost(2.0);
    }
}

// TakeCover: unconditional cover-seek. Enables AttackFromCover.
class UCk_GoapFEARGym_TakeCover : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.AtCover"), true);
        SetCost(1.0);
    }
}

// Reload: cheap; pre-reqs reserve ammo.
class UCk_GoapFEARGym_Reload : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.HasAmmoReserve"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.HasAmmo"), true);
        SetCost(0.5);
    }
}

// Investigate: converts a heard sound into visual contact. Lets a plan
// chain through Investigate -> AttackEnemy -> AttackOpen.
class UCk_GoapFEARGym_Investigate : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.HeardSound"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyVisible"), true);
        SetCost(1.5);
    }
}

// Patrol: fallback "no combat possible" routine. Doesn't satisfy the goal,
// so it's never picked when combat is viable.
class UCk_GoapFEARGym_Patrol : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.Patrolling"), true);
        SetCost(3.0);
    }
}

// ---- Tier-2 children under AttackEnemy (promoted to Planner) ----

// AttackFromCover: ideal cover engagement. Cheaper than open (1.0).
class UCk_GoapFEARGym_AttackFromCover : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.AtCover"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.HasAmmo"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyVisible"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized"), true);
        SetCost(1.0);
    }
}

// AttackFromFlank: the iconic F.E.A.R. moment — ambush from behind, cheapest
// option (0.5). Requires the agent to be BehindEnemy already.
class UCk_GoapFEARGym_AttackFromFlank : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.BehindEnemy"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.HasAmmo"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyVisible"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized"), true);
        SetCost(0.5);
    }
}

// AttackOpen: last-resort frontal assault. Most expensive (2.0). Always
// usable as long as HasAmmo + EnemyVisible; the planner picks it when no
// cover / flanking advantage exists.
class UCk_GoapFEARGym_AttackOpen : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.HasAmmo"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyVisible"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized"), true);
        SetCost(2.0);
    }
}
