// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: COST-DIRTY AND WS-DIRTY UNDER OnEitherDirty
//============================================================================
//
// AutoReplan's policy OnEitherDirty fires when either FTag_Goap_Dirty_Cost
// or FTag_Goap_Dirty_WorldState is present. Both tags can be raised in
// the same frame (cost edit + WS write). After AutoReplan fires, BOTH
// dirty tags must be cleared so subsequent writes can be detected again.
//
//   1. Create WS + planner, OnEitherDirty, MinReplanIntervalSeconds=0.
//   2. Wait for initial plan.
//   3. Same tick: utils_goap::Set_ActionCost(...) + utils_goap_world_state::Set_Value(...).
//   4. Assert: ONE replan fires (count=2), not two.
//   5. Wait briefly, then write to WS again.
//   6. Assert: another replan fires (count=3) — confirms tags were cleared
//      after the previous AutoReplan pass.
//============================================================================

class UCk_AutoTest_Goap_SharedWS_CostDirtyAndWsDirty_OnEitherDirty : UCk_AutoTest_Base
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
            planner_test_util::T(n"AutoTest.Goap.SharedWS.EitherDirty.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(true);
        Params.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnEitherDirty);
        Params.Set_MinReplanIntervalSeconds(0.0f);
        Params.Set_WorldStateSource(_WorldState);
        _Planner = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.EitherDirty.Planner"), Params);
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
            // Same-tick burst: cost change + WS write.
            _Planner.Set_ActionCost(UCk_GoapT1_Action_CreateTool, 3.0f);
            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), true);
            _Phase = 1;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 1)
        {
            // Wait for the coalesced replan.
            if (_Count < 2)
            {
                if (_ElapsedInPhase > 2.0f) { FinishFailure("Same-tick cost+WS dirty did not produce a replan"); }
                return;
            }
            Assert_Equals_Int(_Count, 2, "Same-tick cost+WS burst should produce exactly one replan (count=2)");

            // Now write again (after a few ticks) to confirm tags were cleared.
            _Phase = 2;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 2)
        {
            if (_ElapsedInPhase < 0.2f) { return; }
            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), false);
            _Phase = 3;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 3)
        {
            if (_Count < 3)
            {
                if (_ElapsedInPhase > 2.0f)
                { FinishFailure(f"Subsequent WS write did not trigger replan — count {_Count}, expected 3"); }
                return;
            }
            Assert_Equals_Int(_Count, 3, "Subsequent WS write should trigger one more replan (count=3)");
            FinishSuccess();
        }
    }
}
