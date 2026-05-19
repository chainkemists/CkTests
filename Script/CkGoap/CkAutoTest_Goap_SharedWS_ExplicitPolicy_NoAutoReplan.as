// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: EXPLICIT REPLAN POLICY IGNORES DIRTY TAGS
//============================================================================
//
// A planner with ReplanPolicy = Explicit subscribes to the shared WS like
// every other planner, gets dirty-tagged when the WS changes, but its
// AutoReplan must NOT enqueue a Plan request. The only way to trigger
// re-planning on an Explicit planner is an explicit Request_Plan call.
//
//   1. Create WS + planner with Explicit policy + PlanOnStart=true.
//   2. Wait for the initial plan (count = 1).
//   3. Write to shared WS via the WS handle. Wait several ticks.
//   4. Assert: count is still 1 — no auto-replan fired.
//   5. Call Request_Plan explicitly. Wait.
//   6. Assert: count advances to 2 — explicit request works as expected.
//============================================================================

class UCk_AutoTest_Goap_SharedWS_ExplicitPolicy_NoAutoReplan : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _Planner;

    private int32 _Count = 0;
    private int32 _Phase = 0;
    private float _ElapsedInPhase = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Explicit.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(true);
        Params.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::Explicit);
        Params.Set_MinReplanIntervalSeconds(0.0f);
        Params.Set_WorldStateSource(_WorldState);
        _Planner = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Explicit.Planner"), Params);
        _Planner.AddAction(UCk_GoapT1_Action_CreateTool);
        _Planner.AddGoal  (UCk_GoapT1_Goal_HasTool);
        _Planner.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
    { _Count += 1; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedInPhase += InDeltaT.Get_Seconds();

        if (_Phase == 0)
        {
            // Wait for initial plan.
            if (_Count < 1)
            {
                if (_ElapsedInPhase > 2.0f) { FinishFailure("Initial plan did not fire within 2s"); }
                return;
            }
            Assert_Equals_Int(_Count, 1, "Initial PlanOnStart should fire exactly once");

            // Write to shared WS — should dirty-tag the planner but NOT cause replan.
            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), true);
            _Phase = 1;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 1)
        {
            // Wait long enough for any auto-replan to have fired.
            if (_ElapsedInPhase < 1.5f) { return; }
            Assert_Equals_Int(_Count, 1,
                f"Explicit policy must not auto-replan on WS dirty — count expected 1, got {_Count}");

            // Now explicitly request a plan.
            _Planner.Request_Plan();
            _Phase = 2;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 2)
        {
            if (_Count < 2)
            {
                if (_ElapsedInPhase > 2.0f) { FinishFailure("Explicit Request_Plan did not fire within 2s"); }
                return;
            }
            Assert_Equals_Int(_Count, 2, "Explicit Request_Plan should fire exactly one additional plan");
            FinishSuccess();
        }
    }
}
