// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLAN REQUEST ON DANGLING WS FAILS GRACEFULLY
//============================================================================
//
// If a WorldState entity is destroyed while a planner still references it,
// the planner's source handle becomes invalid. The planner's Plan request
// handler must detect this and fire OnPlanFailed cleanly — not crash, not
// silently no-op, not retry forever.
//
//   1. Create WS + planner with PlanOnStart=false (avoid stale initial
//      plan racing the destroy).
//   2. Destroy WS via utils_entity_lifetime::Request_DestroyEntity.
//   3. Wait one tick.
//   4. Call Request_Plan on the planner.
//   5. Assert: OnPlanFailed fires within a reasonable window.
//   6. Assert: no crash / no OnPlanComplete.
//============================================================================

class UCk_AutoTest_Goap_SharedWS_WorldStateDestroyed_PlanFailsGracefully : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _Planner;

    private int32 _Completed = 0;
    private int32 _Failed = 0;
    private int32 _Phase = 0;
    private float _ElapsedInPhase = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.WSDestroyed.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(false);
        Params.Set_WorldStateSource(_WorldState);
        _Planner = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.WSDestroyed.Planner"), Params);
        _Planner.AddAction(UCk_GoapT1_Action_CreateTool);
        _Planner.AddGoal  (UCk_GoapT1_Goal_HasTool);
        _Planner.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
        _Planner.BindTo_OnPlanFailed  (FCk_Delegate_Goap_OnPlanFailed  (this, n"OnPlanFailed"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION() private void OnPlanComplete(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
    { _Completed += 1; }
    UFUNCTION() private void OnPlanFailed(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanFailed InPayload)
    { _Failed += 1; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedInPhase += InDeltaT.Get_Seconds();

        if (_Phase == 0)
        {
            utils_entity_lifetime::Request_DestroyEntity(_WorldState);
            _Phase = 1;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 1)
        {
            // Wait for destruction to complete.
            if (_ElapsedInPhase < 0.1f) { return; }
            // Confirm WS is gone before issuing the Plan request.
            if (ck::IsValid(_WorldState))
            { return; }

            _Planner.Request_Plan();
            _Phase = 2;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 2)
        {
            if (_Failed >= 1)
            {
                Assert_Equals_Int(_Completed, 0,
                    "OnPlanComplete must NOT fire when WS source is invalid");
                FinishSuccess();
                return;
            }
            if (_ElapsedInPhase > 2.0f)
            { FinishFailure(f"Plan request with dangling WS did not fire OnPlanFailed within 2s — Completed={_Completed} Failed={_Failed}"); }
        }
    }
}
