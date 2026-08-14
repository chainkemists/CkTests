// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PARENT-FALLBACK PROMOTED HOST ROLE SPLIT
//============================================================================
//
// Pins the candidate-role / planner-role split (WsParentFallback design
// §3.10), the exact shape of the BB sub-planner migration: a host action is
// BOTH a candidate in the top-level planner's search AND (promoted, carrying
// _WorldStateSource_Override) the planner for a sub-WS catalog.
//
//   - Candidate role: the host's precond (Key.Shared) / effect (Key.New)
//     register in the PARENT WS's index space — never the sub's.
//   - Planner role: the host's goal (Key.Local) and children register in the
//     SUB WS.
//
// The two registries are seeded with DIFFERENT key orders (parent pre-regs
// Shared+New; sub pre-regs Probe first), so any cross-registry leak would
// misalign indices and corrupt the parent's search — the silent failure this
// split exists to prevent.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_PromotedHostRoleSplit : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Goap_WorldState _ParentWS;
    private FCk_Handle_Goap_WorldState _SubWS;
    private FCk_Handle_Goap_Planner _TopPlanner;
    private FCk_Handle_Goap_Planner _SubPlanner;

    private FGameplayTag SharedKey() { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Shared"); }
    private FGameplayTag NewKey()    { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.New"); }
    private FGameplayTag LocalKey()  { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Local"); }
    private FGameplayTag ProbeKey()  { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Probe"); }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto ParentParams = FCk_Fragment_Goap_WorldState_ParamsData();
        auto ParentPreReg = TArray<FGameplayTag>();
        ParentPreReg.Add(SharedKey());
        ParentPreReg.Add(NewKey());
        ParentParams.Set_PreRegisteredKeys(ParentPreReg);
        _ParentWS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Parent"),
            ParentParams);

        // Different first key => diverged index meaning versus the parent.
        auto SubParams = FCk_Fragment_Goap_WorldState_ParamsData();
        auto SubPreReg = TArray<FGameplayTag>();
        SubPreReg.Add(ProbeKey());
        SubParams.Set_PreRegisteredKeys(SubPreReg);
        SubParams.Set_FallbackParent(_ParentWS);
        _SubWS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Sub"),
            SubParams);

        auto TopGoal = TArray<FCk_GoapWS_Condition_Authored>();
        TopGoal.Add(FCk_GoapWS_Condition_Authored(NewKey(), true));
        auto TopParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Set"));
        TopParams.Set_Goal(TopGoal);
        TopParams.Set_WorldStateSource(_ParentWS);
        TopParams.Set_AllowPlanFailed(true);
        _TopPlanner = utils_goap_planner::Add(Local, TopParams);

        // The dual-role host: candidate in _TopPlanner, promoted planner over _SubWS.
        auto HostParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ParentFallback_Host);
        HostParams.Set_WorldStateSource_Override(_SubWS);
        auto HostAsAction = utils_goap_planner::AddAction(_TopPlanner, HostParams);

        auto SubGoal = TArray<FCk_GoapWS_Condition_Authored>();
        SubGoal.Add(FCk_GoapWS_Condition_Authored(LocalKey(), true));
        auto SubPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        SubPlannerParams.Set_Goal(SubGoal);
        SubPlannerParams.Set_PlanOnStart(false); // sub-planners plan on activation only
        SubPlannerParams.Set_AllowPlanFailed(true);
        _SubPlanner = utils_goap_planner::PromoteActionToPlanner(HostAsAction, SubPlannerParams);

        utils_goap_planner::AddAction(_SubPlanner, FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ParentFallback_SubAchieve));

        Add_Step_WaitUntil("parent plan fails while the gate is false", n"Check_ParentPlanFailed");
        Add_Step("assert candidate-role keys stayed out of the sub registry", n"Step_AssertRoleSplit");
        Add_Step("flip the gate on the parent WS", n"Step_GateTrue");
        Add_Step_WaitUntil("parent plans [Host] (gate read in parent index space)", n"Check_ParentPlansHost");
        Add_Step_WaitUntil("activated sub-planner plans [SubAchieve] in sub space", n"Check_SubPlansChild");
        Add_Step("assert no upward leak of sub keys", n"Step_AssertNoUpwardLeak");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ParentPlanFailed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_PlanStatus(_TopPlanner) == ECk_GoapPlanStatus::PlanFailed);
    }

    UFUNCTION()
    private void Step_AssertRoleSplit(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Has_Key(_SubWS, SharedKey()) == false,
            "the host's precondition must NOT register into the sub registry (candidate role)");
        Assert_True(utils_goap_world_state::Has_Key(_SubWS, NewKey()) == false,
            "the host's effect must NOT register into the sub registry (candidate role)");
        Assert_True(utils_goap_world_state::Has_Key(_ParentWS, SharedKey())
            && utils_goap_world_state::Has_Key(_ParentWS, NewKey()),
            "the host's candidate keys live in the parent registry");
    }

    UFUNCTION()
    private void Step_GateTrue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_goap_world_state::Set_Value(_ParentWS, SharedKey(), true);
    }

    UFUNCTION()
    private void Check_ParentPlansHost(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Plan = utils_goap_planner::Get_PlanClasses(_TopPlanner);
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_PlanStatus(_TopPlanner) == ECk_GoapPlanStatus::PlanFound
            && Plan.Num() == 1
            && Plan[0] == UCk_AutoTestAction_Goap_ParentFallback_Host);
    }

    UFUNCTION()
    private void Check_SubPlansChild(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Plan = utils_goap_planner::Get_PlanClasses(_SubPlanner);
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_PlanStatus(_SubPlanner) == ECk_GoapPlanStatus::PlanFound
            && Plan.Num() == 1
            && Plan[0] == UCk_AutoTestAction_Goap_ParentFallback_SubAchieve);
    }

    UFUNCTION()
    private void Step_AssertNoUpwardLeak(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Has_Key(_ParentWS, LocalKey()) == false,
            "the sub-planner's goal/effect key must not leak into the parent registry");
        Assert_True(utils_goap_world_state::Has_Key(_SubWS, LocalKey()),
            "the sub-planner's goal/effect key lives in the sub registry");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_PromotedHostRoleSplit_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_PromotedHostRoleSplit;
    default _TimeoutSeconds = 10.0f;
}
