// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER RESET ACTIVE CHAIN
//============================================================================
//
// Validates §9 row 14: "`Request_ResetActiveChain` collapses chain to root;
// OnPlannerDeactivated fires per removed Action."
//
// Setup mirrors GoalIsEffects hierarchy:
//   - Root effect: AKey=true. _InitialGoal_RootOnly: {BKey=true}.
//   - Mid (child of Root): effect BKey=true. Composite (has LeafB, LeafA).
//   - LeafB (child of Mid): effect BKey=true.
//   - LeafA (child of Mid): effect AKey=true.
//
// Phase 1: Wait for Root to plan [Mid]. ChainUpdate extends chain to
//   [Root, Mid]. Assert chain.Num() == 2.
//
// Phase 2: Bind OnPlannerDeactivated on Mid. Call Request_ResetActiveChain.
//   After WaitOneFrame, assert:
//   - Get_ActiveChain.Num() == 1  (root only)
//   - OnPlannerDeactivated fired for Mid  (_DeactivatedCount == 1)
//
// Reuses the GoalIsEffects action class files to avoid code duplication.
//============================================================================

class UCk_AutoTest_Goap_Planner_DeactivateChildren : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_Planner _MidAsPlanner;
    private bool _RootPlanReceived = false;
    private int32 _DeactivatedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Goap_WorldState_Spec());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            false);

        // Root's planning goal = {BKey=true}. Root's CDO effect = AKey=true.
        // Mid (effect BKey=true) satisfies Root's goal → Root plan = [Mid].
        // U11.1: goal authored on PlannerParams.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto ActionSetParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        ActionSetParams.Set_WorldStateSource(WS);
        _Planner = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // PR-B.1b Stage 5: Mid is a direct child of the Planner. The legacy
        // Root_GoalIsEffects implicit-root Action is dropped.
        auto MidParams = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        auto MidAction = utils_goap_planner::AddAction(_Planner, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction should succeed");
        _RootAction = MidAction;

        // Promote Mid so Leaf_A/Leaf_B become its tree children.
        auto MidPlannerParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _MidAsPlanner = utils_goap_planner::PromoteActionToPlanner(MidAction, MidPlannerParams);
        Assert_True(ck::IsValid(_MidAsPlanner), "Mid PromoteActionToPlanner should succeed");
        auto MidAsPlanner = _MidAsPlanner;

        // Add Leaf_B and Leaf_A as children of Mid (makes Mid composite).
        auto LeafBParams = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(MidAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction should succeed");

        auto LeafAParams = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        auto LeafAAction = utils_goap_planner::AddAction(MidAsPlanner, LeafAParams);
        Assert_True(ck::IsValid(LeafAAction), "LeafA AddAction should succeed");

        // Wait for Root to plan and ChainUpdate to extend to [Root, Mid].
        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_RootPlanReceived) { return; }
        _RootPlanReceived = true;

        Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
            "Root PlanStatus should be PlanFound");

        auto RootPlan = utils_goap_planner::Get_PlanClasses(_Planner);
        Assert_True(RootPlan.Num() == 1,
            f"Root plan should have exactly 1 entry (got {RootPlan.Num()})");
        Assert_True(RootPlan.Num() > 0 && RootPlan[0] == UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects,
            "Root Plan[0] should be Mid");

        // PR-B.1b Stage 5: chain starts at Plan[0] (Mid) and walks through Mid's
        // own Plan[0] (one of its leaves). Wait until at least Mid is active —
        // the previous self-re-arming poll ran out the engine TimeLimit as an
        // anonymous TimesUp if ChainUpdate never extended.
        WaitUntil(n"Check_ChainExtended", n"OnWaitForChainExtension");
    }

    UFUNCTION()
    private void Check_ChainExtended(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_ActiveChain(_Planner).Num() >= 1);
    }

    UFUNCTION()
    private void OnWaitForChainExtension(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Bind OnPlannerDeactivated on Mid BEFORE calling ResetActiveChain.
        // Request_ResetActiveChain fires the signal synchronously (inline teardown),
        // so the delegate will be invoked during the reset call itself.
        auto MidHandle = utils_goap_planner::Find_ActionByClass(
            _Planner, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        Assert_True(ck::IsValid(MidHandle), "Should find Mid by class in Planner catalog");

        if (ck::IsValid(MidHandle))
        {
            utils_goap_planner::BindTo_OnPlannerDeactivated(_MidAsPlanner,
                FCk_Delegate_Goap_OnPlannerDeactivated(this, n"OnMidDeactivated"));
        }

        // Reset the chain. Teardown and OnPlannerDeactivated broadcast happen
        // synchronously inside Request_ResetActiveChain.
        utils_goap_planner::Request_ResetActiveChain(_Planner);

        // Verify chain collapsed immediately (synchronous operation).
        // PR-B.1b Stage 5: no more implicit-root prefix — chain is fully empty.
        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(Chain.Num() == 0,
            f"ActiveChain should collapse to [] immediately after Request_ResetActiveChain (got {Chain.Num()})");

        // Disable Planner so ChainUpdate doesn't re-extend the chain on the
        // next frame (Root's plan still shows Mid, so ChainUpdate would normally
        // re-append it). We're testing the reset behavior, not re-extension.
        utils_goap_planner::Request_SetEnableToggle(_Planner, ECk_EnableDisable::Disable);

        // Give the signal one frame to dispatch to bound delegates before asserting.
        WaitOneFrame(n"OnCheckDeactivation");
    }

    UFUNCTION()
    private void OnMidDeactivated(
        FCk_Handle_Goap_Planner InPlanner,
        FCk_Goap_Payload_OnPlannerDeactivated InPayload)
    {
        _DeactivatedCount = _DeactivatedCount + 1;
    }

    UFUNCTION()
    private void OnCheckDeactivation(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(Chain.Num() == 0,
            f"ActiveChain should remain empty after ResetChain (Planner disabled to prevent re-extension; got {Chain.Num()})");

        Assert_True(_DeactivatedCount == 1,
            f"OnPlannerDeactivated should have fired exactly once for Mid (fired {_DeactivatedCount} times)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_DeactivateChildren_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_DeactivateChildren;
    default _TimeoutSeconds = 15.0f;
}
