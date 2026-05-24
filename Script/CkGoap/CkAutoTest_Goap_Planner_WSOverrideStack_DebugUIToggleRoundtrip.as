// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: WORLDSTATE OVERRIDE STACK — DEBUG UI TOGGLE ROUND-TRIP
//============================================================================
//
// Regression test for the CkGoapDebugger WorldStateRail toggle path. The rail
// click handler captures the current effective WS value at row-build time,
// then on click pushes !current into a layer named "DebugUI" via
// Push_Override_SingleKey. Clicking again pushes the negation again — which,
// per the override stack's idempotent same-name-layer-update-in-place semantics,
// flips the effective view back.
//
// This test simulates the same sequence at the API level so a regression in
// Push_Override_SingleKey / Get_Value (the two endpoints the rail depends on)
// would fail loudly even if the Slate UI itself isn't covered by automation.
//
// Phase A — base WS: KeyA=true. Get_Value(KeyA) should return true.
//           Has_KeyOverride(KeyA) should be false. Depth should be 0.
// Phase B — Push_Override_SingleKey("DebugUI", KeyA, !true) → false.
//           Get_Value(KeyA) should now return false. Depth=1. Has_KeyOverride=true.
// Phase C — Push_Override_SingleKey("DebugUI", KeyA, !false) → true.
//           Get_Value(KeyA) should now return true. Depth still 1 (same layer
//           updated in place, not stacked).
// Phase D — Push_Override_SingleKey("DebugUI", KeyA, !true) → false.
//           Get_Value(KeyA) should return false again. Depth still 1.
//
// Setup: minimal Planner+OpA scaffolding (reused from BasicPushPop) so KeyA
// is registered in the WS key registry. Without an Action referencing KeyA in
// its preconditions/effects, the registry is sealed at Setup with no entry for
// KeyA, and Set_Value silently no-ops. Assertions therefore live in the
// OnPlanComplete callback (which fires after Setup).
//============================================================================

class UCk_AutoTest_Goap_Planner_WSOverrideStack_DebugUIToggleRoundtrip : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_WorldState _WS;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        // Pre-set base values. These are silent no-ops until Setup runs and
        // registers the keys via the Action references below; re-set in
        // OnRootPlan after Setup.
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyA"),
            true);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.Goal"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.Planner"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(_WS);
        // Framework test catalog — opt out of always-valid-plan tenet enforcement
        // (CkGoap/CLAUDE.md § "Design tenets"). Game-content must never opt out.
        PlannerParams.Set_AllowPlanFailed(true);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // OpA registers KeyA (precondition) + Goal (effect) in the WS registry
        // at Setup. After Setup, Set_Value/Get_Value on KeyA take effect.
        auto OpAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_WSOverrideStack_OpA);
        auto OpA = utils_goap_planner::AddAction(_Planner, OpAParams);
        Assert_True(ck::IsValid(OpA), "AddAction (OpA) should return a valid handle");

        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        auto KeyA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyA");

        // Setup has now registered KeyA. Re-assert the base value (the
        // DoBeginPlay Set was a silent no-op pre-Setup; Set it again here so
        // we test the actual round-trip from a known base state).
        utils_goap_world_state::Set_Value(_WS, KeyA, true);

        // --- Phase A — base view -----------------------------------------
        auto BaseValue = utils_goap_world_state::Get_Value(_WS, KeyA);
        Assert_True(BaseValue == true,
            f"Phase A: base Get_Value(KeyA) should be true (got {BaseValue})");
        Assert_True(utils_goap_world_state::Has_KeyOverride(_WS, KeyA) == false,
            "Phase A: Has_KeyOverride should be false before any push");
        Assert_True(utils_goap_world_state::Get_OverrideDepth(_WS) == 0,
            "Phase A: depth should be 0 before any push");

        // --- Phase B — first toggle: push !current (true → false) --------
        utils_goap_world_state::Push_Override_SingleKey(_WS, n"DebugUI",
            KeyA, !BaseValue);

        auto PhaseBValue = utils_goap_world_state::Get_Value(_WS, KeyA);
        Assert_True(PhaseBValue == false,
            f"Phase B: Get_Value(KeyA) should be false after pushing !true (got {PhaseBValue})");
        Assert_True(utils_goap_world_state::Has_KeyOverride(_WS, KeyA),
            "Phase B: Has_KeyOverride should be true after first push");
        Assert_True(utils_goap_world_state::Get_OverrideDepth(_WS) == 1,
            f"Phase B: depth should be 1 after first push (got {utils_goap_world_state::Get_OverrideDepth(_WS)})");

        // --- Phase C — second toggle: push !current (false → true) -------
        utils_goap_world_state::Push_Override_SingleKey(_WS, n"DebugUI",
            KeyA, !PhaseBValue);

        auto PhaseCValue = utils_goap_world_state::Get_Value(_WS, KeyA);
        Assert_True(PhaseCValue == true,
            f"Phase C: Get_Value(KeyA) should be true after pushing !false (got {PhaseCValue})");
        Assert_True(utils_goap_world_state::Has_KeyOverride(_WS, KeyA),
            "Phase C: Has_KeyOverride should remain true (same layer, updated in place)");
        Assert_True(utils_goap_world_state::Get_OverrideDepth(_WS) == 1,
            "Phase C: depth should still be 1 (single DebugUI layer, updated in place)");

        // --- Phase D — third toggle: push !current (true → false) --------
        utils_goap_world_state::Push_Override_SingleKey(_WS, n"DebugUI",
            KeyA, !PhaseCValue);

        auto PhaseDValue = utils_goap_world_state::Get_Value(_WS, KeyA);
        Assert_True(PhaseDValue == false,
            f"Phase D: Get_Value(KeyA) should be false after pushing !true (got {PhaseDValue})");
        Assert_True(utils_goap_world_state::Get_OverrideDepth(_WS) == 1,
            "Phase D: depth should still be 1");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR
//============================================================================

class ACk_AutoTest_Goap_Planner_WSOverrideStack_DebugUIToggleRoundtrip_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_WSOverrideStack_DebugUIToggleRoundtrip;
    default _TimeoutSeconds = 15.0f;
}
