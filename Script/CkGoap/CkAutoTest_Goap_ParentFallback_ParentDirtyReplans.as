// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PARENT-FALLBACK PARENT-DIRTY REPLANS
//============================================================================
//
// Validates chain-aware dirty propagation (WsParentFallback design §3.6): a
// planner sourced from a sub-WS subscribes to the WHOLE parent chain, so a
// value change on the PARENT dirties it and AutoReplan fires — no explicit
// plan request. This is the mechanism that preserves within-trip re-routing
// for shared gates like IsStuck after the BB key migration.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_ParentDirtyReplans : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Goap_WorldState _Parent;
    private FCk_Handle_Goap_WorldState _Sub;
    private FCk_Handle_Goap_Planner _Planner;
    private int32 _PlanCompleteCount = 0;
    private int32 _PlanFailedCount = 0;
    private int32 _FailedCountAtFlip = 0;

    private FGameplayTag SharedKey() { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Shared"); }
    private FGameplayTag LocalKey()  { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Local"); }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto ParentParams = FCk_Fragment_Goap_WorldState_ParamsData();
        auto PreReg = TArray<FGameplayTag>();
        PreReg.Add(SharedKey());
        ParentParams.Set_PreRegisteredKeys(PreReg);
        _Parent = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Parent"),
            ParentParams);
        utils_goap_world_state::Set_Value(_Parent, SharedKey(), true);

        auto SubParams = FCk_Fragment_Goap_WorldState_ParamsData();
        SubParams.Set_FallbackParent(_Parent);
        _Sub = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Sub"),
            SubParams);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(LocalKey(), true));
        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Set"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(_Sub);
        PlannerParams.Set_AllowPlanFailed(true);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);

        utils_goap_planner::AddAction(_Planner, FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ParentFallback_AchieveLocal));

        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlanComplete"));
        utils_goap_planner::BindTo_OnPlanFailed(_Planner,
            FCk_Delegate_Goap_OnPlanFailed(this, n"OnPlanFailed"));

        Add_Step_WaitUntil("gate true lands and a plan is FOUND", n"Check_FoundWithGateTrue");
        Add_Step("flip the parent gate false (no explicit plan request)", n"Step_ParentSetsFalse");
        Add_Step_WaitUntil("parent-dirty replan fires and FAILS", n"Check_DirtyReplanFailed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnPlanComplete(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        _PlanCompleteCount = _PlanCompleteCount + 1;
    }

    UFUNCTION()
    private void OnPlanFailed(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanFailed InPayload)
    {
        _PlanFailedCount = _PlanFailedCount + 1;
    }

    UFUNCTION()
    private void Check_FoundWithGateTrue(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        // The deferred parent Set may land before or after the initial plan; the parent-dirty
        // subscription is what guarantees convergence on PlanFound either way.
        auto Res = OutResult;
        Res.Set(_PlanCompleteCount >= 1
            && utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound
            && utils_goap_planner::Get_PlanClasses(_Planner).Num() == 1);
    }

    UFUNCTION()
    private void Step_ParentSetsFalse(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FailedCountAtFlip = _PlanFailedCount;
        utils_goap_world_state::Set_Value(_Parent, SharedKey(), false);
    }

    UFUNCTION()
    private void Check_DirtyReplanFailed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PlanFailedCount > _FailedCountAtFlip
            && utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFailed);
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_ParentDirtyReplans_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_ParentDirtyReplans;
    default _TimeoutSeconds = 10.0f;
}
