// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: SHARED WORLDSTATE BASICS
//============================================================================
//
// Verifies the foundational HGOAP property: two planners that share a
// single WorldState entity observe each other's writes.
//
//   1. Create one WorldState entity.
//   2. Create planner A and planner B, both with _WorldStateSource = WS.
//      Give each one trivial action/goal so Setup wires up cleanly.
//   3. Write a key via the WS handle directly.
//   4. Read the same key back via the WS handle — asserting that the
//      WS-handle read returns the value just written.
//   5. Read the key via utils_goap::Get_WorldStateSource(plannerB) too
//      to assert that both planners' Params point at the same WS entity.
//
// Single-tick observation is enough since the Set request lands in the
// WS request queue and is drained by FProcessor_Goap_WorldState_HandleRequests
// before the next tick.
//============================================================================

class UCk_AutoTest_Goap_SharedWS_Basic : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _PlannerA;
    private FCk_Handle_Goap _PlannerB;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Basic.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(false);
        Params.Set_WorldStateSource(_WorldState);

        _PlannerA = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Basic.A"), Params);
        _PlannerA.AddAction(UCk_GoapT1_Action_CreateTool);
        _PlannerA.AddGoal(UCk_GoapT1_Goal_HasTool);

        _PlannerB = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Basic.B"), Params);
        _PlannerB.AddAction(UCk_GoapT1_Action_CreateTool);
        _PlannerB.AddGoal(UCk_GoapT1_Goal_HasTool);

        // Defer the assertion by one tick so the Set request lands in WS
        // and the request processor drains it. Single tick is sufficient.
        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private bool _WriteDone = false;

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_WriteDone == false)
        {
            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), true);
            _WriteDone = true;
            return;
        }

        auto SourceFromA = utils_goap::Get_WorldStateSource(_PlannerA);
        auto SourceFromB = utils_goap::Get_WorldStateSource(_PlannerB);

        Assert_True(SourceFromA == _WorldState,
            "PlannerA's source should be the WS entity");
        Assert_True(SourceFromB == _WorldState,
            "PlannerB's source should be the WS entity");

        auto ReadFromWS = utils_goap_world_state::Get_Value(_WorldState,
            planner_test_util::T(t1_tags::HasTool));
        Assert_True(ReadFromWS,
            "WS-handle read should observe the Set");

        auto ReadViaA = utils_goap_world_state::Get_Value(SourceFromA,
            planner_test_util::T(t1_tags::HasTool));
        auto ReadViaB = utils_goap_world_state::Get_Value(SourceFromB,
            planner_test_util::T(t1_tags::HasTool));
        Assert_True(ReadViaA == ReadViaB,
            "Both planners' WS reads should agree");
        Assert_True(ReadViaA,
            "PlannerA-side read should observe the Set written via the WS handle");

        FinishSuccess();
    }
}
