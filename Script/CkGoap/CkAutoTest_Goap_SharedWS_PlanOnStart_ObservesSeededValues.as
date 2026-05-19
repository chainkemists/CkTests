// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLAN-ON-START OBSERVES PRE-SEEDED WS
//============================================================================
//
// HGOAP setup pattern: create the shared WS, seed values that establish
// the initial world state, THEN create planners with PlanOnStart=true.
// The first plan must reflect the seeded state, not a fresh-all-false WS.
//
//   1. Create WS.
//   2. Seed the goal key (HasTool) to TRUE before any planner exists.
//   3. Create a planner with goal HasTool=true and PlanOnStart=true.
//   4. Assert: first plan completes with ZERO actions (goal is already
//      satisfied at first-plan time).
//
// If the planner re-reads its own snapshot at construction time instead
// of resolving fresh from the shared WS, this would fail with a 1-step
// plan (CreateTool).
//============================================================================

class UCk_AutoTest_Goap_SharedWS_PlanOnStart_ObservesSeededValues : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _Planner;

    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _FirstPlan;
    private bool _PlanCompleted = false;
    private bool _PlanFailed    = false;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Seeded.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        // Seed BEFORE the planner exists. The planner's first plan must
        // observe this value via the shared WS source.
        utils_goap_world_state::Set_Value(_WorldState,
            planner_test_util::T(t1_tags::HasTool), true);

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(true);
        Params.Set_WorldStateSource(_WorldState);
        _Planner = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Seeded.Planner"), Params);
        _Planner.AddAction(UCk_GoapT1_Action_CreateTool);
        _Planner.AddGoal  (UCk_GoapT1_Goal_HasTool);
        _Planner.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
        _Planner.BindTo_OnPlanFailed  (FCk_Delegate_Goap_OnPlanFailed  (this, n"OnPlanFailed"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
    { _FirstPlan = InPayload.Get_Actions(); _PlanCompleted = true; }

    UFUNCTION() private void OnPlanFailed(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanFailed InPayload)
    { _PlanFailed = true; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _Elapsed += InDeltaT.Get_Seconds();

        if (_PlanFailed)
        { FinishFailure("First plan returned PlanFailed despite seeded WS satisfying goal"); return; }

        if (_PlanCompleted == false)
        {
            if (_Elapsed > 2.0f)
            { FinishFailure("First plan did not complete within 2s"); }
            return;
        }

        Assert_Equals_Int(_FirstPlan.Num(), 0,
            "First plan should be empty — goal HasTool=true is already satisfied by seeded WS");
        FinishSuccess();
    }
}
