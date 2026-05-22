// Language=angelscript

//============================================================================
// CkGoapGym — Patrol Route station Actions
//
// Showcases composite Actions and active-chain extension.
//
// Tree:
//   Root  goal = {PatrolComplete=true}
//     └── DoPatrol  (composite — effect PatrolComplete=true)
//           ├── WalkToB    pre {AtPostA}  eff {AtPostB}     cost 1
//           ├── WalkToC    pre {AtPostB}  eff {AtPostC}     cost 1
//           └── MarkComplete pre {AtPostC} eff {PatrolComplete} cost 1
//
// Behaviour:
//   - Root plans → picks DoPatrol (the only operator that satisfies its goal).
//   - ChainUpdate appends DoPatrol → active chain = [Root, DoPatrol].
//     OnPlannerActivated fires on DoPatrol.
//   - DoPatrol activates, its planner runs against its own goal (derived from
//     its own _GoalFromEffects = PatrolComplete=true), backchains:
//       MarkComplete <- WalkToC <- WalkToB
//     producing plan = [WalkToB, WalkToC, MarkComplete] in WS-state with
//     AtPostA=true initially.
//   - All three children are atomic so the chain stays at [Root, DoPatrol]
//     while the gameplay layer (or the user, via the AdvanceWS button) walks
//     through the sub-plan.
//============================================================================

class UCk_GoapGym_Patrol_Root : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.Complete"), true);
        SetCost(0.0);
    }
}

class UCk_GoapGym_Patrol_DoPatrol : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        // DoPatrol is a composite Action — its own effects become its
        // _GoalFromEffects when ChainUpdate activates it.
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.Complete"), true);
        SetCost(1.0);
    }
}

class UCk_GoapGym_Patrol_WalkToB : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtPostA"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtPostB"), true);
        SetCost(1.0);
    }
}

class UCk_GoapGym_Patrol_WalkToC : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtPostB"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtPostC"), true);
        SetCost(1.0);
    }
}

class UCk_GoapGym_Patrol_MarkComplete : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.AtPostC"), true);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Patrol.Complete"), true);
        SetCost(1.0);
    }
}
