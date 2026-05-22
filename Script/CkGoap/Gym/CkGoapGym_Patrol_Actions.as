// Language=angelscript

//============================================================================
// CkGoapGym — Patrol Route station Actions  (U11.6 multi-tier rewrite)
//
// Demonstrates spec §2.2's multi-tier Planner hierarchy.  Each node below
// that has children is BOTH an Action (visible to its parent's planner) AND
// a Planner (runs its own A* over its children with an independent goal).
//
// Tree shape:
//
//   Patrol_Planner          [Planner only]     goal: AreaPatrolled=true
//     Root                  [Action+Planner?]  eff: AreaPatrolled=true   cost 0
//       GoToWaypoint        [Action+Planner]   eff: AtWaypoint=true      cost 1
//         ├── Run           [Action only]      eff: AtWaypoint=true      cost 1
//         └── Walk          [Action only]      eff: AtWaypoint=true      cost 2
//       Observe             [Action+Planner]   pre: AtWaypoint=true
//                                              eff: AreaScanned=true     cost 1
//         ├── LookAround    [Action only]      eff: AreaScanned=true     cost 1
//         └── WaitAtPost    [Action only]      eff: AreaScanned=true     cost 3
//       MarkDone            [Action only]      pre: AtWaypoint=true
//                                                   AreaScanned=true
//                                              eff: AreaPatrolled=true   cost 1
//
// Initial WS: AtWaypoint=false, AreaScanned=false, AreaPatrolled=false.
//
// Expected runtime flow:
//   1. Root plans  → backchain finds GoToWaypoint → Observe → MarkDone.
//                    Chain = [Root, GoToWaypoint].
//   2. GoToWaypoint (promoted Planner) plans with goal AtWaypoint=true.
//                    Picks Run (cost 1 < Walk's cost 2).
//                    Chain = [Root, GoToWaypoint, Run].
//   3. Player sets AtWaypoint=true (Goap.Patrol.SetAtWaypoint).
//                    GoToWaypoint's goal satisfied → Root replans.
//   4. Root replans → picks Observe next (AreaScanned still false).
//                    Chain = [Root, Observe].
//   5. Observe (promoted Planner) plans with goal AreaScanned=true.
//                    Picks LookAround (cost 1).
//                    Chain = [Root, Observe, LookAround].
//   6. Player sets AreaScanned=true (Goap.Patrol.SetAreaScanned).
//                    Observe satisfied → Root replans.
//   7. Root picks MarkDone (atomic leaf, no sub-plan).
//                    Chain = [Root, MarkDone].
//   8. Player sets AreaPatrolled=true (Goap.Patrol.Complete) or let
//                    MarkDone's eff fire automatically if the runtime
//                    applies effects (gym-only: player sets manually).
//
// Buttons:
//   Goap.Patrol.SetAtWaypoint   — AtWaypoint=true
//   Goap.Patrol.SetAreaScanned  — AreaScanned=true
//   Goap.Patrol.Complete        — AreaPatrolled=true
//   Goap.Patrol.Reset           — all keys back to false
//============================================================================

// ---- Tier 1 root ----

// Root action: the single child of the top-level Planner. Its effects match
// the Planner's goal so the Planner can select it.  Zero cost — the root is
// the mandatory entry point; cost is borne by the sub-plan.
class UCk_GoapGym_Patrol_Root : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaPatrolled"), true);
        SetCost(0.0);
    }
}

// ---- Tier 2 composites (each promoted to Planner in the station) ----

// GoToWaypoint: action effect = AtWaypoint=true. No preconditions — always
// available as a candidate. The Observe composite requires AtWaypoint as a
// precondition, so the backchain naturally selects GoToWaypoint first.
class UCk_GoapGym_Patrol_GoToWaypoint : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtWaypoint"), true);
        SetCost(1.0);
    }
}

// Observe: action effect = AreaScanned=true. Precondition AtWaypoint=true
// forces GoToWaypoint to execute before Observe in the plan.
class UCk_GoapGym_Patrol_Observe : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtWaypoint"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaScanned"), true);
        SetCost(1.0);
    }
}

// ---- Tier 2 atomic leaf ----

// MarkDone: terminal step. Requires both AtWaypoint and AreaScanned; produces
// AreaPatrolled=true which satisfies the top-level goal.
class UCk_GoapGym_Patrol_MarkDone : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtWaypoint"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaScanned"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaPatrolled"), true);
        SetCost(1.0);
    }
}

// ---- Tier 3: children of GoToWaypoint ----

// Run: cheaper option to reach the waypoint.
class UCk_GoapGym_Patrol_Run : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtWaypoint"), true);
        SetCost(1.0);
    }
}

// Walk: more expensive alternative.
class UCk_GoapGym_Patrol_Walk : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtWaypoint"), true);
        SetCost(2.0);
    }
}

// ---- Tier 3: children of Observe ----

// LookAround: cheaper scan option.
class UCk_GoapGym_Patrol_LookAround : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaScanned"), true);
        SetCost(1.0);
    }
}

// WaitAtPost: slower but always available.
class UCk_GoapGym_Patrol_WaitAtPost : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaScanned"), true);
        SetCost(3.0);
    }
}
