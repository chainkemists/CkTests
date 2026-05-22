// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET OWNER CASCADE DESTROY
//============================================================================
//
// Validates spec §9 row 12: "Destroying owner cleans up GoapRoot →
// ActionSets → Actions without leaks."
//
// Strategy:
//   - The test entity itself stays alive throughout.
//   - A sub-entity (SubOwner) is spawned as a child of the test entity.
//   - Goap is added to SubOwner. An ActionSet and a root Action are added.
//   - Handles for Goap, ActionSet, and the root Action are captured.
//   - Request_DestroyEntity(SubOwner).
//   - WaitOneFrame to let the destruction settle.
//   - Assert: SubOwner handle invalid, Goap handle invalid, ActionSet handle
//     invalid, root Action handle invalid (cascade destroyed with owner).
//
// No new action classes needed — the Simple action (Ready WS) is reused
// to keep the setup minimal. The goal of this test is handle invalidation
// correctness after destroy, not plan execution.
//============================================================================

class UCk_AutoTest_Goap_Planner_OwnerCascadeDestroy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _SubOwner;
    private FCk_Handle_Goap_Planner _GoapHandle;
    private FCk_Handle_Goap_Planner _ActionSet;
    private FCk_Handle_Goap_Action _RootAction;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // Spawn a child entity that will host the Goap. Destroying it must
        // cascade-destroy all Goap children.
        _SubOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Assert_True(utils_handle::Get_IsValid(_SubOwner),
            "SubOwner should be a valid handle after Request_CreateEntity");

        // Add Transform (required by Goap setup).
        utils_transform::Add(_SubOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // WorldState — hosted on SubOwner so it is cascade-destroyed too.
        auto WS = utils_goap_world_state::Create(_SubOwner,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            true);

        // Add Planner to SubOwner (post-U11.0a: no separate Goap-root container).
        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _ActionSet = utils_goap_planner::Add(_SubOwner, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "Add should return a valid handle");
        _GoapHandle = _ActionSet;  // U11.0a: Planner is the only Goap entity.

        // Add root Action (Simple: effect Ready=true; goal already satisfied).
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Simple);
        _RootAction = utils_goap_planner::SetRootAction(_ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // All handles are valid before destroy.
        Assert_True(utils_handle::Get_IsValid(_SubOwner),
            "Pre-destroy: SubOwner should be valid");
        Assert_True(ck::IsValid(_GoapHandle),
            "Pre-destroy: Goap handle should be valid");
        Assert_True(ck::IsValid(_ActionSet),
            "Pre-destroy: ActionSet handle should be valid");
        Assert_True(ck::IsValid(_RootAction),
            "Pre-destroy: RootAction handle should be valid");

        // Destroy SubOwner. The ECS ownership chain guarantees cascade:
        // SubOwner → Goap entity → ActionSet entity → Action entities.
        utils_entity_lifetime::Request_DestroyEntity(_SubOwner);

        // Wait one frame for the destruction to settle.
        WaitOneFrame(n"OnCheckDestroyed");
    }

    UFUNCTION()
    private void OnCheckDestroyed(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_handle::Get_IsValid(_SubOwner),
            "SubOwner should be invalid after Request_DestroyEntity");

        Assert_True(!ck::IsValid(_GoapHandle),
            "Goap handle should be invalid after owner destroy (cascade)");

        Assert_True(!ck::IsValid(_ActionSet),
            "ActionSet handle should be invalid after owner destroy (cascade)");

        Assert_True(!ck::IsValid(_RootAction),
            "RootAction handle should be invalid after owner destroy (cascade)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_OwnerCascadeDestroy_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_OwnerCascadeDestroy;
    default _TimeoutSeconds = 5.0f;
}
