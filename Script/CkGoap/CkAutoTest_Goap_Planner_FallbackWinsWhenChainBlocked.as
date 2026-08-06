// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: FALLBACK WINS WHEN CHAIN IS STRUCTURALLY BLOCKED
//============================================================================
//
// Companion to FallbackLosesWhenChainViable. Pins the OTHER half of the
// always-valid-plan tenet (CkGoap/CLAUDE.md § "Design tenets"): the fallback
// MUST win — and the planner must reach PlanFound rather than PlanFailed —
// when no other goal-satisfier is reachable from the catalog.
//
// Catalog (flat):
//   Gated     [Action only]   pre:  Unreachable=true
//                             eff:  Goal=true               cost 1
//   Fallback  [Action only]   eff:  Goal=true               cost 999
//
// No Action in the catalog produces Unreachable=true, so Gated is
// structurally unreachable — the only viable path to Goal is via Fallback.
//
// Initial WS: Unreachable=false, Goal=false.
// Expected plan: [Fallback] (cost 999). Asserts:
//   - PlanStatus == PlanFound (NOT PlanFailed)
//   - Plan.Num() == 1
//   - Plan[0] == Fallback
//
// This test would catch a regression where the always-valid-plan tenet check
// stops working (e.g., a refactor that breaks _HasUnconditionalFallback
// detection, causing PlanFailed where Fallback should be chosen).
//============================================================================

class UCk_AutoTest_Goap_Planner_FallbackWinsWhenChainBlocked : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Planner;
    private bool _PlanAsserted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS"),
            FCk_Goap_WorldState_Spec());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Unreachable"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Goal"),
            false);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Goal"),
            true));

        auto PlannerParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(WS);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_Planner), "Planner should be valid");

        utils_goap_planner::AddAction(_Planner,
            FCk_Goap_Action_Spec(UCk_AutoTestAction_Goap_FallbackOnly_Gated));
        utils_goap_planner::AddAction(_Planner,
            FCk_Goap_Action_Spec(UCk_AutoTestAction_Goap_FallbackOnly_Fallback));

        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlan"));
    }

    UFUNCTION()
    private void OnPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanAsserted) { return; }

        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);
        if (Plan.Num() == 0) { return; }

        Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
            "PlanStatus should be PlanFound (Fallback satisfies the always-valid-plan tenet, not PlanFailed)");

        Assert_True(Plan.Num() == 1,
            f"Plan should be exactly [Fallback]. Got {Plan.Num()} entries — did Gated get picked despite the unreachable precondition?");

        if (Plan.Num() == 1)
        {
            Assert_True(Plan[0] == UCk_AutoTestAction_Goap_FallbackOnly_Fallback,
                "Plan[0] should be Fallback (the only viable goal-satisfier — Gated needs Unreachable=true which no Action produces).");
        }

        _PlanAsserted = true;
        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_FallbackWinsWhenChainBlocked_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_FallbackWinsWhenChainBlocked;
    default _TimeoutSeconds = 10.0f;
}
