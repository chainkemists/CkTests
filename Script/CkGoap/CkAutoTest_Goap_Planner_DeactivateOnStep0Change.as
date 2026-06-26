// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER CHAIN TRUNCATION
//============================================================================
//
// Validates §9 row 3: "Plan[0] flips mid-life → chain truncates from new
// diverge-point, OnPlannerDeactivated fires per removed Action."
//
// Setup:
//   - WS: AKey=false.
//   - Root: _InitialGoal_RootOnly={AKey=true}. Effect: AKey=true.
//   - Mid_A (child of Root): effect AKey=true. Cost 1.0 (cheaper).
//     Composite: has Leaf_A as child.
//   - Mid_B (child of Root): effect AKey=true. Cost 2.0 (costlier).
//     Composite: has Leaf_B as child.
//
// Phase 1 (initial plan):
//   Root plans → picks Mid_A (lower cost). ChainUpdate extends chain to
//   [Root, Mid_A]. OnPlannerActivated fires on Mid_A. OnPlannerDeactivated
//   is bound on Mid_A before ChainUpdate runs.
//
// Phase 2 (cost bump → replan → truncation):
//   Request_SetReplanPolicy(Root, OnEitherDirty) — ensures cost changes
//   trigger automatic replan. Request_SetActionCost(Root, Mid_A_Class, 100)
//   → Mid_A cost exceeds Mid_B's → Root replans → Plan[0]=Mid_B.
//   ChainUpdate sees chain[1]=Mid_A ≠ Plan[0]=Mid_B → truncates [Mid_A]
//   (OnPlannerDeactivated fires on Mid_A) → appends Mid_B (OnPlannerActivated
//   fires on Mid_B).
//
// Assertions:
//   - OnPlannerDeactivated fired exactly once for Mid_A.
//   - After second plan settles: chain.Num()==2, chain[1]==Mid_B_Handle.
//   - FinishSuccess.
//============================================================================

