// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: PARENT-FALLBACK OVERRIDE SHADOWS IMPORT
//============================================================================
//
// Validates the snapshot merge ordering (WsParentFallback design Sec.3.5 +
// decision 2): a SUB-side override layer on an imported key shadows the
// parent's value for both reads and the plan snapshot - the sub-planner can
// hypothesize a shared gate true without touching the parent.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_OverrideShadowsImport : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Goap_WorldState _Parent;
    private FCk_Handle_Goap_WorldState _Sub;
    private FCk_Handle_Goap_Planner _Planner;

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

        Add_Step_WaitUntil("initial plan fails (parent gate false, no override)", n"Check_PlanFailed");
        Add_Step("push a sub-side override: Shared=true", n"Step_PushOverride");
        Add_Step_WaitUntil("override-dirty replan finds [AchieveLocal]", n"Check_PlanFound");
        Add_Step("assert the shadow is sub-local only", n"Step_AssertShadow");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_PlanFailed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFailed);
    }

    UFUNCTION()
    private void Step_PushOverride(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_goap_world_state::Push_Override_SingleKey(_Sub, n"hypothesis", SharedKey(), true);

        // Push is synchronous - the effective read flips on this very stack.
        Assert_True(utils_goap_world_state::Get_Value(_Sub, SharedKey()),
            "sub override must shadow the imported key's parent value immediately");
        Assert_True(utils_goap_world_state::Get_Value(_Parent, SharedKey()) == false,
            "the parent's own value must be untouched by a sub-side override");
    }

    UFUNCTION()
    private void Check_PlanFound(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound
            && utils_goap_planner::Get_PlanClasses(_Planner).Num() == 1);
    }

    UFUNCTION()
    private void Step_AssertShadow(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Get_Value(_Parent, SharedKey()) == false,
            "planning against the override must never write the parent");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_OverrideShadowsImport_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_OverrideShadowsImport;
    default _TimeoutSeconds = 10.0f;
}
