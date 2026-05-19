// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: LAZY-PRUNE HANDLES MULTIPLE DEAD SUBSCRIBERS
//============================================================================
//
// SubPlannerDestroyPreservesShared validates pruning of a single dead
// subscriber. This test stresses the prune path harder: 5 subscribers,
// destroy 3 in mixed positions (head, middle, tail), then write and
// confirm the 2 surviving subscribers replan + no crash + dead entries
// have been removed.
//
//   1. Create WS + 5 planners P1..P5, all subscribed.
//   2. Wait for all initial plans.
//   3. Destroy P1 (head), P3 (middle), P5 (tail).
//   4. Issue WS write — subscriber walk encounters the 3 dead handles
//      and lazy-prunes them while still tagging P2 and P4 dirty.
//   5. Assert: P2 and P4's plan counts both advance.
//   6. Assert: a second WS write also propagates (prune state didn't
//      leave the list corrupt for subsequent writes).
//============================================================================

class UCk_AutoTest_Goap_SharedWS_SubscriberLazyPrune_HandlesMultipleDead : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _P1;
    private FCk_Handle_Goap _P2;
    private FCk_Handle_Goap _P3;
    private FCk_Handle_Goap _P4;
    private FCk_Handle_Goap _P5;

    private int32 _C2 = 0;
    private int32 _C4 = 0;
    private int32 _B2 = -1;
    private int32 _B4 = -1;
    private int32 _Phase = 0;
    private float _ElapsedInPhase = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.LazyPrune.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto P = FCk_Fragment_Goap_ParamsData();
        P.Set_PlanOnStart(true);
        P.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        P.Set_MinReplanIntervalSeconds(0.0f);
        P.Set_WorldStateSource(_WorldState);

        _P1 = utils_goap::Create(LocalHandle, planner_test_util::T(n"AutoTest.Goap.SharedWS.LazyPrune.P1"), P);
        _P1.AddAction(UCk_GoapT1_Action_CreateTool); _P1.AddGoal(UCk_GoapT1_Goal_HasTool);

        _P2 = utils_goap::Create(LocalHandle, planner_test_util::T(n"AutoTest.Goap.SharedWS.LazyPrune.P2"), P);
        _P2.AddAction(UCk_GoapT1_Action_CreateTool); _P2.AddGoal(UCk_GoapT1_Goal_HasTool);
        _P2.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnP2"));

        _P3 = utils_goap::Create(LocalHandle, planner_test_util::T(n"AutoTest.Goap.SharedWS.LazyPrune.P3"), P);
        _P3.AddAction(UCk_GoapT1_Action_CreateTool); _P3.AddGoal(UCk_GoapT1_Goal_HasTool);

        _P4 = utils_goap::Create(LocalHandle, planner_test_util::T(n"AutoTest.Goap.SharedWS.LazyPrune.P4"), P);
        _P4.AddAction(UCk_GoapT1_Action_CreateTool); _P4.AddGoal(UCk_GoapT1_Goal_HasTool);
        _P4.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnP4"));

        _P5 = utils_goap::Create(LocalHandle, planner_test_util::T(n"AutoTest.Goap.SharedWS.LazyPrune.P5"), P);
        _P5.AddAction(UCk_GoapT1_Action_CreateTool); _P5.AddGoal(UCk_GoapT1_Goal_HasTool);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION() private void OnP2(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload) { _C2 += 1; }
    UFUNCTION() private void OnP4(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload) { _C4 += 1; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedInPhase += InDeltaT.Get_Seconds();

        if (_Phase == 0)
        {
            // Wait for initial PlanOnStart fires (only counting P2 and P4).
            if (_C2 == 0 || _C4 == 0)
            {
                if (_ElapsedInPhase > 3.0f)
                { FinishFailure(f"Initial plans never settled — C2={_C2} C4={_C4}"); }
                return;
            }
            // Destroy 3 subscribers — head (P1), middle (P3), tail (P5).
            utils_entity_lifetime::Request_DestroyEntity(_P1);
            utils_entity_lifetime::Request_DestroyEntity(_P3);
            utils_entity_lifetime::Request_DestroyEntity(_P5);
            _Phase = 1;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 1)
        {
            if (_ElapsedInPhase < 0.1f) { return; }
            // Confirm destruction.
            if (ck::IsValid(_P1) || ck::IsValid(_P3) || ck::IsValid(_P5)) { return; }

            _B2 = _C2;
            _B4 = _C4;

            // First write — exercises lazy-prune across 3 dead positions
            // (head, middle, tail) and tags 2 live subscribers.
            utils_goap_world_state::Set_Value(_WorldState,
                planner_test_util::T(t1_tags::HasTool), true);
            _Phase = 2;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 2)
        {
            if (_C2 > _B2 && _C4 > _B4)
            {
                // Second write — confirms list is clean after prune (didn't
                // leave invalid handles or skip live ones).
                _B2 = _C2;
                _B4 = _C4;
                utils_goap_world_state::Set_Value(_WorldState,
                    planner_test_util::T(t1_tags::HasTool), false);
                _Phase = 3;
                _ElapsedInPhase = 0.0f;
                return;
            }
            if (_ElapsedInPhase > 2.0f)
            { FinishFailure(f"After 3 destroys + write, P2/P4 didn't replan — C2: {_B2}->{_C2} C4: {_B4}->{_C4}"); }
            return;
        }

        if (_Phase == 3)
        {
            if (_C2 > _B2 && _C4 > _B4)
            { FinishSuccess(); return; }
            if (_ElapsedInPhase > 2.0f)
            { FinishFailure(f"Second write didn't propagate post-prune — C2: {_B2}->{_C2} C4: {_B4}->{_C4}"); }
        }
    }
}
