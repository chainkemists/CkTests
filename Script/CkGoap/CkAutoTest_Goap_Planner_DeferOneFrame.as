// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER DEFER ONE FRAME
//============================================================================
//
// Validates §9 row 13: "Newly-appended Action does NOT plan in activation
// frame; plans in frame+1."
//
// ChainUpdate appends Mid to the chain and adds FTag_Goap_Action_RequiresInitialPlan.
// AutoReplan picks this up on the NEXT frame to enqueue a plan request.
// Therefore Mid's PlanStatus must still be Idle in the same frame that
// ChainUpdate fires.
//
// Setup (reuses GoalIsEffects hierarchy):
//   - WS: AKey=false, BKey=false.
//   - Root: _InitialGoal_RootOnly={BKey=true}. CDO effect=AKey=true.
//   - Mid (child of Root): CDO effect=BKey=true. Composite (has Leaf_B).
//   - Leaf_B (child of Mid): CDO effect=BKey=true. Atomic.
//
// Mid uses the DEFAULT _PlanOnStart=true. The framework's parent-plan gating
// (FTag_Goap_Action_PlanInFlight + parent status check in HandleRequests)
// keeps Mid Idle until Root's plan reaches a terminal status. AutoReplan
// enqueues Mid's initial Plan request, but HandleRequests defers it (re-enqueues
// to the same queue) while Root is still planning. Once Root's plan settles
// to PlanFound, the gate releases and Mid's next HandleRequests pass drains
// the request and starts Mid's search.
//
// Phase 1: Root plans and finds Mid (satisfies BKey=true). OnPlanComplete
//   fires for Root.
//
// Phase 2: In OnRootPlan, retrieve Mid via Find_ActionByClass. ChainUpdate has
//   NOT yet run for this frame (HandleResult fires OnPlanComplete before
//   ChainUpdate processes). Mid's PlanStatus must be Idle — the parent-plan
//   gate held Mid's Plan request deferred while Root was Planning, so Mid
//   never transitioned out of Idle.
//
// Phase 3: Wait one frame (ChainUpdate runs, appends Mid to chain, adds
//   RequiresInitialPlan). Then poll until Mid has PlanFound — with Root now
//   in PlanFound, Mid's deferred Plan request drains on the next HandleRequests
//   pass and Mid's search completes.
//
// The key invariant: Mid is Idle in the same frame as Root's HandleResult
// (activation frame). Mid plans in frame+1 or later, not the same frame.
//============================================================================

class UCk_AutoTest_Goap_Planner_DeferOneFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private bool _RootPlanReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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

        // Root goal: {BKey=true}. Root CDO effect: AKey=true (distinct intentionally).
        // Mid's CDO effect: BKey=true → Root's planner picks Mid.
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

        // PR-B.1b Stage 5: Mid is a direct child of the Planner. No implicit
        // root. Mid is promoted to a Planner with its own goal {BKey=true} so
        // the parent-plan gate (planner-side PlanInFlight) defers Mid's
        // initial Plan request until the top-level Planner settles.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        auto MidAction = utils_goap_planner::AddAction(_Planner, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction should succeed");
        _RootAction = MidAction;

        // Promote Mid to a Planner with goal {BKey=true}. Pre-U11.1, Mid's goal
        // was implicitly injected from its CDO effects. The goal is now set
        // explicitly via PromoteActionToPlanner; the original intent is preserved
        // by using the same {BKey=true} so Mid's deferred plan resolves to [Leaf_B].
        auto MidGoal = TArray<FCk_GoapWS_Condition_Authored>();
        MidGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));
        auto MidPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        MidPlannerParams.Set_Goal(MidGoal);
        auto MidAsPlanner = utils_goap_planner::PromoteActionToPlanner(MidAction, MidPlannerParams);

        // Add Leaf_B as child of Mid (makes Mid composite).
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(MidAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "Leaf_B AddAction should succeed");

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

        // At this moment (inside HandleResult's signal callback), ChainUpdate
        // has NOT yet run for this frame. Mid had its initial Plan request
        // enqueued by AutoReplan but the parent-plan gate deferred it while
        // Root was Planning, so Mid's PlanStatus must still be Idle.
        auto MidHandle = utils_goap_planner::Find_ActionByClass(
            _Planner, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        Assert_True(ck::IsValid(MidHandle), "Should find Mid by class in Planner catalog");

        if (ck::IsValid(MidHandle))
        {
            auto MidStatusBeforeChainUpdate = utils_goap_action::Get_PlanStatus(MidHandle);
            Assert_True(MidStatusBeforeChainUpdate == ECk_GoapPlanStatus::Idle,
                "Mid PlanStatus must be Idle before ChainUpdate runs (parent-plan gate defers Mid until Root settles)");
        }

        // Wait one frame so ChainUpdate appends Mid and sets RequiresInitialPlan.
        WaitOneFrame(n"OnCheckAfterChainUpdate");
    }

    UFUNCTION()
    private void OnCheckAfterChainUpdate(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto MidHandle = utils_goap_planner::Find_ActionByClass(
            _Planner, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        Assert_True(ck::IsValid(MidHandle), "Should still find Mid by class after one frame");

        if (ck::IsValid(MidHandle) == false)
        {
            FinishSuccess();
            return;
        }

        // ChainUpdate should have placed Mid at chain[0] by now.
        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        if (Chain.Num() < 1)
        {
            WaitOneFrame(n"OnCheckAfterChainUpdate");
            return;
        }

        Assert_True(Chain.Num() >= 1,
            f"ActiveChain should include Mid after one frame (got {Chain.Num()})");
        Assert_True(Chain.Num() >= 1 && Chain[0] == MidHandle,
            "Chain[0] should be Mid after ChainUpdate appended it");

        // Mid has been appended. Now poll until Mid has PlanFound to verify
        // that the deferred plan fires on frame+1 (not the same frame as appending).
        WaitOneFrame(n"OnWaitForMidPlan");
    }

    UFUNCTION()
    private void OnWaitForMidPlan(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto MidHandle = utils_goap_planner::Find_ActionByClass(
            _Planner, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        if (ck::IsValid(MidHandle) == false)
        {
            Assert_True(false, "Mid handle lost while waiting for its plan");
            return;
        }

        auto MidStatus = utils_goap_action::Get_PlanStatus(MidHandle);
        if (MidStatus == ECk_GoapPlanStatus::Planning || MidStatus == ECk_GoapPlanStatus::Idle)
        {
            // Still in progress — give it another frame.
            WaitOneFrame(n"OnWaitForMidPlan");
            return;
        }

        Assert_True(MidStatus == ECk_GoapPlanStatus::PlanFound,
            "Mid PlanStatus should eventually be PlanFound after deferred plan");

        auto MidPlan = utils_goap_action::Get_Plan(MidHandle);
        Assert_True(MidPlan.Num() == 1,
            f"Mid plan should have exactly 1 entry after deferred planning (got {MidPlan.Num()})");
        Assert_True(MidPlan.Num() > 0 && MidPlan[0] == UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects,
            "Mid Plan[0] should be Leaf_B");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_DeferOneFrame_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_DeferOneFrame;
    default _TimeoutSeconds = 15.0f;
}
