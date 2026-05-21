// Language=angelscript

//============================================================================
// CkGoapGym — Open Door station Actions
//
// Atomic single-step plan. Root's goal is Door.IsOpen=true. Single operator
// (OpenDoor) satisfies it directly. Plan = [OpenDoor]. Active chain stays at
// [Root] because OpenDoor is atomic (no children).
//============================================================================

class UCk_GoapGym_OpenDoor_Root : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        // Root's CDO effect isn't used for its own planning (goal is supplied
        // via _InitialGoal_RootOnly in params) — declare a matching marker so
        // the WS key is registered and the panel can read it back cleanly.
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(
            n"Gym.Goap.WS.Door.IsOpen"), true);
        SetCost(0.0);
    }
}

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
