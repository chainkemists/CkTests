// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET DEPENDENCY CYCLE DETECTION
//============================================================================
//
// Validates utils_goap_action_set::Get_DependencyCycles(ActionSet).
//
// Per spec §7.1-7.2: Setup runs an iterative Tarjan SCC over the catalog's
// _ChildActions edges. Any non-trivial SCC (size > 1, or size 1 with a
// self-loop) is recorded in FFragment_Goap_ActionSet_Current._DependencyCycles
// as a diagnostic and surfaces here via Get_DependencyCycles. The planner
// does not refuse cyclic catalogs — the diagnostic is informational.
//
// LIMITATION:
//   Constructing a true cycle through the public API in v1 is unreachable
//   through normal usage because:
//     - DoCreateOrFindActionEntity dedupes by action class — a class
//       registered twice returns the existing handle (and emits a Warning).
//     - AddAction_ToAction enforces a strict tree invariant: a child Action
//       cannot be re-parented once it has a parent (CK_ENSURE_IF_NOT on
//       _ParentAction validity).
//   The only path that could form a cycle is calling AddAction_ToAction with
//   a NewChildClass whose existing entity has no parent yet (e.g. the Root
//   action, which has no _ParentAction). That would reparent the Root and
//   create a Root→Mid→Root cycle — but doing so produces a Warning that the
//   AutoTest harness escalates to test failure (per feedback_autotest_
//   warning_escalation), so we cannot exercise that path in a test.
//
// This test therefore validates the INVARIANT side of cycle detection:
// for a well-formed tree (Root → Mid → LeafB, Root → MidB → LeafA), the
// Setup processor's Tarjan SCC pass must report zero cycles. The verb is
// confirmed bound, callable, and returns the expected empty diagnostic list.
//
// Setup:
//   - WS: AKey=false, BKey=false.
//   - Root + Mid (composite, child=LeafB) — a valid 3-deep tree.
//   - Wait for Root.PlanComplete so we know Setup has run on every Action
//     in the catalog (a precondition for ActionSet Setup to populate
//     _DependencyCycles per CkGoap_ActionSet_Processor.cpp ForEachEntity).
//
// Assertions:
//   - Get_DependencyCycles(ActionSet).Num() == 0  (no cycles in valid tree).
//   - FinishSuccess.
//============================================================================

class UCk_AutoTest_Goap_ActionSet_DependencyCycleDetection : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_ActionSet _ActionSet;
    private FCk_Handle_Goap_Action _RootAction;
    private bool _RootPlanReceived = false;

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

        auto Goap = utils_goap::Add(Local, FCk_Fragment_Goap_RootParamsData());

        auto ActionSetParams = FCk_Fragment_Goap_ActionSetParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _ActionSet = utils_goap_action_set::AddActionSet(Goap, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        // Well-formed tree: Root → Mid → LeafB. No cycles by construction.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);
        RootParams.Set_InitialGoal_RootOnly(InitialGoal);

        _RootAction = utils_goap_action_set::SetRootAction(_ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        auto MidAction = utils_goap_action::AddAction_ToAction(_RootAction, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction_ToAction should succeed");

        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_action::AddAction_ToAction(MidAction, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction_ToAction should succeed");

        // Wait for Root to plan — confirms every catalog Action has completed
        // Setup, which in turn means FProcessor_Goap_ActionSet_Setup has run
        // (it defers until all Actions are set up). Only then is the cycle
        // diagnostic finalized.
        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(
        FCk_Handle_Goap_Action InAction,
        FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_RootPlanReceived) { return; }
        _RootPlanReceived = true;

        // Wait one more frame to ensure the ActionSet Setup processor has
        // run after the last Action's Setup completed (per the deferred
        // setup loop in FProcessor_Goap_ActionSet_Setup::ForEachEntity).
        WaitOneFrame(n"OnVerifyNoCycles");
    }

    UFUNCTION()
    private void OnVerifyNoCycles(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Cycles = utils_goap_action_set::Get_DependencyCycles(_ActionSet);
        Assert_True(Cycles.Num() == 0,
            f"Get_DependencyCycles must return an empty list for a well-formed tree (got {Cycles.Num()} cycles)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_DependencyCycleDetection_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_DependencyCycleDetection;
    default _TimeoutSeconds = 15.0f;
}
