// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: PLANNER CANCEL IN-FLIGHT PLAN
//============================================================================
//
// Validates utils_goap_planner::Request_CancelPlan(Planner).
//
// Per FProcessor_Goap_Action_HandleRequests:
//   FCk_Request_Goap_Action_CancelPlan handler:
//     - Removes FTag_AStar_SearchActive, FTag_AStar_SearchComplete
//     - Removes FTag_Goap_Action_PlanInFlight  (U9 cleanup)
//     - Resets _State, _PlanStatus = Idle, _Plan = {}, _PlanCost = 0
//
// Strategy:
//   - Set _PlanOnStart=false on Root so no automatic plan fires.
//   - WS with goal NOT pre-satisfied (BKey=false; goal {BKey=true}) so the
//     planner has actual A* work to do.
//   - Add Mid (composite via LeafB) so Root has a candidate child to search.
//   - Bind OnPlanComplete on Root to fail the test if it ever fires.
//   - After WaitOneFrame (so Setup runs and Action is ready to plan):
//       Request_Plan(Root) - queues plan request.
//       Request_CancelPlan(Root) - queues cancel request immediately after.
//     Both run in the same FProcessor_Goap_Action_HandleRequests pass; the
//     Plan handler seeds search state (Planning), then the Cancel handler
//     tears it down (Idle).
//   - Wait a few frames, then assert:
//       Get_PlanStatus(Root) == Idle  (cancel tore down the in-flight plan).
//       Get_Plan(Root).Num() == 0     (no plan produced).
//       _PlanCompleteFiredCount == 0  (no OnPlanComplete signal).
//   - FinishSuccess.
//============================================================================

class UCk_AutoTest_Goap_Planner_CancelInflight : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_Action _RootAction;
    private int32 _PlanCompleteFiredCount = 0;
    private int32 _SettleFrameCount = 0;

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

        // U11.1: Planner goal={BKey=true} - NOT pre-satisfied (BKey=false),
        // so the planner has actual A* search work.
        // _PlanOnStart=false so no implicit plan races the test's manual sequence.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        ActionSetParams.Set_WorldStateSource(WS);
        ActionSetParams.Set_PlanOnStart(false);
        // Explicit replan policy: never replan automatically. Only our manual
        // Request_Plan should trigger planning.
        ActionSetParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::Explicit);
        _Planner = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);

        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (Root) should return a valid handle");

        // Mid (composite child of Root) - gives the planner a candidate operator.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        auto MidAction = utils_goap_planner::AddAction(_Planner, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction should succeed");

        // Promote Mid so its own children can be registered under it.
        auto MidPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto MidAsPlanner = utils_goap_planner::PromoteActionToPlanner(MidAction, MidPlannerParams);
        Assert_True(ck::IsValid(MidAsPlanner), "Mid PromoteActionToPlanner should succeed");

        // LeafB makes Mid composite. Not strictly needed for the Plan/Cancel
        // semantics on Root, but mirrors the standard hierarchy.
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(MidAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction should succeed");

        // Track OnPlanComplete - must NOT fire after the cancel.
        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));

        // Wait one frame so Setup runs (the Action processor needs to see
        // the catalog + child registration before Plan requests can succeed).
        WaitOneFrame(n"OnIssuePlanThenCancel");
    }

    UFUNCTION()
    private void OnIssuePlanThenCancel(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Sanity: status is Idle (no plan started yet - _PlanOnStart=false).
        auto InitialStatus = utils_goap_planner::Get_PlanStatus(_Planner);
        Assert_True(InitialStatus == ECk_GoapPlanStatus::Idle,
            f"Root PlanStatus should be Idle before Request_Plan (got {InitialStatus})");

        // Queue Plan + Cancel in the SAME frame. Both requests are processed
        // in order by FProcessor_Goap_Action_HandleRequests on the next tick:
        // Plan seeds the search (status -> Planning, _PlanInFlight tag added);
        // Cancel immediately tears it down (status -> Idle, tag removed).
        utils_goap_planner::Request_Plan(_Planner);
        utils_goap_planner::Request_CancelPlan(_Planner);

        // Give the processor a few frames to drain requests and settle.
        _SettleFrameCount = 0;
        WaitOneFrame(n"OnSettleFrame");
    }

    UFUNCTION()
    private void OnSettleFrame(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _SettleFrameCount = _SettleFrameCount + 1;
        if (_SettleFrameCount < 5)
        {
            WaitOneFrame(n"OnSettleFrame");
            return;
        }

        // After settling: status must be Idle (cancel won), plan empty,
        // and OnPlanComplete must NOT have fired.
        auto Status = utils_goap_planner::Get_PlanStatus(_Planner);
        Assert_True(Status == ECk_GoapPlanStatus::Idle,
            f"Root PlanStatus should be Idle after Request_CancelPlan tears down the in-flight plan (got {Status})");

        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);
        Assert_True(Plan.Num() == 0,
            f"Root plan should be empty after cancel (got {Plan.Num()} entries)");

        Assert_True(_PlanCompleteFiredCount == 0,
            f"OnPlanComplete must NOT fire after Request_CancelPlan kills the in-flight search (fired {_PlanCompleteFiredCount} times)");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnPlanComplete(
        FCk_Handle_Goap_Planner InPlanner,
        FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        _PlanCompleteFiredCount = _PlanCompleteFiredCount + 1;
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_CancelInflight_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_CancelInflight;
    default _TimeoutSeconds = 15.0f;
}
