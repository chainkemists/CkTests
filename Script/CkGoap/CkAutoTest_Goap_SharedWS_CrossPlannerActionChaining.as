// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: CROSS-PLANNER ACTION CHAINING VIA SHARED WS
//============================================================================
//
// The core HGOAP value-add: a state change produced by planner A's action
// must let planner B (sharing the same WorldState) succeed at a plan whose
// precondition depends on that state.
//
//   1. Planner A: action that effects K1=true. Goal: K1=true.
//   2. Planner B: action requires K1=true, effects K2=true. Goal: K2=true.
//   3. Initial WS: K1=false, K2=false.
//   4. Both planners PlanOnStart=true.
//      → Planner A's first plan: 1 step (the K1-producing action).
//      → Planner B's first plan: PlanFailed (precondition K1 unsatisfied).
//   5. Simulate A's action firing by writing K1=true via the WS handle.
//   6. B is dirty-tagged + re-plans.
//      → B's new plan: 1 step (its K2-producing action).
//
// This proves that effects applied to the shared WS by one observer
// propagate into another observer's plan composition — not just into
// its read-back of values, but into the actions it picks.
//============================================================================

namespace cross_chain_tags
{
    const FName K1 = n"AutoTest.Goap.SharedWS.Chain.K1";
    const FName K2 = n"AutoTest.Goap.SharedWS.Chain.K2";
}

class UCk_GoapChain_ActionA : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride) void DoDefineAction()
    {
        AddEffect(GameplayTags::ResolveGameplayTag(cross_chain_tags::K1), true);
        SetCost(1.0f);
    }
};

class UCk_GoapChain_ActionB : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride) void DoDefineAction()
    {
        AddPrecondition(GameplayTags::ResolveGameplayTag(cross_chain_tags::K1), true);
        AddEffect      (GameplayTags::ResolveGameplayTag(cross_chain_tags::K2), true);
        SetCost(1.0f);
    }
};

class UCk_GoapChain_GoalA : UCk_GoapGoal_EntityScript
{
    UFUNCTION(BlueprintOverride) void DoDefineGoal()
    { AddCondition(GameplayTags::ResolveGameplayTag(cross_chain_tags::K1), true); SetPriority(1); }
};

class UCk_GoapChain_GoalB : UCk_GoapGoal_EntityScript
{
    UFUNCTION(BlueprintOverride) void DoDefineGoal()
    { AddCondition(GameplayTags::ResolveGameplayTag(cross_chain_tags::K2), true); SetPriority(1); }
};

class UCk_AutoTest_Goap_SharedWS_CrossPlannerActionChaining : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _WorldState;
    private FCk_Handle_Goap _PlannerA;
    private FCk_Handle_Goap _PlannerB;

    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _PlanA;
    private bool  _PlanAComplete = false;
    private bool  _BInitialFailed = false;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _PlanB_AfterChain;
    private bool  _PlanBAfterChainComplete = false;

    private int32 _Phase = 0;
    private float _ElapsedInPhase = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WorldState = utils_goap_world_state::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Chain.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto Params = FCk_Fragment_Goap_ParamsData();
        Params.Set_PlanOnStart(true);
        Params.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        Params.Set_MinReplanIntervalSeconds(0.0f);
        Params.Set_WorldStateSource(_WorldState);

        _PlannerA = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Chain.A"), Params);
        _PlannerA.AddAction(UCk_GoapChain_ActionA);
        _PlannerA.AddGoal(UCk_GoapChain_GoalA);
        _PlannerA.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanCompleteA"));

        _PlannerB = utils_goap::Create(LocalHandle,
            planner_test_util::T(n"AutoTest.Goap.SharedWS.Chain.B"), Params);
        _PlannerB.AddAction(UCk_GoapChain_ActionB);
        _PlannerB.AddGoal(UCk_GoapChain_GoalB);
        _PlannerB.BindTo_OnPlanComplete(FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanCompleteB"));
        _PlannerB.BindTo_OnPlanFailed  (FCk_Delegate_Goap_OnPlanFailed  (this, n"OnPlanFailedB"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnPlanCompleteA(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
    { _PlanA = InPayload.Get_Actions(); _PlanAComplete = true; }

    UFUNCTION()
    private void OnPlanCompleteB(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (_BInitialFailed) { _PlanB_AfterChain = InPayload.Get_Actions(); _PlanBAfterChainComplete = true; }
    }

    UFUNCTION()
    private void OnPlanFailedB(FCk_Handle_Goap InHandle, FCk_Goap_Payload_OnPlanFailed InPayload)
    { if (_BInitialFailed == false) { _BInitialFailed = true; } }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedInPhase += InDeltaT.Get_Seconds();

        if (_Phase == 0)
        {
            // Wait for A's initial plan + B's initial PlanFailed.
            if (_PlanAComplete == false || _BInitialFailed == false)
            {
                if (_ElapsedInPhase > 2.0f)
                { FinishFailure(f"Initial plans did not settle in 2s — AComplete={_PlanAComplete} BFailed={_BInitialFailed}"); }
                return;
            }
            Assert_Equals_Int(_PlanA.Num(), 1, "A's initial plan should contain one action (ActionA)");
            if (_PlanA.Num() == 1)
            { Assert_True(_PlanA[0] == UCk_GoapChain_ActionA, "A's initial plan should be ActionA"); }

            // Simulate A's action firing — apply its effect to the shared WS.
            utils_goap_world_state::Set_Value(_WorldState,
                GameplayTags::ResolveGameplayTag(cross_chain_tags::K1), true);
            _Phase = 1;
            _ElapsedInPhase = 0.0f;
            return;
        }

        if (_Phase == 1)
        {
            // Wait for B to re-plan via dirty-tag propagation. New plan must
            // succeed and contain ActionB.
            if (_PlanBAfterChainComplete == false)
            {
                if (_ElapsedInPhase > 2.0f)
                { FinishFailure("B did not re-plan within 2s after K1 was set via shared WS"); }
                return;
            }
            Assert_Equals_Int(_PlanB_AfterChain.Num(), 1, "B's chained plan should contain one action (ActionB)");
            if (_PlanB_AfterChain.Num() == 1)
            { Assert_True(_PlanB_AfterChain[0] == UCk_GoapChain_ActionB, "B's chained plan should be ActionB"); }
            FinishSuccess();
        }
    }
}
