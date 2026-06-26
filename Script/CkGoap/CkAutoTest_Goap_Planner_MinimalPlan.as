// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER SMOKE — ROOT-ONLY PLAN FIRES
//============================================================================
//
// End-to-end smoke test for the unified Planner/Action model:
//   1. Spawn a WorldState entity, pre-register Ready=true (goal already
//      satisfied at start, so the planner returns an empty plan).
//   2. Add a Goap root container.
//   3. AddActionSet.
//   4. AddAction with the Simple action class — first call becomes implicit root.
//      Its effects (Ready=true) ARE the root's goal in the unified model.
//   5. BindTo_OnPlanComplete on the root.
//
// Expected: within a couple of frames, OnPlanComplete fires.
// PlanStatus = PlanFound, plan may be empty (goal already satisfied at
// start — no operators needed).
//
// This exercises: Add, AddAction (implicit-root entity creation,
//                 chain seeding, WS source resolution), Action_Setup (CDO
//                 extraction + goal resolution + WS key registration),
//                 AutoReplan (initial-plan tag), HandleRequests (Plan
//                 build), Execute (A* search), HandleResult (path -> plan
//                 + signal), ChainUpdate (chain-state evaluation).
//============================================================================

class UCk_AutoTest_Goap_Planner_MinimalPlan : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private bool _PlanReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // World state — pre-register Ready and set it to TRUE so the goal
        // is already satisfied at planning time.
        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            true);

        // Top-level Planner.
        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_WorldStateSource(WS);
        _Planner = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // First AddAction = implicit root Action. In the unified model the
        // root's effects ARE its goal when the Planner's _Goal is empty —
        // no separate Initial_Goal needed when the action's own effects
        // describe the world target.
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Simple);

        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction should return a valid handle");

        // PR-B.1b Stage 5: the implicit-root chain assertion is gone. Before any
        // plan runs Get_ActiveChain returns empty — the test now verifies the
        // post-plan signal flow instead.

        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlan"));
    }

    UFUNCTION()
    private void OnPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanReceived) { return; }   // first plan only
        _PlanReceived = true;

        Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
            "Action _PlanStatus should be PlanFound");

        // Plan may be empty (goal already satisfied at start) — that's OK
        // for the smoke test. We just want to confirm OnPlanComplete fires
        // and the status is PlanFound.

        FinishSuccess();
    }
}
