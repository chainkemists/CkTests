// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: REPLAN THROTTLING COALESCES BURST WRITES
//============================================================================
//
// MinReplanIntervalSeconds defines a window within which multiple dirty
// signals coalesce into a single replan. Without this property, a hot
// system writing every frame would re-plan every frame even with a
// throttle set.
//
//   1. Create WS + one planner with ReplanPolicy=OnWorldStateDirty and
//      MinReplanIntervalSeconds=1.0.
//   2. Wait for initial plan (count = 1).
//   3. Within ~0.2s real-time, write to the WS many times (>5 distinct
//      value flips). Each flip dirties the planner.
//   4. Wait through the throttle window (>1.0s elapsed since first flip).
//   5. Assert: total plan count is exactly 2 (initial + one coalesced
//      replan), NOT 5+ (one per flip) and NOT 1 (replan suppressed).
//============================================================================

class UCk_AutoTest_Goap_SharedWS_ReplanThrottling_CoalescesWrites : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _Planner;

    private int32 _Count = 0;
    private int32 _Phase = 0;
    private float _ElapsedInPhase = 0.0f;
    private int32 _WritesDone = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Throttle.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(true);
        Params.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        Params.Set_MinReplanIntervalSeconds(1.0f);
        Params.Set_WorldStateSource(_WorldState);
        _Planner = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Throttle.Planner"), Params);
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
            if (_Count < 1)
            {
                if (_ElapsedInPhase > 2.0f) { FinishFailure("Initial plan did not fire within 2s"); }
                return;
            }
            // Burst-write 6 distinct value flips on consecutive ticks.
            _Phase = 1;
            _ElapsedInPhase = 0.0f;
            _WritesDone = 0;
            return;
        }

        if (_Phase == 1)
        {
            if (_WritesDone < 6)
            {
                // Flip value back and forth so every Set is a value change.
                auto NewValue = (_WritesDone % 2) == 0;
                utils_goap_world_state::Set_Value(_WorldState,
                    planner_test_util::T(t1_tags::HasTool), NewValue);
                _WritesDone += 1;
                return;
            }
            // All bursts done; wait long enough for throttle window to elapse.
            _Phase = 2;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 2)
        {
            // Wait 1.5x the throttle window to be sure the coalesced replan fired.
            if (_ElapsedInPhase < 1.6f) { return; }
            Assert_Equals_Int(_Count, 2,
                f"6 burst writes within throttle window should coalesce to 1 replan (total count 2, got {_Count})");
            FinishSuccess();
        }
    }
}
