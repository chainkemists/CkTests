// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: FALLBACK LOSES WHEN A VIABLE CHAIN EXISTS
//============================================================================
//
// Pins the always-valid-plan tenet's cost-ordering guarantee documented in
// CkGoap/CLAUDE.md § "Design tenets": "Fallback cost picks itself. Any cost
// much higher than the cheapest real Action wins automatically when no other
// plan is viable."
//
// Catalog (flat — no sub-Planners, deliberately minimal):
//   Setup     [Action only]   eff:  MidStep=true            cost 1
//   Finalize  [Action only]   pre:  MidStep=true
//                             eff:  Goal=true               cost 1
//   Fallback  [Action only]   eff:  Goal=true               cost 999
//
// Initial WS: MidStep=false, Goal=false.
// Expected plan: [Setup, Finalize] (total cost 2). Asserts:
//   - PlanStatus == PlanFound
//   - Plan.Num() == 2
//   - Plan[0] == Setup, Plan[1] == Finalize
// The Fallback (cost 999) must NOT appear in the plan — that's the regression
// guard for "fallback would win a goal-satisfier race despite higher cost".
//
// This test exists because the gym-audit work surfaced a question: do
// gym-shape tests need _AllowPlanFailed=true plus no fallback in catalog, or
// can they include the fallback and trust A* min-cost? The answer is "trust
// A*" — but only when this test passes. If this test fails, the framework's
// A* / GOAP integration has a min-cost ordering bug that needs a fix.
//============================================================================

class UCk_AutoTest_Goap_Planner_FallbackLosesWhenChainViable : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Planner;
    private bool _PlanAsserted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.MidStep"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.Goal"),
            false);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.Goal"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(WS);
        // Fallback present in catalog; tenet check should pass without an
        // opt-out. If it doesn't, the framework's Setup-time static check
        // would fire CK_ENSURE_IF_NOT before the planner ever produces a plan.
        _Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_Planner), "Planner should be valid");

        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackVsChain_Setup));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackVsChain_Finalize));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackVsChain_Fallback));

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
            "PlanStatus should be PlanFound");

        Assert_True(Plan.Num() == 2,
            f"Plan should be the [Setup, Finalize] chain (2 entries). Got {Plan.Num()} entries — Fallback may have won despite higher cost.");

        if (Plan.Num() == 2)
        {
            Assert_True(Plan[0] == UCk_AutoTestAction_Goap_FallbackVsChain_Setup,
                "Plan[0] should be Setup (no preconditions; satisfies MidStep required by Finalize)");
            Assert_True(Plan[1] == UCk_AutoTestAction_Goap_FallbackVsChain_Finalize,
                "Plan[1] should be Finalize (only candidate whose effect is Goal=true at cost < 999)");
        }

        // Hard guard against the symptom this test exists to catch: if the
        // Fallback appears anywhere in the plan, the framework returned a
        // non-min-cost path.
        for (auto Idx = 0; Idx < Plan.Num(); Idx = Idx + 1)
        {
            Assert_True(Plan[Idx] != UCk_AutoTestAction_Goap_FallbackVsChain_Fallback,
                f"Fallback (cost 999) must not appear in the chosen plan when the [Setup, Finalize] chain (cost 2) is viable. Plan[{Idx}] is Fallback.");
        }

        _PlanAsserted = true;
        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_FallbackLosesWhenChainViable_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_FallbackLosesWhenChainViable;
    default _TimeoutSeconds = 10.0f;
}
