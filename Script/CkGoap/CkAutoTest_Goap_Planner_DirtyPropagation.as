// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER WS DIRTY PROPAGATION
//============================================================================
//
// Validates §9 row 9: "WS change → subscribed Actions replan; non-subscribed
// Actions don't."
//
// Setup:
//   - WS: AKey=false.
//   - Root action (Root_GoalIsEffects): _InitialGoal_RootOnly={AKey=true},
//     default ReplanPolicy=OnWorldStateDirty.
//   - LeafA (child of Root): effect AKey=true. Atomic (no children).
//   - WS starts at AKey=false → Root plans → plan=[LeafA]. OnPlanComplete
//     fires (count=1).
//
// Phase 1: Wait for Root's initial plan. Assert count==1 and plan contains
//   LeafA.
//
// Phase 2: Mutate WS — Set AKey=true. Root's goal {AKey=true} is now
//   satisfied. AutoReplan (dirty) fires a new plan request. The new plan is
//   empty (goal already satisfied). OnPlanComplete fires again (count=2).
//
// Assert: count==2, confirming that the WS dirty subscription triggered a
//   replan. Only Root is subscribed to this WS, so no other Action replans.
//============================================================================

class UCk_AutoTest_Goap_Planner_DirtyPropagation : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_WorldState _WS;
    private int32 _PlanCompleteCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);

        // Root goal: {AKey=true}. WS starts false → Root plans and picks LeafA.
        // Default ReplanPolicy=OnWorldStateDirty means mutating AKey will trigger
        // a replan on the next frame (via FTag_Goap_Dirty_WorldState mechanism).
        // U11.1: goal authored on PlannerParams.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        ActionSetParams.Set_WorldStateSource(_WS);
        _Planner = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // PR-B.1b Stage 5: LeafA is registered directly under the Planner. No
        // implicit-root Action. LeafA's effect AKey=true satisfies the goal.
        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        _RootAction = utils_goap_planner::AddAction(_Planner, LeafAParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (LeafA) should return a valid handle");

        // Bind OnPlanComplete on Root to count replans.
        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnRootPlanComplete"));
    }

    UFUNCTION()
    private void OnRootPlanComplete(
        FCk_Handle_Goap_Planner InPlanner,
        FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        _PlanCompleteCount = _PlanCompleteCount + 1;

        // Phase 2 is judged by the wait continuation below, not here, so there is
        // exactly one path to a verdict.
        if (_PlanCompleteCount == 1)
        {
            // First plan: WS has AKey=false, so Root should have picked LeafA.
            Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
                "Root PlanStatus should be PlanFound on first plan");

            auto RootPlan = utils_goap_planner::Get_PlanClasses(_Planner);
            Assert_True(RootPlan.Num() == 1,
                f"Root plan should have exactly 1 entry on first plan (got {RootPlan.Num()})");
            Assert_True(RootPlan.Num() > 0 && RootPlan[0] == UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects,
                "Root Plan[0] should be LeafA (AKey=true effect)");

            // Now mutate WS: AKey=true. Goal is now satisfied. The WS processor
            // will add FTag_Goap_Dirty_WorldState to Root (a subscriber), and
            // AutoReplan will enqueue a new plan request on the next frame.
            utils_goap_world_state::Set_Value(_WS,
                utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
                true);

            WaitUntil(n"Check_DirtyReplanFired", n"OnSecondPlanArrived");
        }
    }

    // The dirty-triggered replan arriving IS the settling event. Waiting on it
    // names the condition if it never fires; the previous unbounded re-arming
    // poll simply ran out the engine TimeLimit and surfaced as an anonymous
    // TimesUp that said nothing about what the test was waiting for.
    UFUNCTION()
    private void Check_DirtyReplanFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PlanCompleteCount >= 2);
    }

    UFUNCTION()
    private void OnSecondPlanArrived(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Second plan: AKey=true, goal satisfied → empty plan (PlanFound + empty).
        Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
            "Root PlanStatus should be PlanFound on dirty-triggered replan");

        auto RootPlan = utils_goap_planner::Get_PlanClasses(_Planner);
        Assert_True(RootPlan.Num() == 0,
            f"Root plan should be empty after WS mutation satisfies goal (got {RootPlan.Num()})");
        Assert_Equals_Int(_PlanCompleteCount, 2,
            "The WS dirty subscription should trigger exactly one replan");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_DirtyPropagation_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_DirtyPropagation;
    default _TimeoutSeconds = 10.0f;
}
