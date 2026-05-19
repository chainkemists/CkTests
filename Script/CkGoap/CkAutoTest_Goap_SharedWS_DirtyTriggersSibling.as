// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: SHARED-WS DIRTY TRIGGERS SIBLING REPLAN
//============================================================================
//
// Verifies the signal-driven dirty propagation that makes HGOAP work:
// when one observer mutates the shared WorldState, every planner pointing
// at that WorldState picks up the dirty tag and re-plans on its next
// AutoReplan tick.
//
//   1. Create one WorldState entity.
//   2. Create planner A and planner B, both with _WorldStateSource = WS,
//      ReplanPolicy = OnWorldStateDirty, PlanOnStart = true. Bind each
//      planner's OnPlanComplete to a local counter.
//   3. Wait for the initial plan on both — record baselines.
//   4. Mutate the shared WS via the WS handle.
//   5. Assert BOTH counters increment — confirming the WS-side
//      subscriber walk tagged both planners dirty and AutoReplan fired.
//============================================================================

class UCk_AutoTest_Goap_SharedWS_DirtyTriggersSibling : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _PlannerA;
    private FCk_Handle_Goap _PlannerB;

    private int32 _CountA = 0;
    private int32 _CountB = 0;
    private int32 _BaselineA = -1;
    private int32 _BaselineB = -1;
    private bool  _WriteFired = false;
    private float _TicksSinceWrite = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Dirty.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(true);
        Params.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        Params.Set_MinReplanIntervalSeconds(0.0f);
        Params.Set_WorldStateSource(_WorldState);

        _PlannerA = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Dirty.A"), Params);
        _PlannerA.AddAction(UCk_GoapT1_Action_CreateTool);
        _PlannerA.AddGoal(UCk_GoapT1_Goal_HasTool);
        _PlannerA.BindTo_OnPlanComplete(
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanCompleteA"));

        _PlannerB = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Dirty.B"), Params);
        _PlannerB.AddAction(UCk_GoapT1_Action_CreateTool);
        _PlannerB.AddGoal(UCk_GoapT1_Goal_HasTool);
        _PlannerB.BindTo_OnPlanComplete(
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanCompleteB"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnPlanCompleteA(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
    { _CountA += 1; }

    UFUNCTION()
    private void OnPlanCompleteB(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
    { _CountB += 1; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Phase 1 — wait for both initial plans to complete.
        if (_BaselineA < 0)
        {
            if (_CountA <= 0 || _CountB <= 0) { return; }
            _BaselineA = _CountA;
            _BaselineB = _CountB;
            return;
        }

        // Phase 2 — write to shared WS and wait for both planners to react.
        if (_WriteFired == false)
        {
            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), true);
            _WriteFired = true;
            _TicksSinceWrite = 0.0f;
            return;
        }

        _TicksSinceWrite += InDeltaT.Get_Seconds();

        if (_CountA > _BaselineA && _CountB > _BaselineB)
        {
            FinishSuccess();
            return;
        }

        if (_TicksSinceWrite > 2.0f)
        {
            FinishFailure(f"Sibling replan did not fire within 2s — A: {_BaselineA}->{_CountA}, B: {_BaselineB}->{_CountB}");
        }
    }
}
