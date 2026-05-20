// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: MULTI-ACTIONSET INDEPENDENT TICKING
//============================================================================
//
// Validates spec §9 row 10: "Two ActionSets on one entity tick independently."
//
// Setup:
//   - Single Goap root on one entity.
//   - ActionSet A: tag AutoTest.Goap.ActionSet.Set,
//       root = UCk_AutoTestAction_Goap_ActionSet_Root_MultiA
//       goal {AKey=true}, WS pre-seeded AKey=true → empty plan → PlanFound.
//   - ActionSet B: tag AutoTest.Goap.ActionSet.Set2,
//       root = UCk_AutoTestAction_Goap_ActionSet_Root_MultiB
//       goal {BKey=true}, WS pre-seeded BKey=true → empty plan → PlanFound.
//   - Both share the same WorldState entity.
//   - Bind OnPlanComplete on each root independently.
//
// Expected:
//   - Both OnPlanComplete callbacks fire (independently).
//   - Both report PlanFound.
//   - The two ActionSets' roots are distinct handles.
//   - FinishSuccess after both fire.
//============================================================================

class UCk_AutoTest_Goap_ActionSet_MultiActionSet : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Goap_Action _RootA;
    private FCk_Handle_Goap_Action _RootB;
    private bool _PlanAReceived = false;
    private bool _PlanBReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Shared WorldState entity. Pre-register both keys as satisfied so
        // both planners find PlanFound immediately (empty plan).
        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true);

        // Goap root container on the entity.
        auto Goap = utils_goap::Add(Local, FCk_Fragment_Goap_RootParamsData());
        Assert_True(utils_goap::Has(Goap), "Has(Goap) should be true after Add");

        // ---- ActionSet A ----
        auto ActionSetParamsA = FCk_Fragment_Goap_ActionSetParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto ActionSetA = utils_goap_action_set::AddActionSet(Goap, ActionSetParamsA);
        Assert_True(ck::IsValid(ActionSetA), "AddActionSet A should return a valid handle");

        auto GoalA = TArray<FCk_GoapWS_Condition_Authored>();
        GoalA.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));
        auto RootParamsA = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_MultiA);
        RootParamsA.Set_InitialGoal_RootOnly(GoalA);

        _RootA = utils_goap_action_set::SetRootAction(ActionSetA, RootParamsA, WS);
        Assert_True(ck::IsValid(_RootA), "SetRootAction A should return a valid handle");

        // ---- ActionSet B ----
        auto ActionSetParamsB = FCk_Fragment_Goap_ActionSetParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set2"));
        auto ActionSetB = utils_goap_action_set::AddActionSet(Goap, ActionSetParamsB);
        Assert_True(ck::IsValid(ActionSetB), "AddActionSet B should return a valid handle");

        auto GoalB = TArray<FCk_GoapWS_Condition_Authored>();
        GoalB.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));
        auto RootParamsB = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_MultiB);
        RootParamsB.Set_InitialGoal_RootOnly(GoalB);

        _RootB = utils_goap_action_set::SetRootAction(ActionSetB, RootParamsB, WS);
        Assert_True(ck::IsValid(_RootB), "SetRootAction B should return a valid handle");

        // The two roots must be distinct handles.
        Assert_True(!(_RootA == _RootB),
            "ActionSet A root and ActionSet B root must be distinct Action handles");

        // Bind OnPlanComplete on each root independently.
        utils_goap_action::BindTo_OnPlanComplete(_RootA,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnPlanA"));
        utils_goap_action::BindTo_OnPlanComplete(_RootB,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnPlanB"));
    }

    UFUNCTION()
    private void OnPlanA(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanAReceived) { return; }
        _PlanAReceived = true;

        Assert_True(utils_goap_action::Get_PlanStatus(_RootA) == ECk_GoapPlanStatus::PlanFound,
            "ActionSet A root PlanStatus should be PlanFound");

        TryFinish();
    }

    UFUNCTION()
    private void OnPlanB(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanBReceived) { return; }
        _PlanBReceived = true;

        Assert_True(utils_goap_action::Get_PlanStatus(_RootB) == ECk_GoapPlanStatus::PlanFound,
            "ActionSet B root PlanStatus should be PlanFound");

        TryFinish();
    }

    private void TryFinish()
    {
        if (!_PlanAReceived || !_PlanBReceived) { return; }

        // Both plans fired. The two roots are distinct — confirm again now
        // that both are live (planning may have mutated handles).
        Assert_True(ck::IsValid(_RootA), "RootA should still be valid after both plans fired");
        Assert_True(ck::IsValid(_RootB), "RootB should still be valid after both plans fired");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_MultiActionSet_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_MultiActionSet;
    default _TimeoutSeconds = 10.0f;
}
