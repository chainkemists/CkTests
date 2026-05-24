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
