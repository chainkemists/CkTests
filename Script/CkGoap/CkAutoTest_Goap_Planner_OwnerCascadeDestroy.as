// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: PLANNER OWNER CASCADE DESTROY
//============================================================================
//
// Validates spec Sec.9 row 12: "Destroying owner cleans up GoapRoot ->
// Planners -> Actions without leaks."
//
// Strategy:
//   - The test entity itself stays alive throughout.
//   - A sub-entity (SubOwner) is spawned as a child of the test entity.
//   - Goap is added to SubOwner. A Planner and a root Action are added.
//   - Handles for Goap, Planner, and the root Action are captured.
//   - Request_DestroyEntity(SubOwner).
//   - WaitOneFrame to let the destruction settle.
//   - Assert: SubOwner handle invalid, Goap handle invalid, Planner handle
//     invalid, root Action handle invalid (cascade destroyed with owner).
//
// No new action classes needed - the Simple action (Ready WS) is reused
// to keep the setup minimal. The goal of this test is handle invalidation
// correctness after destroy, not plan execution.
//============================================================================

class UCk_AutoTest_Goap_Planner_OwnerCascadeDestroy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _SubOwner;
    private FCk_Handle_Goap_Planner _GoapHandle;
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_Action _RootAction;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Spawn a child entity that will host the Goap. Destroying it must
        // cascade-destroy all Goap children.
        _SubOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Assert_True(utils_handle::Get_IsValid(_SubOwner),
            "SubOwner should be a valid handle after Request_CreateEntity");

        // Add Transform (required by Goap setup).
        utils_transform::Add(_SubOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // WorldState - hosted on SubOwner so it is cascade-destroyed too.
        auto WS = utils_goap_world_state::Create(_SubOwner,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            true);

        // Create a Planner as a distinct CHILD entity of SubOwner. Create (not
        // Add) is used deliberately: Add would stamp the Planner role onto
        // SubOwner itself, collapsing the owner and the Planner into one entity
        // and defeating the point of this test (cascade from an owner to a
        // SEPARATE Planner child). Create keeps them distinct so the destroy
        // genuinely exercises the SubOwner -> Planner-child -> Action chain.
        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(TArray<FCk_GoapWS_Condition_Authored>());
        ActionSetParams.Set_WorldStateSource(WS);
        _Planner = utils_goap_planner::Create(_SubOwner,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"),
            ActionSetParams);
        Assert_True(ck::IsValid(_Planner), "Create should return a valid handle");
        _GoapHandle = _Planner;  // U11.0a: Planner is the only Goap entity.

        // Add root Action (Simple: effect Ready=true; goal already satisfied).
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Simple);
        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (implicit-root) should return a valid handle");

        // All handles are valid before destroy.
        Assert_True(utils_handle::Get_IsValid(_SubOwner),
            "Pre-destroy: SubOwner should be valid");
        Assert_True(ck::IsValid(_GoapHandle),
            "Pre-destroy: Goap handle should be valid");
        Assert_True(ck::IsValid(_Planner),
            "Pre-destroy: Planner handle should be valid");
        Assert_True(ck::IsValid(_RootAction),
            "Pre-destroy: RootAction handle should be valid");

        // Destroy SubOwner. The ECS ownership chain guarantees cascade:
        // SubOwner -> Goap entity -> Planner entity -> Action entities.
        utils_entity_lifetime::Request_DestroyEntity(_SubOwner);

        // Wait one frame for the destruction to settle.
        WaitUntil(n"Check_SubOwnerDestroyed", n"OnCheckDestroyed");
    }

    // The sub-owner is valid on entry, so the cascade teardown is what flips this.
    UFUNCTION()
    private void Check_SubOwnerDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(!utils_handle::Get_IsValid(_SubOwner));
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

        Assert_True(!ck::IsValid(_Planner),
            "Planner handle should be invalid after owner destroy (cascade)");

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
