// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: WORLDSTATE ENTITIES ARE ISOLATED
//============================================================================
//
// Two independent WorldState entities must not cross-contaminate. Writes
// to WS-A must not dirty-tag planners subscribed to WS-B, and a key with
// the same gameplay-tag name registered on both must occupy independent
// slots (no global registry).
//
//   1. Create WS-A and WS-B (distinct entities).
//   2. Create planner P_A subscribed to WS-A and planner P_B subscribed
//      to WS-B. Both PlanOnStart=true so we capture baseline plan counts.
//   3. Write a key K via the WS-A handle.
//   4. Assert: P_A's plan-count advances; P_B's does NOT.
//   5. Assert: WS-A's read for K returns true; WS-B's read for K returns
//      false (independent slots).
//============================================================================

class UCk_AutoTest_Goap_SharedWS_MultipleWorldStates_Isolated : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WS_A;
    private FCk_Handle_Goap_WorldState _WS_B;
    private FCk_Handle_Goap _P_A;
    private FCk_Handle_Goap _P_B;

    private int32 _CountA = 0;
    private int32 _CountB = 0;
    private int32 _BaselineA = -1;
    private int32 _BaselineB = -1;
    private bool  _WriteFired = false;
    private float _ElapsedInPhase = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WS_A = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Isolated.WS_A"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        _WS_B = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Isolated.WS_B"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto PA = FCk_Fragment_Goap_ParamsData();
        PA.Set_PlanOnStart(true);
        PA.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        PA.Set_MinReplanIntervalSeconds(0.0f);
        PA.Set_WorldStateSource(_WS_A);
        _P_A = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Isolated.P_A"), PA);
        _P_A.AddAction(UCk_GoapT1_Action_CreateTool);
        _P_A.AddGoal  (UCk_GoapT1_Goal_HasTool);
        _P_A.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanCompleteA"));

        auto PB = FCk_Fragment_Goap_ParamsData();
        PB.Set_PlanOnStart(true);
        PB.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        PB.Set_MinReplanIntervalSeconds(0.0f);
        PB.Set_WorldStateSource(_WS_B);
        _P_B = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Isolated.P_B"), PB);
        _P_B.AddAction(UCk_GoapT1_Action_CreateTool);
        _P_B.AddGoal  (UCk_GoapT1_Goal_HasTool);
        _P_B.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanCompleteB"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION() private void OnPlanCompleteA(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload) { _CountA += 1; }
    UFUNCTION() private void OnPlanCompleteB(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload) { _CountB += 1; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedInPhase += InDeltaT.Get_Seconds();

        if (_BaselineA < 0)
        {
            if (_CountA <= 0 || _CountB <= 0) { return; }
            _BaselineA = _CountA;
            _BaselineB = _CountB;
            return;
        }

        if (_WriteFired == false)
        {
            // Write to WS-A only.
            utils_goap_world_state::Set_Value(_WS_A,
                planner_test_util::T(t1_tags::HasTool), true);
            _WriteFired = true;
            _ElapsedInPhase = 0.0f;
            return;
        }

        // Wait for the write to land + propagate. Generous window because
        // we need to confirm P_B did NOT replan (a negative assertion).
        if (_ElapsedInPhase < 1.5f) { return; }

        // P_A should have re-planned at least once.
        Assert_True(_CountA > _BaselineA,
            f"P_A subscribed to WS-A should replan after WS-A write — baseline {_BaselineA}, current {_CountA}");
        // P_B is on WS-B and should NOT have replanned.
        Assert_Equals_Int(_CountB, _BaselineB,
            "P_B subscribed to WS-B must NOT replan when WS-A is written");

        // Key K registered on WS-A must not appear in WS-B's registry view.
        auto ReadA = utils_goap_world_state::Get_Value(_WS_A,
            planner_test_util::T(t1_tags::HasTool));
        auto ReadB = utils_goap_world_state::Get_Value(_WS_B,
            planner_test_util::T(t1_tags::HasTool));
        Assert_True(ReadA, "WS-A should read true for the key just written");
        Assert_True(ReadB == false,
            "WS-B's slot for the same gameplay tag must be independent (default false)");

        FinishSuccess();
    }
}
