// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: PARENT-FALLBACK PLAN FLIP
//============================================================================
//
// Validates the plan-snapshot import merge (WsParentFallback design Sec.3.5):
// a sub-planner whose only action is gated on a parent-resident key plans
// PlanFailed while the parent holds false, and PlanFound [AchieveLocal] after
// the parent value flips - the A* snapshot must read the PARENT's truth
// through the local import alias. Afterwards, the alias slot must not leak:
// a later parent-side flip is still what the sub handle reads.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_PlanFlip : UCk_AutoTest_Base
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

        Add_Step_WaitUntil("initial plan fails (parent gate false)", n"Check_PlanFailed");
        Add_Step("flip the gate through the PARENT handle", n"Step_ParentSetsTrue");
        Add_Step_WaitUntil("replan finds [AchieveLocal] (snapshot read the parent's truth)", n"Check_PlanFound");
        Add_Step("assert plan content and read-through", n"Step_AssertPlan");
        Add_Step("flip the gate back through the parent", n"Step_ParentSetsFalse");
        Add_Step_WaitUntil("sub handle reads the new parent value (alias never leaks)", n"Check_SubReadsFalse");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_PlanFailed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFailed);
    }

    UFUNCTION()
    private void Step_ParentSetsTrue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_goap_world_state::Set_Value(_Parent, SharedKey(), true);
    }

    UFUNCTION()
    private void Check_PlanFound(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound
            && utils_goap_planner::Get_PlanClasses(_Planner).Num() == 1);
    }

    UFUNCTION()
    private void Step_AssertPlan(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);
        Assert_True(Plan.Num() == 1 && Plan[0] == UCk_AutoTestAction_Goap_ParentFallback_AchieveLocal,
            "the found plan must be exactly [AchieveLocal]");
        Assert_True(utils_goap_world_state::Get_Value(_Sub, SharedKey()),
            "the imported key reads the parent's truth through the sub handle");
    }

    UFUNCTION()
    private void Step_ParentSetsFalse(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_goap_world_state::Set_Value(_Parent, SharedKey(), false);
    }

    UFUNCTION()
    private void Check_SubReadsFalse(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_world_state::Get_Value(_Sub, SharedKey()) == false);
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_PlanFlip_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_PlanFlip;
    default _TimeoutSeconds = 10.0f;
}
