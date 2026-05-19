// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: SUB-PLANNER DESTRUCTION PRESERVES SHARED WS
//============================================================================
//
// Verifies the lifetime decoupling of the HGOAP topology: a sub-planner's
// destruction leaves the shared WorldState (and other planners pointing
// at it) intact.
//
//   1. Create one WorldState entity.
//   2. Create planner A (parent) and planner B (sub), both pointing at WS.
//      Bind A's OnPlanComplete to a counter so we can detect replans.
//   3. Write a key via the WS handle; confirm the value lands.
//   4. Destroy planner B via utils_entity_lifetime::Request_DestroyEntity.
//   5. Wait one tick for the destroy.
//   6. Assert WS still valid + value preserved + planner A still valid.
//   7. Write a second value via the WS handle.
//   8. Assert planner A's counter advanced — proving the subscriber
//      list's lazy-prune cleaned up the dead B without dropping A.
//============================================================================

class UCk_AutoTest_Goap_SharedWS_SubPlannerDestroyPreservesShared : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _PlannerA;
    private FCk_Handle_Goap _PlannerB;

    private int32 _Phase = 0;
    private int32 _CountA = 0;
    private int32 _BaselineA = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.SubDestroy.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(true);
        Params.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        Params.Set_MinReplanIntervalSeconds(0.0f);
        Params.Set_WorldStateSource(_WorldState);

        _PlannerA = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.SubDestroy.A"), Params);
        _PlannerA.AddAction(UCk_GoapT1_Action_CreateTool);
        _PlannerA.AddGoal(UCk_GoapT1_Goal_HasTool);
        _PlannerA.BindTo_OnPlanComplete(
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanCompleteA"));

        _PlannerB = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.SubDestroy.B"), Params);
        _PlannerB.AddAction(UCk_GoapT1_Action_CreateTool);
        _PlannerB.AddGoal(UCk_GoapT1_Goal_HasTool);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnPlanCompleteA(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
    { _CountA += 1; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_Phase == 0)
        {
            // Wait for at least one plan-complete on A so the initial planner
            // pass is stable before we start mutating state.
            if (_CountA <= 0) { return; }

            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), true);
            _Phase = 1;
            return;
        }

        if (_Phase == 1)
        {
            auto Seeded = utils_goap_world_state::Get_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool));
            if (Seeded == false) { return; }

            utils_entity_lifetime::Request_DestroyEntity(_PlannerB);
            _BaselineA = _CountA;
            _Phase = 2;
            return;
        }

        if (_Phase == 2)
        {
            Assert_True(ck::IsValid(_WorldState),
                "Shared WorldState should survive sub-planner destruction");
            auto Value = utils_goap_world_state::Get_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool));
            Assert_True(Value,
                "Shared WS value should be preserved across sub-planner destruction");
            Assert_True(ck::IsValid(_PlannerA),
                "Parent planner should still be valid");

            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), false);
            _Phase = 3;
            return;
        }

        if (_Phase == 3)
        {
            if (_CountA <= _BaselineA) { return; }
            FinishSuccess();
        }
    }
}
