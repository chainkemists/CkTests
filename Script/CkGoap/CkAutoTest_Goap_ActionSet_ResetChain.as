// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET RESET ACTIVE CHAIN
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

class UCk_AutoTest_Goap_ActionSet_ResetChain : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _ActionSet;
    private bool _RootPlanReceived = false;
    private int32 _DeactivatedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
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

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        _ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);

        _RootAction = utils_goap_planner::SetRootAction(_ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // Add Mid as composite child of Root.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        auto MidAction = utils_goap_action::AddAction_ToAction(_RootAction, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction_ToAction should succeed");

        // Add Leaf_B and Leaf_A as children of Mid (makes Mid composite).
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_action::AddAction_ToAction(MidAction, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction_ToAction should succeed");

        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        auto LeafAAction = utils_goap_action::AddAction_ToAction(MidAction, LeafAParams);
        Assert_True(ck::IsValid(LeafAAction), "LeafA AddAction_ToAction should succeed");

        // Wait for Root to plan and ChainUpdate to extend to [Root, Mid].
        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_RootPlanReceived) { return; }
        _RootPlanReceived = true;

        Assert_True(utils_goap_action::Get_PlanStatus(_RootAction) == ECk_GoapPlanStatus::PlanFound,
            "Root PlanStatus should be PlanFound");

        auto RootPlan = utils_goap_action::Get_Plan(_RootAction);
        Assert_True(RootPlan.Num() == 1,
            f"Root plan should have exactly 1 entry (got {RootPlan.Num()})");
        Assert_True(RootPlan.Num() > 0 && RootPlan[0] == UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects,
            "Root Plan[0] should be Mid");

        // Wait one frame for ChainUpdate to extend chain to [Root, Mid].
        WaitOneFrame(n"OnWaitForChainExtension");
    }

    UFUNCTION()
    private void OnWaitForChainExtension(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);

        // ChainUpdate may need another frame if it ran before HandleResult in
        // the same frame. Poll until chain length == 2.
        if (Chain.Num() < 2)
        {
            WaitOneFrame(n"OnWaitForChainExtension");
            return;
        }

        Assert_True(Chain.Num() == 2,
            f"ActiveChain should be [Root, Mid] before reset (got {Chain.Num()})");

        // Bind OnPlannerDeactivated on Mid BEFORE calling ResetActiveChain.
        // Request_ResetActiveChain fires the signal synchronously (inline teardown),
        // so the delegate will be invoked during the reset call itself.
        auto MidHandle = utils_goap_planner::Find_ActionByClass(
            _ActionSet, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        Assert_True(ck::IsValid(MidHandle), "Should find Mid by class in ActionSet catalog");

        if (ck::IsValid(MidHandle))
        {
            utils_goap_action::BindTo_OnPlannerDeactivated(MidHandle,
                FCk_Delegate_Goap_OnPlannerDeactivated(this, n"OnMidDeactivated"));
        }

        // Reset the chain. Teardown and OnPlannerDeactivated broadcast happen
        // synchronously inside Request_ResetActiveChain.
        utils_goap_planner::Request_ResetActiveChain(_ActionSet);

        // Verify chain collapsed immediately (synchronous operation).
        Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"ActiveChain should collapse to [Root] immediately after Request_ResetActiveChain (got {Chain.Num()})");

        // Disable ActionSet so ChainUpdate doesn't re-extend the chain on the
        // next frame (Root's plan still shows Mid, so ChainUpdate would normally
        // re-append it). We're testing the reset behavior, not re-extension.
        utils_goap_planner::Request_SetEnableToggle(_ActionSet, ECk_EnableDisable::Disable);

        // Give the signal one frame to dispatch to bound delegates before asserting.
        WaitOneFrame(n"OnCheckDeactivation");
    }

    UFUNCTION()
    private void OnMidDeactivated(
        FCk_Handle_Goap_Action InAction,
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

        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"ActiveChain should remain at length 1 after ResetChain (ActionSet disabled to prevent re-extension; got {Chain.Num()})");

        Assert_True(_DeactivatedCount == 1,
            f"OnPlannerDeactivated should have fired exactly once for Mid (fired {_DeactivatedCount} times)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_ResetChain_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_ResetChain;
    default _TimeoutSeconds = 15.0f;
}
