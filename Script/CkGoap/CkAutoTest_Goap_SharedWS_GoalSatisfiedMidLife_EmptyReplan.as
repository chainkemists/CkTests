// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: GOAL SATISFIED MID-LIFE → EMPTY REPLAN
//============================================================================
//
// Companion to PlanOnStart_ObservesSeededValues — that one tests the
// goal-satisfied case at planner construction. THIS one tests the
// transition mid-life: planner starts with an unsatisfied goal and a
// non-empty plan, then the WS gets set to satisfy the goal externally,
// then the dirty-tag triggers replan, and the new plan must be empty
// with status PlanFound (not PlanFailed).
//
//   1. Create WS with HasTool=false (default).
//   2. Create planner with goal HasTool=true, PlanOnStart=true.
//   3. First plan: 1 step (CreateTool).
//   4. Externally write HasTool=true via WS handle.
//   5. Planner replans via dirty propagation.
//   6. Second plan: empty action list. PlanFound (signal fires
//      OnPlanComplete, not OnPlanFailed).
//============================================================================

class UCk_AutoTest_Goap_SharedWS_GoalSatisfiedMidLife_EmptyReplan : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _Planner;

    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _LastPlan;
    private int32 _CompletedCount = 0;
    private int32 _FailedCount = 0;
    private int32 _Phase = 0;
    private float _ElapsedInPhase = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.GoalSatisfied.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(true);
        Params.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        Params.Set_MinReplanIntervalSeconds(0.0f);
        Params.Set_WorldStateSource(_WorldState);
        _Planner = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.GoalSatisfied.Planner"), Params);
        _Planner.AddAction(UCk_GoapT1_Action_CreateTool);
        _Planner.AddGoal  (UCk_GoapT1_Goal_HasTool);
        _Planner.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
        _Planner.BindTo_OnPlanFailed  (FCk_Delegate_Goap_OnPlanFailed  (this, n"OnPlanFailed"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
    { _LastPlan = InPayload.Get_Actions(); _CompletedCount += 1; }

    UFUNCTION() private void OnPlanFailed(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanFailed InPayload)
    { _FailedCount += 1; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedInPhase += InDeltaT.Get_Seconds();

        if (_Phase == 0)
        {
            if (_CompletedCount < 1)
            {
                if (_ElapsedInPhase > 2.0f) { FinishFailure("Initial plan did not complete within 2s"); }
                return;
            }
            Assert_Equals_Int(_LastPlan.Num(), 1, "First plan should be 1 step (CreateTool)");
            Assert_Equals_Int(_FailedCount, 0, "First plan should not fire OnPlanFailed");

            // Satisfy the goal externally.
            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), true);
            _Phase = 1;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 1)
        {
            if (_CompletedCount < 2)
            {
                if (_ElapsedInPhase > 2.0f)
                { FinishFailure(f"Second plan did not complete within 2s — Completed={_CompletedCount} Failed={_FailedCount}"); }
                return;
            }
            Assert_Equals_Int(_LastPlan.Num(), 0,
                "Replan after goal satisfied should produce empty action list");
            Assert_Equals_Int(_FailedCount, 0,
                "Goal-already-satisfied should fire OnPlanComplete, not OnPlanFailed");
            FinishSuccess();
        }
    }
}
