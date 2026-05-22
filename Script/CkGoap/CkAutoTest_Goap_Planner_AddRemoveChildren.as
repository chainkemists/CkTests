// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER ADD/REMOVE CHILDREN AT RUNTIME
//============================================================================
//
// Replaces the obsolete Goap_Planner_SiblingActions test (spec §9 mapping
// table). Validates that a Planner's child Action catalog can be MUTATED at
// runtime — both ADD and REMOVE of children must be reflected in the next
// plan.
//
// Coverage map:
//   Phase A — Initial plan: Planner has only the AtomicChild leaf as child.
//             Plan = [AtomicChild].
//   Phase B — Runtime add: A SECOND cheaper leaf (UCk_AutoTestAction_Goap_AddRemove_Cheaper,
//             cost 0.5) is added under the same Planner. Request_Plan is
//             enqueued. Plan must replan to [Cheaper] because cheaper option
//             wins under regressive A*.
//   Phase C — Runtime remove: Cheaper is removed via Request_RemoveAction.
//             The planner's next plan must flip back to [AtomicChild] (the
//             only remaining candidate operator).
//
// Setup:
//   - WS: Ready=false.
//   - Top-level Planner with goal {Ready=true}.
//   - Implicit root Action: UCk_AutoTestAction_Goap_ActionSet_Root_AtomicLeaf
//     (effect Ready=true, cost 1.0 — but root cost isn't relevant; root is
//     never picked as an operator for itself).
//   - Initial child: UCk_AutoTestAction_Goap_ActionSet_AtomicChild
//     (effect Ready=true, cost 1.0).
//   - Bind OnPlanComplete on the root.
//
// Phase A — OnRootPlan (first fire):
//   Assert PlanStatus == PlanFound, Plan == [AtomicChild] (only child option).
//   AddAction(Cheaper) → planner catalog now has 2 children.
//   Request_Plan to force a replan.
//
// Phase B — OnRootPlan (second fire, after we add Cheaper):
//   Assert Plan == [Cheaper] (lower cost wins).
//   Request_RemoveAction(Cheaper) → planner catalog drops back to 1 child.
//
// Phase C — OnRootPlan (third fire, after we remove Cheaper):
//   Assert Plan == [AtomicChild] (only remaining candidate operator).
//   FinishSuccess.
//============================================================================

class UCk_AutoTest_Goap_Planner_AddRemoveChildren : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private int32 _PlansReceived = 0;
    private bool _CheaperAdded = false;
    private bool _CheaperRemoved = false;
    private int32 _SettleFrameCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            false);

        // U11.1: planner goal {Ready=true}.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        ActionSetParams.Set_WorldStateSource(WS);
        _Planner = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // Implicit root.
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_AtomicLeaf);
        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (implicit-root) should return a valid handle");

        // Initial child: AtomicChild (cost 1.0).
        auto AtomicParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_AtomicChild);
        auto AtomicAction = utils_goap_planner::AddAction(_Planner, AtomicParams);
        Assert_True(ck::IsValid(AtomicAction), "AddAction (AtomicChild) should return a valid handle");

        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        _PlansReceived = _PlansReceived + 1;

        Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
            "PlanStatus should be PlanFound");

        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);

        if (_PlansReceived == 1)
        {
            // Phase A — initial plan should be [AtomicChild] (only available option).
            Assert_True(Plan.Num() == 1,
                f"Phase A: plan should have exactly 1 entry (got {Plan.Num()})");
            Assert_True(Plan.Num() > 0 && Plan[0] == UCk_AutoTestAction_Goap_ActionSet_AtomicChild,
                "Phase A: Plan[0] should be AtomicChild");

            // Runtime mutation: add a cheaper sibling Action under the same planner.
            auto CheaperParams = FCk_Fragment_Goap_ActionParamsData(
                UCk_AutoTestAction_Goap_AddRemove_Cheaper);
            auto CheaperAction = utils_goap_planner::AddAction(_Planner, CheaperParams);
            Assert_True(ck::IsValid(CheaperAction),
                "Runtime AddAction (Cheaper) should return a valid handle");
            _CheaperAdded = true;

            // Cheaper needs Setup to populate its _CachedActionDef (cost,
            // effects) before the planner's next A* graph build can consume
            // it. Setup runs in FGroup_Gameplay_AI on the next tick, so wait
            // a few frames before triggering the replan to make sure Cheaper
            // is fully registered as a candidate operator.
            _SettleFrameCount = 0;
            WaitOneFrame(n"OnSettleBeforeReplan");
            return;
        }

        if (_PlansReceived == 2)
        {
            // Phase B — replan after the runtime add.
            Assert_True(_CheaperAdded, "Phase B should only fire after Cheaper was added");
            Assert_True(Plan.Num() == 1,
                f"Phase B: plan should have exactly 1 entry (got {Plan.Num()})");
            Assert_True(Plan.Num() > 0 && Plan[0] == UCk_AutoTestAction_Goap_AddRemove_Cheaper,
                "Phase B: Plan[0] should be Cheaper (cost 0.5 < AtomicChild cost 1.0)");

            // Runtime mutation: remove Cheaper from the catalog. Request_Plan
            // is enqueued internally by Request_RemoveAction so we don't need
            // to call it again. Settle a few frames to let the catalog mutation
            // + setup re-run propagate before the next plan completes.
            utils_goap_planner::Request_RemoveAction(_Planner,
                UCk_AutoTestAction_Goap_AddRemove_Cheaper);
            _CheaperRemoved = true;
            return;
        }

        // Phase C — replan after the runtime remove.
        Assert_True(_CheaperRemoved, "Phase C should only fire after Cheaper was removed");
        Assert_True(Plan.Num() == 1,
            f"Phase C: plan should have exactly 1 entry (got {Plan.Num()})");
        Assert_True(Plan.Num() > 0 && Plan[0] == UCk_AutoTestAction_Goap_ActionSet_AtomicChild,
            "Phase C: Plan[0] should be AtomicChild (only candidate remaining after Cheaper removed)");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnSettleBeforeReplan(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _SettleFrameCount = _SettleFrameCount + 1;
        if (_SettleFrameCount < 3)
        {
            WaitOneFrame(n"OnSettleBeforeReplan");
            return;
        }

        // Now that Cheaper has been through Setup, force a replan.
        utils_goap_planner::Request_Plan(_Planner);
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_AddRemoveChildren_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_AddRemoveChildren;
    default _TimeoutSeconds = 15.0f;
}
