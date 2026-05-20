// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET WS DIRTY PROPAGATION
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

class UCk_AutoTest_Goap_ActionSet_DirtyPropagation : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_ActionSet _ActionSet;
    private FCk_Handle_Goap_WorldState _WS;
    private int32 _PlanCompleteCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);

        auto Goap = utils_goap::Add(Local, FCk_Fragment_Goap_RootParamsData());

        auto ActionSetParams = FCk_Fragment_Goap_ActionSetParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _ActionSet = utils_goap_action_set::AddActionSet(Goap, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        // Root goal: {AKey=true}. WS starts false → Root plans and picks LeafA.
        // Default ReplanPolicy=OnWorldStateDirty means mutating AKey will trigger
        // a replan on the next frame (via FTag_Goap_Dirty_WorldState mechanism).
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);
        RootParams.Set_InitialGoal_RootOnly(InitialGoal);

        _RootAction = utils_goap_action_set::SetRootAction(_ActionSet, RootParams, _WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // Add LeafA as a child of Root. LeafA's effect AKey=true satisfies
        // Root's goal {AKey=true}. LeafA is atomic (no children) so it won't
        // extend the active chain.
        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        auto LeafAAction = utils_goap_action::AddAction_ToAction(_RootAction, LeafAParams);
        Assert_True(ck::IsValid(LeafAAction), "LeafA AddAction_ToAction should succeed");

        // Bind OnPlanComplete on Root to count replans.
        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootPlanComplete"));
    }

    UFUNCTION()
    private void OnRootPlanComplete(
        FCk_Handle_Goap_Action InAction,
        FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        _PlanCompleteCount = _PlanCompleteCount + 1;

        if (_PlanCompleteCount == 1)
        {
            // First plan: WS has AKey=false, so Root should have picked LeafA.
            Assert_True(utils_goap_action::Get_PlanStatus(_RootAction) == ECk_GoapPlanStatus::PlanFound,
                "Root PlanStatus should be PlanFound on first plan");

            auto RootPlan = utils_goap_action::Get_Plan(_RootAction);
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

            // Poll until the second OnPlanComplete fires (up to several frames).
            WaitOneFrame(n"OnPollForSecondPlan");
            return;
        }

        if (_PlanCompleteCount == 2)
        {
            // Second plan: AKey=true, goal satisfied → empty plan (PlanFound + empty).
            Assert_True(utils_goap_action::Get_PlanStatus(_RootAction) == ECk_GoapPlanStatus::PlanFound,
                "Root PlanStatus should be PlanFound on dirty-triggered replan");

            auto RootPlan = utils_goap_action::Get_Plan(_RootAction);
            Assert_True(RootPlan.Num() == 0,
                f"Root plan should be empty after WS mutation satisfies goal (got {RootPlan.Num()})");

            FinishSuccess();
        }
    }

    // Poll if the WS dirty replan hasn't fired in the OnPlanComplete callback yet.
    UFUNCTION()
    private void OnPollForSecondPlan(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        // OnPlanComplete will call FinishSuccess once _PlanCompleteCount reaches 2.
        // If it hasn't fired yet wait another frame (bounded by _TimeoutSeconds).
        if (_PlanCompleteCount < 2)
        {
            WaitOneFrame(n"OnPollForSecondPlan");
        }
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_DirtyPropagation_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_DirtyPropagation;
    default _TimeoutSeconds = 10.0f;
}
