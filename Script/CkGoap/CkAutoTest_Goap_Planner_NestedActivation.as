// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER CHAIN GROWTH
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
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_Planner _MidAsPlanner;
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
        _Planner = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // PR-B.1b Stage 5: Mid is a direct child of the Planner. Adding it
        // alone (no sibling Root_GoalIsEffects) so the planner's only path to
        // BKey=true is through Mid.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        _MidAction = utils_goap_planner::AddAction(_Planner, MidParams);
        Assert_True(ck::IsValid(_MidAction), "Mid AddAction should succeed");

        // Promote Mid so LeafB becomes its tree child (makes Mid composite).
        auto MidPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _MidAsPlanner = utils_goap_planner::PromoteActionToPlanner(_MidAction, MidPlannerParams);
        Assert_True(ck::IsValid(_MidAsPlanner), "Mid PromoteActionToPlanner should succeed");
        auto MidAsPlanner = _MidAsPlanner;

        // Add LeafB as a tree child of promoted Mid — makes Mid composite so
        // UpdateActivation extends the chain through Mid.
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(MidAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction should succeed");

        // Bind OnPlannerActivated on Mid NOW — before UpdateActivation runs — so
        // we cannot miss the activation signal.
        utils_goap_planner::BindTo_OnPlannerActivated(_MidAsPlanner,
            FCk_Delegate_Goap_OnPlannerActivated(this, n"OnMidActivated"));

        // Wait for the top-level Planner to plan; chain extends through Mid
        // when UpdateActivation runs.
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
            "Top-level PlanStatus should be PlanFound");

        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);
        Assert_True(Plan.Num() == 1,
            f"Plan should have exactly 1 entry (got {Plan.Num()})");
        Assert_True(Plan.Num() > 0 && Plan[0] == UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects,
            "Plan[0] should be Mid_GoalIsEffects");

        WaitOneFrame(n"OnPollForChainExtension");
    }

    UFUNCTION()
    private void OnMidActivated(
        FCk_Handle_Goap_Planner InPlanner,
        FCk_Goap_Payload_OnPlannerActivated InPayload)
    {
        if (IsFinished()) { return; }

        _ActivatedCount = _ActivatedCount + 1;

        // Verify the chain extends through Mid. PR-B.1b Stage 5: the chain
        // starts at Plan[0] (Mid), then walks Mid's Plan[0] (LeafB) — so the
        // chain is [Mid, LeafB].
        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(Chain.Num() >= 1,
            f"ActiveChain should include Mid when OnPlannerActivated fires (got {Chain.Num()})");

        if (Chain.Num() >= 1)
        {
            Assert_True(Chain[0] == _MidAction,
                "Chain[0] should be the Mid action handle");
        }

        Assert_True(_ActivatedCount == 1,
            f"OnPlannerActivated should have fired exactly once (fired {_ActivatedCount} times)");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnPollForChainExtension(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        if (Chain.Num() < 1)
        {
            WaitOneFrame(n"OnPollForChainExtension");
            return;
        }

        Assert_True(_ActivatedCount == 1,
            f"OnPlannerActivated should have fired once when chain extended (fired {_ActivatedCount} times)");

        Assert_True(Chain.Num() >= 1,
            f"ActiveChain should include Mid (got {Chain.Num()})");

        if (Chain.Num() >= 1)
        {
            Assert_True(Chain[0] == _MidAction,
                "Chain[0] should be the Mid action handle");
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
