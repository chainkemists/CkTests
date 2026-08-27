// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: an idle, settled planner leaves the per-frame views
//============================================================================
//
// FProcessor_Goap_Planner_AutoReplan and FProcessor_Goap_Planner_UpdateActivation
// declared no view-narrowing fragment, so every planner in the world was visited
// every frame just to early-out. At scale that is a per-frame floor linear in
// planner count (measured: 1127 planners x ~4 us = ~4.5 ms/frame spent deciding
// there is nothing to do).
//
// Shape: the DirtyPropagation fixture (goal {AKey=true}, LeafA supplies it, WS
// starts false) so the first plan is a real one. Let it settle, hold it idle for
// three frames, then read the scheduler's per-frame MAIN-PASS entity count for
// both nodes: zero means the candidate / activation-dirty tags took the planner
// out of the view. The final leg dirties the WS once and proves the gate lets a
// dirty planner back in - a gate that never re-opened would also read zero.
//============================================================================

class UCk_AutoTest_Goap_IdlePlannerNotVisitedByAutoReplan : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_Goap_Planner    _Planner;
    private FCk_Handle_Goap_WorldState _WS;
    private int32                      _PlanCompleteCount = 0;
    private int64                      _IdleFrame = 0;

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

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        PlannerParams.Set_Goal(InitialGoal);
        PlannerParams.Set_WorldStateSource(_WS);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        auto LeafA = utils_goap_planner::AddAction(_Planner, LeafAParams);
        Assert_True(ck::IsValid(LeafA), "AddAction (LeafA) should return a valid handle");

        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
    }

    UFUNCTION()
    private void OnPlanComplete(
        FCk_Handle_Goap_Planner InPlanner,
        FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        _PlanCompleteCount = _PlanCompleteCount + 1;

        if (_PlanCompleteCount == 1)
        {
            Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
                "the planner must reach PlanFound before the idle window is measured");

            // Three idle frames with no WS or cost mutation, so everything the
            // initial plan dirtied is consumed before the measured frame. A frame
            // count is right here: the assertion is that nothing happens, so there
            // is no condition to wait on.
            WaitFrames(3, n"OnIdle");
        }
    }

    UFUNCTION()
    private void OnIdle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        _IdleFrame = utils_time::Get_FrameCounter();
        WaitFrames(2, n"OnIdleFrameRecorded");
    }

    UFUNCTION()
    private void OnIdleFrameRecorded(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        const FName AutoReplanNode = n"class ck::FProcessor_Goap_Planner_AutoReplan";
        const FName UpdateActivationNode = n"class ck::FProcessor_Goap_Planner_UpdateActivation";

        const int32 AutoReplanVisited = UCk_Utils_EcsWorld_Subsystem_UE::Get_Debug_ProcessorMainPassEntityCountForFrame(
            this, AutoReplanNode, _IdleFrame);
        const int32 UpdateActivationVisited = UCk_Utils_EcsWorld_Subsystem_UE::Get_Debug_ProcessorMainPassEntityCountForFrame(
            this, UpdateActivationNode, _IdleFrame);

        Assert_True(AutoReplanVisited >= 0,
            f"node name wrong: [{AutoReplanNode}] did not resolve in the scheduler debug history for frame [{_IdleFrame}] (got {AutoReplanVisited})");
        Assert_True(UpdateActivationVisited >= 0,
            f"node name wrong: [{UpdateActivationNode}] did not resolve in the scheduler debug history for frame [{_IdleFrame}] (got {UpdateActivationVisited})");

        Assert_Equals_Int(AutoReplanVisited, 0,
            f"an idle, settled planner must not be visited by AutoReplan (count={AutoReplanVisited}); a nonzero count is the per-frame O(planners) floor");
        Assert_Equals_Int(UpdateActivationVisited, 0,
            f"an idle, settled planner must not be visited by UpdateActivation (count={UpdateActivationVisited}); a nonzero count is the per-frame O(planners) floor");

        // The gate must re-open: dirty the WS once and require a second plan.
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true);

        WaitUntil(n"Check_DirtyReplanFired", n"OnSecondPlanArrived");
    }

    UFUNCTION()
    private void Check_DirtyReplanFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PlanCompleteCount >= 2);
    }

    UFUNCTION()
    private void OnSecondPlanArrived(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_PlanCompleteCount, 2,
            f"dirtying the world state must let the planner back into AutoReplan (plan-complete count={_PlanCompleteCount}); a gate that never re-opens would starve every replan");

        FinishSuccess();
    }
}
