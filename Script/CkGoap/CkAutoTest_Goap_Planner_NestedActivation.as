// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET CHAIN GROWTH
//============================================================================
//
// Validates §9 row 2: "Plan[0] is a composite Action → chain extends,
// OnPlannerActivated fires."
//
// Setup reuses the GoalIsEffects action class hierarchy:
//   - Root CDO effect: AKey=true. _InitialGoal_RootOnly: {BKey=true}.
//   - Mid (child of Root): effect BKey=true → satisfies Root's goal.
//     Mid is composite (has LeafB as child) → ChainUpdate extends the chain.
//   - LeafB (child of Mid): effect BKey=true → satisfies Mid's goal.
//
// Phase 1: Bind OnPlannerActivated on Mid immediately in DoBeginPlay
//   (before ChainUpdate can activate Mid). The binding policy is
//   FireIfPayloadInFlightThisFrame so a same-frame activation is not missed.
//
// Phase 2: Wait for Root to plan [Mid] via OnPlanComplete.
//   Assert Root plan = [Mid]. Mid will then be activated by ChainUpdate
//   on the next frame.
//
// Phase 3: OnMidActivated fires when ChainUpdate appends Mid to the chain.
//   Assert:
//     - Get_ActiveChain.Num() == 2  (chain extended from [Root] to [Root, Mid])
//     - Get_ActiveChain()[1] == MidHandle
//     - OnPlannerActivated fired exactly once
//   FinishSuccess.
//
// Reuses GoalIsEffects action class files to avoid code duplication.
//============================================================================

class UCk_AutoTest_Goap_Planner_NestedActivation : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Action _MidAction;
    private FCk_Handle_Goap_Planner _ActionSet;
    private bool _RootPlanReceived = false;
    private int32 _ActivatedCount = 0;

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

        // Root's planning goal = {BKey=true}. Root's CDO effect = AKey=true
        // (distinct from goal). Mid's effect BKey=true satisfies Root's goal
        // so Root's plan = [Mid].
        // U11.1: goal authored on PlannerParams.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        ActionSetParams.Set_WorldStateSource(WS);
        _ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "Add Planner should return a valid handle");

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);

        _RootAction = utils_goap_planner::AddAction(_ActionSet, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (implicit-root) should return a valid handle");

        // Add Mid as composite child of Root.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        _MidAction = utils_goap_planner::AddAction(_ActionSet, MidParams);
        Assert_True(ck::IsValid(_MidAction), "Mid AddAction should succeed");

        // Promote Mid so LeafB becomes its tree child (makes Mid composite).
        auto MidPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto MidAsPlanner = utils_goap_planner::PromoteActionToPlanner(_MidAction, MidPlannerParams);
        Assert_True(ck::IsValid(MidAsPlanner), "Mid PromoteActionToPlanner should succeed");

        // Add LeafB as child of Mid — makes Mid composite so ChainUpdate
        // extends the chain to [Root, Mid].
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(MidAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction should succeed");

        // Bind OnPlannerActivated on Mid NOW — before ChainUpdate runs — so we
        // cannot miss the activation signal. FireIfPayloadInFlightThisFrame
        // (default) means even a same-frame activation is caught.
        utils_goap_action::BindTo_OnPlannerActivated(_MidAction,
            FCk_Delegate_Goap_OnPlannerActivated(this, n"OnMidActivated"));

        // Initial chain has only Root.
        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"ActiveChain should start with only Root (got {Chain.Num()})");

        // Wait for Root to plan before asserting chain extension.
        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_RootPlanReceived) { return; }
        _RootPlanReceived = true;

        Assert_True(utils_goap_planner::Get_PlanStatus(_ActionSet) == ECk_GoapPlanStatus::PlanFound,
            "Root PlanStatus should be PlanFound");

        auto RootPlan = utils_goap_planner::Get_PlanClasses(_ActionSet);
        Assert_True(RootPlan.Num() == 1,
            f"Root plan should have exactly 1 entry (got {RootPlan.Num()})");
        Assert_True(RootPlan.Num() > 0 && RootPlan[0] == UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects,
            "Root Plan[0] should be Mid_GoalIsEffects");

        // ChainUpdate runs after HandleResult in the same frame and will
        // activate Mid. OnMidActivated will fire when that happens.
        // If ChainUpdate already ran this frame and Mid is already activated
        // (FireIfPayloadInFlightThisFrame covers that), we poll as a fallback.
        WaitOneFrame(n"OnPollForChainExtension");
    }

    UFUNCTION()
    private void OnMidActivated(
        FCk_Handle_Goap_Action InAction,
        FCk_Goap_Payload_OnPlannerActivated InPayload)
    {
        if (IsFinished()) { return; }

        _ActivatedCount = _ActivatedCount + 1;

        // Verify chain has extended to [Root, Mid].
        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 2,
            f"ActiveChain should be [Root, Mid] when OnPlannerActivated fires (got {Chain.Num()})");

        if (Chain.Num() >= 2)
        {
            Assert_True(Chain[1] == _MidAction,
                "Chain[1] should be the Mid action handle");
        }

        Assert_True(_ActivatedCount == 1,
            f"OnPlannerActivated should have fired exactly once (fired {_ActivatedCount} times)");

        FinishSuccess();
    }

    // Fallback poll: if OnMidActivated hasn't fired yet (signal races), keep
    // waiting until chain extends or timeout.
    UFUNCTION()
    private void OnPollForChainExtension(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        if (Chain.Num() < 2)
        {
            // ChainUpdate hasn't extended yet — wait another frame.
            WaitOneFrame(n"OnPollForChainExtension");
            return;
        }

        // Chain extended but OnMidActivated didn't fire (unexpected).
        // Assert here to produce a meaningful failure.
        Assert_True(_ActivatedCount == 1,
            f"OnPlannerActivated should have fired once when chain extended to [Root, Mid] (fired {_ActivatedCount} times)");

        Assert_True(Chain.Num() == 2,
            f"ActiveChain should be [Root, Mid] (got {Chain.Num()})");

        if (Chain.Num() >= 2)
        {
            Assert_True(Chain[1] == _MidAction,
                "Chain[1] should be the Mid action handle");
        }

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_NestedActivation_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_NestedActivation;
    default _TimeoutSeconds = 15.0f;
}
