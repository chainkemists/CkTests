// Language=angelscript

//============================================================================
// CkGoapGym - Patrol Route station Actions  (U11.6 multi-tier rewrite)
//
// Demonstrates spec Sec.2.2's multi-tier Planner hierarchy.  Each node below
// that has children is BOTH an Action (visible to its parent's planner) AND
// a Planner (runs its own A* over its children with an independent goal).
//
// Tree shape:
//
//   Patrol_Planner          [Planner only]     goal: AreaPatrolled=true
//     GoToWaypoint          [Action+Planner]   eff: AtWaypoint=true      cost 1
//       +-- Run             [Action only]      eff: AtWaypoint=true      cost 1
//       +-- Walk            [Action only]      eff: AtWaypoint=true      cost 2
//     Observe               [Action+Planner]   pre: AtWaypoint=true
//                                              eff: AreaScanned=true     cost 1
//       +-- LookAround      [Action only]      eff: AreaScanned=true     cost 1
//       +-- WaitAtPost      [Action only]      eff: AreaScanned=true     cost 3
//     MarkDone              [Action only]      pre: AtWaypoint=true
//                                                   AreaScanned=true
//                                              eff: AreaPatrolled=true   cost 1
//
// Initial WS: AtWaypoint=false, AreaScanned=false, AreaPatrolled=false.
//
// PR-B.1b Stage 5 update: the implicit-root model is gone. GoToWaypoint,
// Observe, and MarkDone are direct children of the Planner; the backchain
// orders them as [GoToWaypoint, Observe, MarkDone] because MarkDone is the
// only candidate whose effect satisfies AreaPatrolled.
//
// Expected runtime flow:
//   1. Planner plans -> [GoToWaypoint, Observe, MarkDone].
//                      Chain = [GoToWaypoint].
//   2. GoToWaypoint (promoted Planner) plans with goal AtWaypoint=true.
//                      Picks Run (cost 1 < Walk's cost 2).
//                      Chain = [GoToWaypoint, Run].
//   3. Player sets AtWaypoint=true (Goap.Patrol.SetAtWaypoint).
//                      GoToWaypoint's goal satisfied -> top Planner replans.
//   4. Plan now starts at Observe -> [Observe, MarkDone].
//                      Chain = [Observe].
//   5. Observe (promoted Planner) plans with goal AreaScanned=true.
//                      Picks LookAround (cost 1).
//                      Chain = [Observe, LookAround].
//   6. Player sets AreaScanned=true (Goap.Patrol.SetAreaScanned).
//                      Observe satisfied -> top Planner replans.
//   7. Plan picks MarkDone (atomic leaf, no sub-plan).
//                      Chain = [MarkDone].
//   8. Player sets AreaPatrolled=true (Goap.Patrol.Complete) or let
//                    MarkDone's eff fire automatically if the runtime
//                    applies effects (gym-only: player sets manually).
//
// Buttons:
//   Goap.Patrol.SetAtWaypoint   - AtWaypoint=true
//   Goap.Patrol.SetAreaScanned  - AreaScanned=true
//   Goap.Patrol.Complete        - AreaPatrolled=true
//   Goap.Patrol.Reset           - all keys back to false
//============================================================================

// ---- Tier 1 composites (each promoted to Planner in the station) ----

// GoToWaypoint: action effect = AtWaypoint=true. No preconditions - always
// available as a candidate. The Observe composite requires AtWaypoint as a
// precondition, so the backchain naturally selects GoToWaypoint first.
class UCk_GoapGym_Patrol_GoToWaypoint : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
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
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtWaypoint"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaScanned"), true);
        SetCost(1.0);
    }
}

// ---- Tier 1 atomic leaf ----

// MarkDone: terminal step. Requires both AtWaypoint and AreaScanned; produces
// AreaPatrolled=true which satisfies the top-level goal.
class UCk_GoapGym_Patrol_MarkDone : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtWaypoint"), true);
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaScanned"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaPatrolled"), true);
        SetCost(1.0);
    }
}

// ---- Tier 2: children of GoToWaypoint ----

// Run: cheaper option to reach the waypoint.
class UCk_GoapGym_Patrol_Run : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
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
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtWaypoint"), true);
        SetCost(2.0);
    }
}

// ---- Tier 2: children of Observe ----

// LookAround: cheaper scan option.
class UCk_GoapGym_Patrol_LookAround : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
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
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaScanned"), true);
        SetCost(3.0);
    }
}

// ---- Top-level fallback ----

// StandWatch: always-valid-plan tenet fallback for the TOP Patrol Planner
// (the CkGoap docs Sec. "Design tenets"). No preconditions, effect = goal
// (AreaPatrolled=true), very high cost. Semantically: "hold position;
// AreaPatrolled satisfied by attrition / time-out". MarkDone (the real
// completion path) carries hard preconditions (AtWaypoint + AreaScanned),
// so without this fallback the top Planner has no unconditional path to
// goal and the framework's tenet check (CK_ENSURE_IF_NOT) fires.
//
// Note: the GoToWaypoint and Observe sub-Planners already comply with the
// tenet via their Run/Walk and LookAround/WaitAtPost leaves respectively
// (no preconditions; effects = sub-Planner goal). Only the top Planner
// needed a new fallback.
class UCk_GoapGym_Patrol_StandWatch : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AreaPatrolled"), true);
        SetCost(999.0);
    }
}
