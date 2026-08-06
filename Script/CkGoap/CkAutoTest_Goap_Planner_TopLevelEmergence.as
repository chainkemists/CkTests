// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER TOP-LEVEL EMERGENCE
//============================================================================
//
// Validates: top-level Planner identification is runtime-observable, not
// declared. A Planner is "top-level" when its root Action has no active
// parent — i.e. Get_ActiveParentAction on the root Action returns null.
//
// Setup:
//   - Single owner entity.
//   - Two independent top-level Planners on the owner:
//       Planner_A: tag AutoTest.Goap.ActionSet.Set,  WS pre-seeded AKey=true.
//       Planner_B: tag AutoTest.Goap.ActionSet.Set2, WS pre-seeded BKey=true.
//   - Each Planner gets its own AddAction call with a distinct Action class.
//   - Both Planners have pre-satisfied goals → empty plans → PlanFound.
//
// Assertions (driven by OnPlanComplete on each root):
//   1. Both roots produce PlanFound.
//   2. Get_ActiveParentAction(RootA) == nullptr  → top-level (no parent class).
//   3. Get_ActiveParentAction(RootB) == nullptr  → top-level (no parent class).
//   4. Root handles are distinct (separate Planner entities).
//
// After both roots plan:
//   5. FinishSuccess.
//
// This exercises: Add (two independent Planners), AddAction, OnPlanComplete
//                 (parallel independent ticking), and the observable top-level
//                 identity invariant (Get_ActiveParentAction == nullptr on roots).
//============================================================================

class UCk_AutoTest_Goap_Planner_TopLevelEmergence : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_Goap_Action _RootA;
    private FCk_Handle_Goap_Action _RootB;
    private FCk_Handle_Goap_Planner _PlannerA;
    private FCk_Handle_Goap_Planner _PlannerB;
    private bool _PlanAReceived = false;
    private bool _PlanBReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Shared WorldState entity. Pre-satisfy both keys so both planners
        // produce PlanFound immediately (empty plan).
        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Goap_WorldState_Spec());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true);

        // ---- Planner A ---- goal {AKey=true}, pre-satisfied.
        auto GoalA = TArray<FCk_GoapWS_Condition_Authored>();
        GoalA.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));

        auto PlannerParamsA = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        PlannerParamsA.Set_Goal(GoalA);
        PlannerParamsA.Set_WorldStateSource(WS);
        // Two top-level Planners under one owner → Create (named child Planners);
        // Add stamps onto Local directly and rejects the second call.
        _PlannerA = utils_goap_planner::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"),
            PlannerParamsA);
        Assert_True(ck::IsValid(_PlannerA), "Planner A Create should return a valid handle");

        auto RootParamsA = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_ActionSet_Root_MultiA);
        _RootA = utils_goap_planner::AddAction(_PlannerA, RootParamsA);
        Assert_True(ck::IsValid(_RootA), "AddAction A should return a valid handle");

        // ---- Planner B ---- goal {BKey=true}, pre-satisfied.
        auto GoalB = TArray<FCk_GoapWS_Condition_Authored>();
        GoalB.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto PlannerParamsB = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set2"));
        PlannerParamsB.Set_Goal(GoalB);
        PlannerParamsB.Set_WorldStateSource(WS);
        _PlannerB = utils_goap_planner::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set2"),
            PlannerParamsB);
        Assert_True(ck::IsValid(_PlannerB), "Planner B Create should return a valid handle");

        auto RootParamsB = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_ActionSet_Root_MultiB);
        _RootB = utils_goap_planner::AddAction(_PlannerB, RootParamsB);
        Assert_True(ck::IsValid(_RootB), "AddAction B should return a valid handle");

        // The two roots must be distinct handles (different Planner entities).
        Assert_True(!(_RootA == _RootB),
            "Root A and Root B must be distinct Action handles (different Planner entities)");

        // Top-level identity assertion: immediately after AddAction, before
        // any plan runs, Get_ActiveParentAction returns null on both roots.
        // This is the invariant: root Actions of top-level Planners have no parent.
        auto ParentA = utils_goap_action::Get_ActiveParentAction(_RootA);
        Assert_True(ParentA == nullptr,
            "RootA's Get_ActiveParentAction must be null — it is a top-level Planner root");

        auto ParentB = utils_goap_action::Get_ActiveParentAction(_RootB);
        Assert_True(ParentB == nullptr,
            "RootB's Get_ActiveParentAction must be null — it is a top-level Planner root");

        // Bind OnPlanComplete on both roots to confirm independent ticking.
        utils_goap_planner::BindTo_OnPlanComplete(_PlannerA,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanA"));
        utils_goap_planner::BindTo_OnPlanComplete(_PlannerB,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanB"));
    }

    UFUNCTION()
    private void OnPlanA(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanAReceived) { return; }
        _PlanAReceived = true;

        Assert_True(utils_goap_planner::Get_PlanStatus(_PlannerA) == ECk_GoapPlanStatus::PlanFound,
            "Planner A root PlanStatus should be PlanFound");

        // Verify top-level identity is still observable after planning.
        auto ParentA = utils_goap_action::Get_ActiveParentAction(_RootA);
        Assert_True(ParentA == nullptr,
            "RootA's Get_ActiveParentAction must still be null after PlanFound — top-level identity is stable");

        TryFinish();
    }

    UFUNCTION()
    private void OnPlanB(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanBReceived) { return; }
        _PlanBReceived = true;

        Assert_True(utils_goap_planner::Get_PlanStatus(_PlannerB) == ECk_GoapPlanStatus::PlanFound,
            "Planner B root PlanStatus should be PlanFound");

        // Verify top-level identity is still observable after planning.
        auto ParentB = utils_goap_action::Get_ActiveParentAction(_RootB);
        Assert_True(ParentB == nullptr,
            "RootB's Get_ActiveParentAction must still be null after PlanFound — top-level identity is stable");

        TryFinish();
    }

    private void TryFinish()
    {
        if (!_PlanAReceived || !_PlanBReceived) { return; }

        // Both planners found their plans independently.
        // Final cross-check: handles still valid and still distinct.
        Assert_True(ck::IsValid(_RootA), "RootA must still be valid after both plans fired");
        Assert_True(ck::IsValid(_RootB), "RootB must still be valid after both plans fired");
        Assert_True(!(_RootA == _RootB), "RootA and RootB must remain distinct handles");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_TopLevelEmergence_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_TopLevelEmergence;
    default _TimeoutSeconds = 15.0f;
}
