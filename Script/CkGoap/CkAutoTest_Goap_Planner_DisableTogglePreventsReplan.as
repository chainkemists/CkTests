// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: DISABLE TOGGLE PREVENTS REPLAN (PR-B.1b Stage 1)
//============================================================================
//
// Validates spec §3.3 ("Disabled Planners don't replan and don't activate
// their children.") and CTO finding A4. Before PR-B.1b Stage 1, only
// FProcessor_Goap_Planner_UpdateActivation gated on EnableToggle — the A*
// pipeline on the Action side (Setup, AutoReplan, HandleRequests, Execute,
// HandleResult) ran unconditionally, burning CPU on disabled Planners and
// silently broadcasting OnPlanComplete signals that activation then ignored.
//
// Setup:
//   - WS: AKey=false.
//   - Top-level Planner with goal {AKey=true}, ReplanPolicy=OnWorldStateDirty.
//   - Root (implicit-root Action via first AddAction): no children of its own
//     that contribute; planner's candidates come from sibling Actions added
//     under the same Planner.
//   - LeafA (sibling of Root, child of Root in implicit-root tree): effect
//     AKey=true. Atomic.
//
// Phase 1: Initial plan fires. _PlanCompleteCount == 1, plan = [LeafA].
//
// Phase 2: Disable Planner. Reset count to 0. Mutate WS to AKey=true (would
//   normally fire FTag_Goap_Dirty_WorldState → AutoReplan → HandleRequests
//   → Execute → HandleResult → OnPlanComplete). Wait several frames. Assert
//   _PlanCompleteCount == 0 — the disabled Planner did NOT replan.
//
// Phase 3: Re-enable. AutoReplan picks up the dirty tag (still set) and
//   pipelines through; OnPlanComplete fires. Assert _PlanCompleteCount >= 1.
//============================================================================

class UCk_AutoTest_Goap_Planner_DisableTogglePreventsReplan : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_WorldState _WS;
    private int32 _PlanCompleteCount = 0;
    private int32 _DisabledFrameCount = 0;
    private bool _DisablePhaseEntered = false;

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

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);
        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (implicit-root) should return a valid handle");

        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        auto LeafAAction = utils_goap_planner::AddAction(_Planner, LeafAParams);
        Assert_True(ck::IsValid(LeafAAction), "LeafA AddAction should succeed");

        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlan"));
    }

    UFUNCTION()
    private void OnPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        _PlanCompleteCount = _PlanCompleteCount + 1;

        if (!_DisablePhaseEntered && _PlanCompleteCount == 1)
        {
            // Phase 1 -> Phase 2: initial plan landed. Disable the Planner,
            // reset the counter, mutate WS, then poll for several frames
            // asserting count stays at 0.
            Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
                "Root PlanStatus should be PlanFound on first plan");

            utils_goap_planner::Request_SetEnableToggle(_Planner, ECk_EnableDisable::Disable);
            Assert_True(
                utils_goap_planner::Get_EnableToggle(_Planner) == ECk_EnableDisable::Disable,
                "Planner should be disabled after Request_SetEnableToggle(Disable)");

            _PlanCompleteCount = 0;
            _DisablePhaseEntered = true;

            utils_goap_world_state::Set_Value(_WS,
                utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
                true);

            WaitOneFrame(n"OnPollWhileDisabled");
            return;
        }
    }

    // Phase 2 poll: count must stay 0 while Planner is disabled.
    UFUNCTION()
    private void OnPollWhileDisabled(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_PlanCompleteCount == 0,
            f"Disabled Planner must NOT replan (frame {_DisabledFrameCount}, got OnPlanComplete count {_PlanCompleteCount})");

        _DisabledFrameCount = _DisabledFrameCount + 1;
        if (_DisabledFrameCount < 10)
        {
            WaitOneFrame(n"OnPollWhileDisabled");
            return;
        }

        // Phase 3: re-enable. AutoReplan should pick up the dirty tag and
        // pipeline through; OnPlan increments _PlanCompleteCount.
        utils_goap_planner::Request_SetEnableToggle(_Planner, ECk_EnableDisable::Enable);
        Assert_True(
            utils_goap_planner::Get_EnableToggle(_Planner) == ECk_EnableDisable::Enable,
            "Planner should be enabled after Request_SetEnableToggle(Enable)");

        WaitOneFrame(n"OnPollForReenabledPlan");
    }

    UFUNCTION()
    private void OnPollForReenabledPlan(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_PlanCompleteCount >= 1)
        {
            Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
                "Root PlanStatus should be PlanFound after re-enable + replan");
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPollForReenabledPlan");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_DisableTogglePreventsReplan_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_DisableTogglePreventsReplan;
    default _TimeoutSeconds = 15.0f;
}
