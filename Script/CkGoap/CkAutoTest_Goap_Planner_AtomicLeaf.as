// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET ATOMIC LEAF CHAIN STABILITY
//============================================================================
//
// Validates: when the planner selects an atomic child (no registered
// grandchildren), ChainUpdate does NOT extend the active chain past Root.
//
// Setup:
//   - WS: Ready=false.
//   - Root action: effect Ready=true. _InitialGoal_RootOnly={Ready=true}.
//   - AtomicChild action: effect Ready=true, no grandchildren.
//   - Root child = AtomicChild.
//
// Expected (asserted after WaitOneFrame so ChainUpdate has run):
//   - Get_PlanStatus(Root) == PlanFound
//   - Get_Plan(Root)[0] == UCk_AutoTestAction_Goap_ActionSet_AtomicChild
//   - Get_ActiveChain(ActionSet).Num() == 1  (Root only — AtomicChild is
//     atomic, so ChainUpdate does NOT append it)
//============================================================================

class UCk_AutoTest_Goap_Planner_AtomicLeaf : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _ActionSet;
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

        // U11.1: goal authored on PlannerParams (was: ActionParams._InitialGoal_RootOnly).
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        ActionSetParams.Set_WorldStateSource(WS);
        _ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "Add Planner should return a valid handle");

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_AtomicLeaf);

        _RootAction = utils_goap_planner::AddAction(_ActionSet, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (implicit-root) should return a valid handle");

        // Add AtomicChild as a child of Root. No grandchildren added — atomic.
        auto ChildParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_AtomicChild);
        auto ChildAction = utils_goap_planner::AddAction(_ActionSet, ChildParams);
        Assert_True(ck::IsValid(ChildAction), "AddAction (subsequent → tree child of implicit root) should return a valid handle");

        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanReceived) { return; }
        _PlanReceived = true;

        Assert_True(utils_goap_planner::Get_PlanStatus(_ActionSet) == ECk_GoapPlanStatus::PlanFound,
            "Root PlanStatus should be PlanFound");

        auto Plan = utils_goap_planner::Get_PlanClasses(_ActionSet);
        Assert_True(Plan.Num() == 1,
            f"Root plan should have exactly 1 entry (got {Plan.Num()})");
        Assert_True(Plan.Num() > 0 && Plan[0] == UCk_AutoTestAction_Goap_ActionSet_AtomicChild,
            "Root Plan[0] should be AtomicChild");

        // Wait one frame so ChainUpdate has had a chance to run and decide
        // whether to extend the chain. A correctly-behaving system will NOT
        // append AtomicChild (no children registered on it).
        WaitOneFrame(n"OnSettled_AfterChainUpdate");
    }

    UFUNCTION()
    private void OnSettled_AfterChainUpdate(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"ActiveChain should remain at length 1 (Root only) after ChainUpdate — AtomicChild must NOT be appended (got {Chain.Num()})");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_AtomicLeaf_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_AtomicLeaf;
}
