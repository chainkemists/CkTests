// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: OWNER CASCADE DESTROY TAKES WS + PLANNERS
//============================================================================
//
// Destroying the owner entity must cascade-destroy its WorldState and
// every planner subscribed to that WS (via CkRecord). This validates:
//   1. No crashes / no ensure failures during cascade.
//   2. WS subscriber walk on in-flight writes copes with destroyed
//      subscriber handles (lazy-prune path).
//   3. After cascade, all handles report invalid.
//
// Scenario:
//   1. Create a CHILD owner entity (so destroying it doesn't take the
//      test runner down).
//   2. Under that child owner: WS + 2 planners pointing at it.
//   3. PlanOnStart=true so request queues are non-empty when destroyed.
//   4. Destroy the child owner.
//   5. Wait one tick — cascade completes.
//   6. Assert: owner, WS, and both planners are all invalid handles.
//============================================================================

class UCk_AutoTest_Goap_SharedWS_OwnerCascadeDestroy_DoesNotCrash : UCk_AutoTest_Base
{
    private FCk_Handle _ChildOwner;
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _PlannerA;
    private FCk_Handle_Goap _PlannerB;

    private int32 _Phase = 0;
    private float _ElapsedInPhase = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Spawn a transient child entity to act as the HGOAP owner — this
        // is the one we'll destroy, not the test-runner entity.
        _ChildOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_transform::Add(_ChildOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(_ChildOwner,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.OwnerDestroy.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(true);
        Params.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        Params.Set_MinReplanIntervalSeconds(0.0f);
        Params.Set_WorldStateSource(_WorldState);

        _PlannerA = utils_goap::Create(_ChildOwner,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.OwnerDestroy.A"), Params);
        _PlannerA.AddAction(UCk_GoapT1_Action_CreateTool);
        _PlannerA.AddGoal  (UCk_GoapT1_Goal_HasTool);

        _PlannerB = utils_goap::Create(_ChildOwner,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.OwnerDestroy.B"), Params);
        _PlannerB.AddAction(UCk_GoapT1_Action_CreateTool);
        _PlannerB.AddGoal  (UCk_GoapT1_Goal_HasTool);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedInPhase += InDeltaT.Get_Seconds();

        if (_Phase == 0)
        {
            // Let one tick pass so initial PlanOnStart work + WS request queue
            // are mid-flight when we destroy.
            if (_ElapsedInPhase < 0.1f) { return; }
            utils_entity_lifetime::Request_DestroyEntity(_ChildOwner);
            _Phase = 1;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 1)
        {
            // Give cascade a few ticks to fully process.
            if (_ElapsedInPhase < 0.3f) { return; }
            Assert_True(ck::Is_NOT_Valid(_ChildOwner),
                "Child owner should be destroyed after cascade");
            Assert_True(ck::Is_NOT_Valid(_WorldState),
                "WorldState should be cascade-destroyed with its owner");
            Assert_True(ck::Is_NOT_Valid(_PlannerA),
                "PlannerA should be cascade-destroyed with its owner");
            Assert_True(ck::Is_NOT_Valid(_PlannerB),
                "PlannerB should be cascade-destroyed with its owner");
            FinishSuccess();
        }
    }
}
