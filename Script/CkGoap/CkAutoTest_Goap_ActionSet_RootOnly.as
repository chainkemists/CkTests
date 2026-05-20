// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET SMOKE — ROOT-ONLY PLAN FIRES
//============================================================================
//
// End-to-end smoke test for the unified ActionSet/Action model:
//   1. Spawn a WorldState entity, pre-register Ready=true (goal already
//      satisfied at start, so the planner returns an empty plan).
//   2. Add a Goap root container.
//   3. AddActionSet.
//   4. SetRootAction with the Simple action class as the root. Its effects
//      (Ready=true) ARE the root's goal in the unified model.
//   5. BindTo_OnPlanComplete on the root.
//
// Expected: within a couple of frames, OnPlanComplete fires.
// PlanStatus = PlanFound, plan may be empty (goal already satisfied at
// start — no operators needed).
//
// This exercises: Add, AddActionSet, SetRootAction (root entity creation,
//                 chain seeding, WS source storage), Action_Setup (CDO
//                 extraction + goal resolution + WS key registration),
//                 AutoReplan (initial-plan tag), HandleRequests (Plan
//                 build), Execute (A* search), HandleResult (path -> plan
//                 + signal), ChainUpdate (chain-state evaluation).
//============================================================================

class UCk_AutoTest_Goap_ActionSet_RootOnly : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private bool _PlanReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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

        // Goap root container.
        auto Goap = utils_goap::Add(Local, FCk_Fragment_Goap_RootParamsData());
        Assert_True(utils_goap::Has(Goap), "Has(Goap) should be true after Add");

        // ActionSet.
        auto ActionSetParams = FCk_Fragment_Goap_ActionSetParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto ActionSet = utils_goap_action_set::AddActionSet(Goap, ActionSetParams);
        Assert_True(ck::IsValid(ActionSet), "AddActionSet should return a valid handle");

        // Designate root Action. In the unified model the root's effects
        // ARE its goal — no separate Initial_Goal needed when the action's
        // own effects describe the world target.
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Simple);

        _RootAction = utils_goap_action_set::SetRootAction(ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // Active chain should contain the root immediately.
        auto Chain = utils_goap_action_set::Get_ActiveChain(ActionSet);
        Assert_True(Chain.Num() == 1,
            f"ActiveChain should contain just the root after SetRootAction (got {Chain.Num()})");

        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnPlan"));
    }

    UFUNCTION()
    private void OnPlan(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanReceived) { return; }   // first plan only
        _PlanReceived = true;

        Assert_True(utils_goap_action::Get_PlanStatus(_RootAction) == ECk_GoapPlanStatus::PlanFound,
            "Action _PlanStatus should be PlanFound");

        // Plan may be empty (goal already satisfied at start) — that's OK
        // for the smoke test. We just want to confirm OnPlanComplete fires
        // and the status is PlanFound.

        FinishSuccess();
    }
}
