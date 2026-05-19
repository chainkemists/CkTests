// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: 4-WAY SUBSCRIBER FAN-OUT
//============================================================================
//
// DirtyTriggersSibling validates fan-out with 2 subscribers. This test
// stresses the same path with 4 subscribers to catch ordering / off-by-
// one bugs in the lazy-prune loop and confirm the AddOrGet tag op
// scales linearly without misses.
//
//   1. Create one WS + 4 planners, all subscribed, OnWorldStateDirty,
//      PlanOnStart=true.
//   2. Wait for all 4 initial plans (each count >= 1). Record baselines.
//   3. Single write to WS.
//   4. Assert ALL 4 counts advance.
//============================================================================

class UCk_AutoTest_Goap_SharedWS_ThreePlusSubscribers_AllTagged : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _P1;
    private FCk_Handle_Goap _P2;
    private FCk_Handle_Goap _P3;
    private FCk_Handle_Goap _P4;

    private int32 _C1 = 0;
    private int32 _C2 = 0;
    private int32 _C3 = 0;
    private int32 _C4 = 0;
    private int32 _B1 = -1;
    private int32 _B2 = -1;
    private int32 _B3 = -1;
    private int32 _B4 = -1;
    private bool  _WriteFired = false;
    private float _ElapsedInPhase = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.FanOut.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto P = FCk_Fragment_Goap_ParamsData();
        P.Set_PlanOnStart(true);
        P.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        P.Set_MinReplanIntervalSeconds(0.0f);
        P.Set_WorldStateSource(_WorldState);

        _P1 = utils_goap::Create(LocalHandle, planner_test_util::T(n"AutoTest.Goap.SharedWS.FanOut.P1"), P);
        _P1.AddAction(UCk_GoapT1_Action_CreateTool); _P1.AddGoal(UCk_GoapT1_Goal_HasTool);
        _P1.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnP1"));

        _P2 = utils_goap::Create(LocalHandle, planner_test_util::T(n"AutoTest.Goap.SharedWS.FanOut.P2"), P);
        _P2.AddAction(UCk_GoapT1_Action_CreateTool); _P2.AddGoal(UCk_GoapT1_Goal_HasTool);
        _P2.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnP2"));

        _P3 = utils_goap::Create(LocalHandle, planner_test_util::T(n"AutoTest.Goap.SharedWS.FanOut.P3"), P);
        _P3.AddAction(UCk_GoapT1_Action_CreateTool); _P3.AddGoal(UCk_GoapT1_Goal_HasTool);
        _P3.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnP3"));

        _P4 = utils_goap::Create(LocalHandle, planner_test_util::T(n"AutoTest.Goap.SharedWS.FanOut.P4"), P);
        _P4.AddAction(UCk_GoapT1_Action_CreateTool); _P4.AddGoal(UCk_GoapT1_Goal_HasTool);
        _P4.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnP4"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION() private void OnP1(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload) { _C1 += 1; }
    UFUNCTION() private void OnP2(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload) { _C2 += 1; }
    UFUNCTION() private void OnP3(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload) { _C3 += 1; }
    UFUNCTION() private void OnP4(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload) { _C4 += 1; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedInPhase += InDeltaT.Get_Seconds();

        if (_B1 < 0)
        {
            if (_C1 == 0 || _C2 == 0 || _C3 == 0 || _C4 == 0)
            {
                if (_ElapsedInPhase > 3.0f) { FinishFailure(f"Initial plans never settled — C1={_C1} C2={_C2} C3={_C3} C4={_C4}"); }
                return;
            }
            _B1 = _C1; _B2 = _C2; _B3 = _C3; _B4 = _C4;
            return;
        }

        if (_WriteFired == false)
        {
            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), true);
            _WriteFired = true;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_C1 > _B1 && _C2 > _B2 && _C3 > _B3 && _C4 > _B4)
        {
            FinishSuccess();
            return;
        }
        if (_ElapsedInPhase > 2.0f)
        {
            FinishFailure(f"Not all 4 subscribers replanned within 2s — C1: {_B1}->{_C1} C2: {_B2}->{_C2} C3: {_B3}->{_C3} C4: {_B4}->{_C4}");
        }
    }
}
