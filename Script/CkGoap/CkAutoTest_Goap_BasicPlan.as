// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: BASIC SINGLE-ACTION PLAN
//============================================================================
//
// Smoke test for the classical-boolean GOAP planner:
//   1. Add a Goap entity (PlanOnStart=false).
//   2. Add the gym's UCk_GoapT1_Action_CreateTool action and
//      UCk_GoapT1_Goal_HasTool goal.
//   3. Set world state HasTool=false (the goal is "HasTool=true").
//   4. Bind OnPlanComplete and Request_Plan.
//   5. Plan completes with exactly 1 action: CreateTool.
//
// Reuses the gym's T1 action/goal classes from CkGoap_PlannerTests.as so
// the planner is exercised against a known-good action graph rather than
// a test-only one.
//
//============================================================================
// EXPECTED FAILURE — needs framework investigation
//============================================================================
//
// Symptom: OnPlanComplete fires successfully (planner ran cleanly), but
// the returned plan is empty (Plan.Num() == 0) instead of containing the
// expected single action. Identical action/goal/world-state setup runs
// in the gym's PlannerT1 station produces a populated plan.
//
// Things tried that did NOT fix it:
//   1. Tick-deferring Request_Plan (in case AddAction is async-deferred).
//   2. Adding the same gameplay-label between utils_goap::Add and
//      AddAction that the gym does.
//   3. Adding a transform fragment to the owner before utils_goap::Add
//      (matching the gym's first DoConstruct line).
//
// Suspected cause: gym station does setup in DoConstruct, this test
// uses DoBeginPlay. Some part of the Goap Add/AddAction registration
// pipeline is sensitive to that timing — possibly the action class CDOs
// need to be touched during the DoConstruct window for AS to register
// them. Override of DoConstruct in the AutoTest base would require
// duplicating UCk_AutoTest_Base's body (no super in AS).
//
// When fixed: this test should pass automatically with no test-side
// changes. The Goap_DependencyChain test has the same root cause and
// will turn green at the same time.
//============================================================================

class UCk_AutoTest_Goap_BasicPlan : UCk_AutoTest_Base
{
    private FCk_Handle_Goap _Goap;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // Gym pattern: transform fragment exists on owner before Goap is added.
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GoapParams = FCk_Fragment_Goap_ParamsData();
        GoapParams.Set_PlanOnStart(false);
        _Goap = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.BasicPlan"), GoapParams);

        _Goap.AddAction(UCk_GoapT1_Action_CreateTool);
        _Goap.AddGoal(UCk_GoapT1_Goal_HasTool);
        utils_goap::Set_WorldStateValue(
            _Goap, planner_test_util::T(t1_tags::HasTool), false);

        _Goap.BindTo_OnPlanComplete(
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
        _Goap.BindTo_OnPlanFailed(
            FCk_Delegate_Goap_OnPlanFailed(this, n"OnPlanFailed"));

        // Defer Request_Plan by a tick so AddAction/AddGoal request
        // processors run first — without this, the planner sees an empty
        // action set and returns PlanFailed. The gym does its setup in
        // DoConstruct (which apparently lets actions register before the
        // first planner pass), but in DoBeginPlay we need the explicit delay.
        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private bool _PlanRequested = false;

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_PlanRequested) { return; }
        _PlanRequested = true;
        _Goap.Request_Plan();
    }

    UFUNCTION()
    private void OnPlanComplete(
        FCk_Handle_Goap InHandle,
        FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        auto Plan = InPayload.Get_Actions();
        Assert_Equals_Int(Plan.Num(), 1,
            "Single-action goal should yield a 1-step plan");
        Assert_True(planner_test_util::ContainsAction(Plan, UCk_GoapT1_Action_CreateTool),
            "Plan should contain CreateTool action");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnPlanFailed(
        FCk_Handle_Goap InHandle,
        FCk_Goap_Payload_OnPlanFailed InPayload)
    {
        if (IsFinished()) { return; }
        FinishFailure("Planner returned PlanFailed for a satisfiable goal");
    }
}
