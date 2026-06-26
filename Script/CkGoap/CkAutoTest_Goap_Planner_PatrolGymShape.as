// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PATROL GYM SHAPE REGRESSION
//============================================================================
//
// Pins the planner shape used by the Patrol gym (CkGoapGym_Patrol_Station).
// Failure mode this guards: someone re-introduces a "Root" Action whose
// effect is the planner's goal (AreaPatrolled=true) at cost 0 — that lets
// the planner trivially satisfy the goal in a single step and bypasses the
// whole [GoToWaypoint, Observe, MarkDone] chain the gym demonstrates.
//
// Shape (mirrors the gym, no actor wrapper bookkeeping):
//   Patrol_Planner          [Planner only]      goal: AreaPatrolled=true
//     GoToWaypoint          [Action+Planner]    eff:  AtWaypoint=true     cost 1
//       Run                 [Action only]       eff:  AtWaypoint=true     cost 1
//       Walk                [Action only]       eff:  AtWaypoint=true     cost 2
//     Observe               [Action+Planner]    pre:  AtWaypoint=true
//                                               eff:  AreaScanned=true    cost 1
//       LookAround          [Action only]       eff:  AreaScanned=true    cost 1
//       WaitAtPost          [Action only]       eff:  AreaScanned=true    cost 3
//     MarkDone              [Action only]       pre:  AtWaypoint=true,
//                                                     AreaScanned=true
//                                               eff:  AreaPatrolled=true  cost 1
//
// Initial WS: all false. Expected plan: [GoToWaypoint, Observe, MarkDone].
// Assert Plan.Num() >= 3 — exact-equal-3 is the canonical shape; >=3 lets
// the test survive an additional intermediate step the planner might insert
// without giving an inch on the "single-step-via-Root" regression.
//============================================================================

class UCk_AutoTest_Goap_Planner_PatrolGymShape : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _TopPlanner;
    private bool _PlanAsserted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // ---- WorldState (mirrors gym's Reset_WS — all false) ----
        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.AtWaypoint"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.AreaScanned"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.AreaPatrolled"),
            false);

        // ---- Top-level Planner: goal AreaPatrolled=true ----
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.AreaPatrolled"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Patrol"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(WS);
        // Framework test mirroring the Patrol gym's current catalog. The gym
        // itself doesn't yet include a fallback Action (separate cleanup task —
        // gyms should be audited under the always-valid-plan tenet, CkGoap/CLAUDE.md
        // § "Design tenets"). Opt-out here so the regression test runs cleanly;
        // when the Patrol gym gains a fallback (e.g. StandWatch), drop this line
        // and add the fallback Action below to mirror.
        PlannerParams.Set_AllowPlanFailed(true);
        _TopPlanner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_TopPlanner), "Top-level Planner should be valid");

        // ---- Tier-1 composite: GoToWaypoint (promoted to Planner) ----
        auto GoToWaypoint = utils_goap_planner::AddAction(_TopPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_GoToWaypoint));
        Assert_True(ck::IsValid(GoToWaypoint), "GoToWaypoint AddAction should succeed");

        auto GoToGoal = TArray<FCk_GoapWS_Condition_Authored>();
        GoToGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.AtWaypoint"),
            true));
        auto GoToPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Patrol.GoToWaypoint"));
        GoToPlannerParams.Set_Goal(GoToGoal);
        GoToPlannerParams.Set_AllowPlanFailed(true);  // framework test — see top-Planner comment
        auto GoToAsPlanner = utils_goap_planner::PromoteActionToPlanner(GoToWaypoint, GoToPlannerParams);
        Assert_True(ck::IsValid(GoToAsPlanner), "GoToWaypoint promotion should succeed");

        utils_goap_planner::AddAction(GoToAsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_Run));
        utils_goap_planner::AddAction(GoToAsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_Walk));

        // ---- Tier-1 composite: Observe (promoted to Planner) ----
        auto Observe = utils_goap_planner::AddAction(_TopPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_Observe));
        Assert_True(ck::IsValid(Observe), "Observe AddAction should succeed");

        auto ObserveGoal = TArray<FCk_GoapWS_Condition_Authored>();
        ObserveGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.AreaScanned"),
            true));
        auto ObservePlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Patrol.Observe"));
        ObservePlannerParams.Set_Goal(ObserveGoal);
        ObservePlannerParams.Set_AllowPlanFailed(true);  // framework test — see top-Planner comment
        auto ObserveAsPlanner = utils_goap_planner::PromoteActionToPlanner(Observe, ObservePlannerParams);
        Assert_True(ck::IsValid(ObserveAsPlanner), "Observe promotion should succeed");

        utils_goap_planner::AddAction(ObserveAsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_LookAround));
        utils_goap_planner::AddAction(ObserveAsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_WaitAtPost));

        // ---- Tier-1 atomic leaf: MarkDone ----
        auto MarkDone = utils_goap_planner::AddAction(_TopPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_MarkDone));
        Assert_True(ck::IsValid(MarkDone), "MarkDone AddAction should succeed");

        // ---- Bind plan-complete on top-level Planner ----
        utils_goap_planner::BindTo_OnPlanComplete(_TopPlanner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnTopPlan"));
    }

    UFUNCTION()
    private void OnTopPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanAsserted) { return; }

        auto Plan = utils_goap_planner::Get_PlanClasses(_TopPlanner);
        // Skip transient empty-plan fires during catalog warm-up.
        if (Plan.Num() == 0) { return; }

        Assert_True(utils_goap_planner::Get_PlanStatus(_TopPlanner) == ECk_GoapPlanStatus::PlanFound,
            "Top-level PlanStatus should be PlanFound");

        // The regression guard: a cost-0 Root that satisfies the goal would
        // produce Plan.Num() == 1. Anything < 3 means the multi-step chain
        // has been short-circuited.
        Assert_True(Plan.Num() >= 3,
            f"Patrol plan must have >= 3 entries [GoToWaypoint, Observe, MarkDone] (got {Plan.Num()})");

        if (Plan.Num() >= 3)
        {
            Assert_True(Plan[0] == UCk_GoapGym_Patrol_GoToWaypoint,
                "Plan[0] should be GoToWaypoint (no precondition; satisfies AtWaypoint required by Observe + MarkDone)");
            Assert_True(Plan[1] == UCk_GoapGym_Patrol_Observe,
                "Plan[1] should be Observe (satisfies AreaScanned required by MarkDone)");
            Assert_True(Plan[2] == UCk_GoapGym_Patrol_MarkDone,
                "Plan[2] should be MarkDone (only candidate whose effect is AreaPatrolled=true)");
        }

        _PlanAsserted = true;
        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_PatrolGymShape_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_PatrolGymShape;
    default _TimeoutSeconds = 15.0f;
}
