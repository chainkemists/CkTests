// Language=angelscript

//============================================================================
// CkGoapGym — Open Door station Actions
//
// Atomic single-step plan. Planner's goal is Door.IsOpen=true. The single
// operator (OpenDoor) is registered directly on the Planner; its effect
// satisfies the goal so the plan resolves to [OpenDoor].
//
// PR-B.1b Stage 5: the implicit-root model is gone — there is no separate
// Root Action; OpenDoor is the only candidate.
//
// Always-valid-plan tenet (CkGoap/CLAUDE.md § "Design tenets"):
//   OpenDoor carries a precondition (IsOpen=false), so it does NOT count as
//   an unconditional fallback. WaitAtDoor below is the fallback: no
//   preconditions, effect = goal, cost 999. It only wins when OpenDoor is
//   somehow not viable; for this gym OpenDoor is always viable while the
//   door is closed, so WaitAtDoor will essentially never appear in the plan
//   — but it satisfies the framework's tenet check and guarantees the
//   planner never returns PlanFailed.
//============================================================================

class UCk_GoapGym_OpenDoor_Operator : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddPrecondition(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Door.IsOpen"), false);
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Door.IsOpen"), true);
        SetCost(1.0);
    }
}

// Always-valid-plan tenet fallback (CkGoap/CLAUDE.md § "Design tenets").
// No preconditions, effect = goal (Door.IsOpen=true), very high cost so the
// real OpenDoor operator wins whenever it's viable. Semantically: "wait at
// the door for someone else to open it from the other side" — the goal is
// satisfied by attrition when a co-op partner / scripted event opens the door.
class UCk_GoapGym_OpenDoor_WaitAtDoor : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Door.IsOpen"), true);
        SetCost(999.0);
    }
}
