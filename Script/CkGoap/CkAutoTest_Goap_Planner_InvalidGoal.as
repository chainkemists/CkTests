// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET INVALID GOAL DIAGNOSTIC
//============================================================================
//
// Validates: when Request_SetGoalWorldState is called with a goal condition
// that references a tag NOT registered in the Action's resolved WS registry,
// that condition lands in Get_InvalidGoal(Action).
//
// How _InvalidGoal is populated:
//   FProcessor_Goap_Action_HandleRequests processes FCk_Request_Goap_Action_SetGoal.
//   For each authored condition in the request, it calls Registry.Find(tag). If
//   the tag is not registered (it was never added via any action's preconditions
//   or effects), the condition is added to _Current._InvalidGoal.
//
// Setup:
//   - WS: Ready=false (only Ready is registered by Root's CDO effects).
//   - No _InitialGoal_RootOnly set — root gets empty goal → PlanFound immediately.
//   - Request_SetGoalWorldState([{UnknownKey=true}]) is queued in DoBeginPlay.
//     UnknownKey is NOT referenced by any action's CDO, so Setup will never
//     register it in the WS key registry. HandleRequests processes SetGoal,
//     fails to find UnknownKey, adds it to _InvalidGoal.
//   - Bind OnPlanComplete — fires after HandleRequests processes both
//     SetGoal and the initial Plan request (empty goal → PlanFound).
//
// Expected: Get_InvalidGoal(Root).Num() == 1 in OnPlanComplete.
//============================================================================

class UCk_AutoTest_Goap_Planner_InvalidGoal : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private bool _PlanReceived = false;

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

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(ActionSet), "AddActionSet should return a valid handle");

        // Root with no _InitialGoal_RootOnly — empty goal, PlanFound immediately.
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_InvalidGoal);
        _RootAction = utils_goap_planner::SetRootAction(ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // Issue SetGoalWorldState with a tag that is NOT registered in the WS
        // key registry. Only Ready is registered (via Root's CDO effect).
        // UnknownKey never appears in any action CDO, so Setup will never
        // register it. HandleRequests cannot find it → _InvalidGoal populated.
        auto GoalConditions = TArray<FCk_GoapWS_Condition_Authored>();
        GoalConditions.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.UnknownKey"),
            true));
        utils_goap_action::Request_SetGoalWorldState(_RootAction, GoalConditions);

        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnPlan"));
    }

    UFUNCTION()
    private void OnPlan(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanReceived) { return; }
        _PlanReceived = true;

        // The SetGoalWorldState request was processed before the Plan request
        // (FIFO queue, SetGoal was enqueued in DoBeginPlay). SetGoal set
        // _InvalidGoal = [{UnknownKey, true}] and _Goal = []. Plan then ran
        // on the empty goal → PlanFound with empty plan. _InvalidGoal persists.
        Assert_True(utils_goap_action::Get_PlanStatus(_RootAction) == ECk_GoapPlanStatus::PlanFound,
            "Root PlanStatus should be PlanFound (empty goal satisfied immediately)");

        auto InvalidGoal = utils_goap_action::Get_InvalidGoal(_RootAction);
        Assert_True(InvalidGoal.Num() == 1,
            f"Get_InvalidGoal should contain 1 entry for the unregistered UnknownKey (got {InvalidGoal.Num()})");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_InvalidGoal_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_InvalidGoal;
}