class UCk_AutoTest_Goap_Planner_DeactivateOnStep0Change : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Action _MidAAction;
    private FCk_Handle_Goap_Action _MidBAction;
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_Planner _MidAAsPlanner;

    // Phase tracking
    private bool _FirstPlanReceived = false;
    private bool _SecondPlanReceived = false;
    private int32 _MidADeactivatedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // World state — AKey drives the goal. Start false so Root has work to do.
        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            false);

        // Root: goal {AKey=true}. Both Mid_A and Mid_B satisfy it.
        // ReplanPolicy OnEitherDirty ensures cost changes auto-trigger replan.
        // U11.1: goal authored on PlannerParams.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        ActionSetParams.Set_WorldStateSource(WS);
        ActionSetParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnEitherDirty);
        _Planner = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // PR-B.1b Stage 5: Mid_A and Mid_B are direct children of the Planner.
        // No implicit-root Action — the legacy Root_ChainTruncation is dropped
        // (it had effect AKey=true cost 1.0 which would tie with Mid_A).

        // Mid_A: cost 1.0 — Planner picks this first.
        // Add Leaf_A as child to make Mid_A composite (chain extends to it).
        auto MidAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_MidA_ChainTruncation);
        _MidAAction = utils_goap_planner::AddAction(_Planner, MidAParams);
        Assert_True(ck::IsValid(_MidAAction), "Mid_A AddAction should succeed");
        _RootAction = _MidAAction;

        auto MidAPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _MidAAsPlanner = utils_goap_planner::PromoteActionToPlanner(_MidAAction, MidAPlannerParams);
        Assert_True(ck::IsValid(_MidAAsPlanner), "Mid_A PromoteActionToPlanner should succeed");
        auto MidAAsPlanner = _MidAAsPlanner;

        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_ChainTruncation);
        auto LeafAAction = utils_goap_planner::AddAction(MidAAsPlanner, LeafAParams);
        Assert_True(ck::IsValid(LeafAAction), "Leaf_A AddAction should succeed");

        // Mid_B: child of Root. Cost 2.0 — Root picks this after Mid_A is bumped.
        // Add Leaf_B as child to make Mid_B composite (chain extends to it).
        auto MidBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_MidB_ChainTruncation);
        _MidBAction = utils_goap_planner::AddAction(_Planner, MidBParams);
        Assert_True(ck::IsValid(_MidBAction), "Mid_B AddAction should succeed");

        auto MidBPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto MidBAsPlanner = utils_goap_planner::PromoteActionToPlanner(_MidBAction, MidBPlannerParams);
        Assert_True(ck::IsValid(MidBAsPlanner), "Mid_B PromoteActionToPlanner should succeed");

        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_ChainTruncation);
        auto LeafBAction = utils_goap_planner::AddAction(MidBAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "Leaf_B AddAction should succeed");

        // Bind OnPlannerDeactivated on Mid_A NOW — before ChainUpdate activates it —
        // so we cannot miss the deactivation signal when truncation fires.
        // FireIfPayloadInFlightThisFrame (default) catches same-frame signals.
        utils_goap_planner::BindTo_OnPlannerDeactivated(_MidAAsPlanner,
            FCk_Delegate_Goap_OnPlannerDeactivated(this, n"OnMidADeactivated"));

        // PR-B.1b Stage 5: chain starts empty before any plan runs.
        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(Chain.Num() == 0,
            f"ActiveChain should start empty before any plan runs (got {Chain.Num()})");

        // Wait for Root's initial plan.
        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnMidADeactivated(
        FCk_Handle_Goap_Planner InPlanner,
        FCk_Goap_Payload_OnPlannerDeactivated InPayload)
    {
        if (IsFinished()) { return; }
        _MidADeactivatedCount = _MidADeactivatedCount + 1;
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        if (_FirstPlanReceived == false)
        {
            _FirstPlanReceived = true;

            // First plan: Mid_A should be chosen (cost 1 < Mid_B cost 2).
            Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
                "Root PlanStatus should be PlanFound on first plan");

            auto RootPlan = utils_goap_planner::Get_PlanClasses(_Planner);
            Assert_True(RootPlan.Num() == 1,
                f"Root first plan should have exactly 1 entry (got {RootPlan.Num()})");
            Assert_True(RootPlan.Num() > 0 && RootPlan[0] == UCk_AutoTestAction_Goap_ActionSet_MidA_ChainTruncation,
                "Root Plan[0] should be Mid_A on first plan");

            // Wait for ChainUpdate to extend chain to [Root, Mid_A], then
            // trigger the cost-bump replan.
            WaitOneFrame(n"OnWaitForFirstChainExtension");
            return;
        }

        if (_SecondPlanReceived == false)
        {
            _SecondPlanReceived = true;

            // Second plan: Mid_B should be chosen (Mid_A cost now 100 > Mid_B cost 2).
            Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
                "Root PlanStatus should be PlanFound on second plan");

            auto RootPlan = utils_goap_planner::Get_PlanClasses(_Planner);
            Assert_True(RootPlan.Num() == 1,
                f"Root second plan should have exactly 1 entry (got {RootPlan.Num()})");
            Assert_True(RootPlan.Num() > 0 && RootPlan[0] == UCk_AutoTestAction_Goap_ActionSet_MidB_ChainTruncation,
                "Root Plan[0] should be Mid_B on second plan");

            // ChainUpdate runs after HandleResult in the same frame.
            // Wait one frame to let it truncate Mid_A and append Mid_B.
            WaitOneFrame(n"OnWaitForChainTruncation");
            return;
        }
    }

    // Poll until the first chain extension [Root, Mid_A] is visible.
    UFUNCTION()
    private void OnWaitForFirstChainExtension(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        // PR-B.1b Stage 5: chain starts at Plan[0] (Mid_A).
        if (Chain.Num() < 1)
        {
            WaitOneFrame(n"OnWaitForFirstChainExtension");
            return;
        }

        Assert_True(Chain.Num() >= 1,
            f"Chain should include Mid_A after first plan (got {Chain.Num()})");

        if (Chain.Num() >= 1)
        {
            Assert_True(Chain[0] == _MidAAction,
                "Chain[0] should be Mid_A after first plan");
        }

        // Chain is [Root, Mid_A]. Now trigger the replan by bumping Mid_A's cost.
        // OnEitherDirty policy (set at Root construction) will auto-trigger replan.
        utils_goap_planner::Request_SetChildActionCost(_Planner,
            UCk_AutoTestAction_Goap_ActionSet_MidA_ChainTruncation, 100.0);
    }

    // Wait for ChainUpdate to truncate Mid_A and extend to Mid_B.
    UFUNCTION()
    private void OnWaitForChainTruncation(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);

        // If chain still shows Mid_A, ChainUpdate hasn't processed yet.
        // Poll until chain changes to Mid_B at slot 0.
        if (Chain.Num() >= 1 && Chain[0] == _MidAAction)
        {
            WaitOneFrame(n"OnWaitForChainTruncation");
            return;
        }

        // Chain should now begin with Mid_B.
        Assert_True(Chain.Num() >= 1,
            f"ActiveChain should include Mid_B after truncation (got {Chain.Num()})");

        if (Chain.Num() >= 1)
        {
            Assert_True(Chain[0] == _MidBAction,
                "Chain[0] should be Mid_B after truncation");
        }

        Assert_True(_MidADeactivatedCount == 1,
            f"OnPlannerDeactivated should have fired exactly once for Mid_A (fired {_MidADeactivatedCount} times)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_DeactivateOnStep0Change_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_DeactivateOnStep0Change;
    default _TimeoutSeconds = 15.0f;
}
