// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: PLANNER GET_PLAN ENTITY-HANDLE VARIANT
//============================================================================
//
// Coverage gap filler: every other Goap_Planner_* test reads the plan via
// utils_goap_planner::Get_PlanClasses (returns TArray<TSubclassOf<...>>).
// The sibling variant utils_goap_planner::Get_Plan (returns
// TArray<FCk_Handle_Goap_Action> - the actual entity handles) has had no
// dedicated regression coverage. This test exercises it on a real multi-step
// plan and cross-checks against Get_PlanClasses for consistency.
//
// Setup - a 2-step ordered plan:
//   - WS: AKey=false, BKey=false.
//   - Planner goal: {BKey=true}.
//   - Implicit root: Root_GoalIsEffects (effect AKey=true, just hosts the
//     planner - never picked as an operator since the planner's goal is BKey).
//   - MakeA (cost 1.0): effect AKey=true.
//   - MakeB (cost 1.0): precondition AKey=true, effect BKey=true.
//
// Regressive A* with goal BKey=true:
//   Goal needs BKey=true -> only MakeB has that effect.
//   MakeB needs AKey=true -> only MakeA has that effect.
//   Plan (execution order) = [MakeA, MakeB].
//
// Assertions on OnPlanComplete:
//   1. PlanStatus == PlanFound.
//   2. Get_Plan(Planner).Num() == 2.
//   3. Every handle in Get_Plan is valid (ck::IsValid).
//   4. Get_PlanClasses(Planner).Num() == Get_Plan(Planner).Num().
//   5. The class of each entity handle in Get_Plan matches the parallel slot
//      in Get_PlanClasses (cross-check). We verify by mapping each plan
//      entity handle back through utils_goap_planner::Find_ActionByClass for
//      each PlanClasses[i] and asserting the result equals Plan[i].
//============================================================================

class UCk_AutoTest_Goap_Planner_GetPlanEntities : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private bool _PlanReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            false);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(WS);
        // Framework test catalog - opt out of always-valid-plan tenet enforcement
        // (the CkGoap docs Sec. "Design tenets"). Game-content must never opt out.
        PlannerParams.Set_AllowPlanFailed(true);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // PR-B.1b Stage 5: no implicit-root Action. MakeA and MakeB are direct
        // children of the Planner. Root_GoalIsEffects (AKey effect cost 1.0)
        // would compete with MakeA so it's dropped.
        auto MakeAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_GetPlanEntities_MakeA);
        auto MakeAAction = utils_goap_planner::AddAction(_Planner, MakeAParams);
        Assert_True(ck::IsValid(MakeAAction), "AddAction (MakeA) should return a valid handle");
        _RootAction = MakeAAction;

        // MakeB - precondition AKey=true, effect BKey=true. Chains after MakeA.
        auto MakeBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_GetPlanEntities_MakeB);
        auto MakeBAction = utils_goap_planner::AddAction(_Planner, MakeBParams);
        Assert_True(ck::IsValid(MakeBAction), "AddAction (MakeB) should return a valid handle");

        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanReceived) { return; }
        _PlanReceived = true;

        Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
            "PlanStatus should be PlanFound");

        // ---- Core coverage: Get_Plan (entity-handle variant) ----
        auto PlanEntities = utils_goap_planner::Get_Plan(_Planner);
        Assert_True(PlanEntities.Num() == 2,
            f"Get_Plan should return exactly 2 entity handles (got {PlanEntities.Num()})");

        // Every returned handle must be valid.
        for (int32 i = 0; i < PlanEntities.Num(); i = i + 1)
        {
            Assert_True(ck::IsValid(PlanEntities[i]),
                f"Get_Plan entity at index {i} should be a valid handle");
        }

        // ---- Cross-check: Get_PlanClasses parallels Get_Plan slot-for-slot ----
        auto PlanClasses = utils_goap_planner::Get_PlanClasses(_Planner);
        Assert_True(PlanClasses.Num() == PlanEntities.Num(),
            f"Get_PlanClasses count ({PlanClasses.Num()}) should equal Get_Plan count ({PlanEntities.Num()})");

        // The class lookup of each Plan[i] handle should match PlanClasses[i].
        // We verify by reverse-mapping each PlanClasses[i] back to the catalog
        // entity via Find_ActionByClass and confirming it equals PlanEntities[i].
        if (PlanEntities.Num() == 2 && PlanClasses.Num() == 2)
        {
            auto EntityForClass0 = utils_goap_planner::Find_ActionByClass(_Planner, PlanClasses[0]);
            auto EntityForClass1 = utils_goap_planner::Find_ActionByClass(_Planner, PlanClasses[1]);

            Assert_True(EntityForClass0 == PlanEntities[0],
                "Plan[0]: class-lookup entity should equal Get_Plan[0] entity");
            Assert_True(EntityForClass1 == PlanEntities[1],
                "Plan[1]: class-lookup entity should equal Get_Plan[1] entity");

            // Sanity: the two slots are distinct operators of the chained plan.
            Assert_True(PlanClasses[0] == UCk_AutoTestAction_Goap_GetPlanEntities_MakeA,
                "Plan[0] class should be MakeA (first step - establishes AKey)");
            Assert_True(PlanClasses[1] == UCk_AutoTestAction_Goap_GetPlanEntities_MakeB,
                "Plan[1] class should be MakeB (second step - needs AKey, sets BKey)");
        }

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_GetPlanEntities_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_GetPlanEntities;
    default _TimeoutSeconds = 15.0f;
}
