// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: STRICT DEPENDENCY CHAIN
//============================================================================
//
// Verifies the planner emits actions in the correct dependency order:
//   1. Add four T2 actions (DoStep1 .. DoStepFinal) where each subsequent
//      action requires the previous step's flag as a precondition.
//   2. Add the StepFinal goal.
//   3. Plan completes with exactly 4 actions in order
//      Step1 -> Step2 -> Step3 -> StepFinal.
//
// Reuses the gym's T2 action/goal classes from CkGoap_PlannerTests.as.
//
// EXPECTED FAILURE — see CkAutoTest_Goap_BasicPlan.as for the canonical
// explanation. Plan returns empty (Plan.Num()==0) despite the planner
// running cleanly. Same suspected root cause as Goap_BasicPlan; both
// will pass automatically once the underlying lifecycle issue is fixed.
//============================================================================

class UCk_AutoTest_Goap_DependencyChain : UCk_AutoTest_Base
{
    private FCk_Handle_Goap _Goap;
    private FCk_Handle_Goap_WorldState _WorldState;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // Gym pattern: transform fragment exists on owner before Goap is added.
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_worldstate::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.DependencyChain.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto GoapParams = FCk_Fragment_Goap_ParamsData();
        GoapParams.Set_PlanOnStart(false);
        GoapParams.Set_WorldStateSource(_WorldState);
        _Goap = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.DependencyChain"), GoapParams);

        _Goap.AddAction(UCk_GoapT2_Action_DoStep1);
        _Goap.AddAction(UCk_GoapT2_Action_DoStep2);
        _Goap.AddAction(UCk_GoapT2_Action_DoStep3);
        _Goap.AddAction(UCk_GoapT2_Action_DoStepFinal);
        _Goap.AddGoal(UCk_GoapT2_Goal_StepFinal);

        _Goap.BindTo_OnPlanComplete(
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
        _Goap.BindTo_OnPlanFailed(
            FCk_Delegate_Goap_OnPlanFailed(this, n"OnPlanFailed"));

        // Defer Request_Plan by a tick — see Goap_BasicPlan for rationale.
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
        Assert_Equals_Int(Plan.Num(), 4,
            "4-step dependency chain should yield a 4-action plan");

        if (Plan.Num() == 4)
        {
            Assert_True(Plan[0] == UCk_GoapT2_Action_DoStep1,
                "Plan[0] should be DoStep1");
            Assert_True(Plan[1] == UCk_GoapT2_Action_DoStep2,
                "Plan[1] should be DoStep2");
            Assert_True(Plan[2] == UCk_GoapT2_Action_DoStep3,
                "Plan[2] should be DoStep3");
            Assert_True(Plan[3] == UCk_GoapT2_Action_DoStepFinal,
                "Plan[3] should be DoStepFinal");
        }

        FinishSuccess();
    }

    UFUNCTION()
    private void OnPlanFailed(
        FCk_Handle_Goap InHandle,
        FCk_Goap_Payload_OnPlanFailed InPayload)
    {
        if (IsFinished()) { return; }
        FinishFailure("Planner returned PlanFailed for a satisfiable dependency chain");
    }
}
