// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: PARENT-FALLBACK ADVERSARIAL ORDERING
//============================================================================
//
// Pins the residency-ordering hazard (WsParentFallback design Sec.6) as a
// regression test instead of a doc paragraph. Key.Probe is referenced by the
// ProbeOnly SUB-action ONLY - never by any other action - so its residency is
// decided purely by pre-registration:
//
//   Pair A: parent WITHOUT pre-registration -> Probe classifies SUB-LOCAL
//           (the documented misclassification: findable, not silent).
//   Pair B: parent pre-registers Probe      -> Probe classifies as an IMPORT.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_AdversarialOrdering : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Goap_WorldState _ParentA;
    private FCk_Handle_Goap_WorldState _SubA;
    private FCk_Handle_Goap_WorldState _ParentB;
    private FCk_Handle_Goap_WorldState _SubB;

    private FGameplayTag ProbeKey() { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Probe"); }
    private FGameplayTag LocalKey() { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Local"); }

    private bool DoImportedContains(const FCk_Handle_Goap_WorldState& InWS, FGameplayTag InTag)
    {
        for (auto Tag : utils_goap_world_state::Get_ImportedKeys(InWS))
        {
            if (Tag == InTag) { return true; }
        }
        return false;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // ---- Pair A: pre-registration deliberately OMITTED ----
        _ParentA = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Parent"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto SubAParams = FCk_Fragment_Goap_WorldState_ParamsData();
        SubAParams.Set_FallbackParent(_ParentA);
        _SubA = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Sub"),
            SubAParams);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(LocalKey(), true));

        auto PlannerAParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Set"));
        PlannerAParams.Set_Goal(Goal);
        PlannerAParams.Set_WorldStateSource(_SubA);
        PlannerAParams.Set_AllowPlanFailed(true);
        auto PlannerA = utils_goap_planner::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Set"),
            PlannerAParams);
        utils_goap_planner::AddAction(PlannerA, FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ParentFallback_ProbeOnly));

        // ---- Pair B: parent pre-registers the probe ----
        auto ParentBParams = FCk_Fragment_Goap_WorldState_ParamsData();
        auto PreReg = TArray<FGameplayTag>();
        PreReg.Add(ProbeKey());
        ParentBParams.Set_PreRegisteredKeys(PreReg);
        _ParentB = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Parent2"),
            ParentBParams);

        auto SubBParams = FCk_Fragment_Goap_WorldState_ParamsData();
        SubBParams.Set_FallbackParent(_ParentB);
        _SubB = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Sub2"),
            SubBParams);

        auto PlannerBParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        PlannerBParams.Set_Goal(Goal);
        PlannerBParams.Set_WorldStateSource(_SubB);
        PlannerBParams.Set_AllowPlanFailed(true);
        auto PlannerB = utils_goap_planner::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"),
            PlannerBParams);
        utils_goap_planner::AddAction(PlannerB, FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ParentFallback_ProbeOnly));

        Add_Step_WaitUntil("both pairs' action setups have classified the probe", n"Check_BothClassified");
        Add_Step("assert the residency split matches pre-registration", n"Step_AssertOrderingOutcomes");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_BothClassified(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_world_state::Has_Key(_SubA, ProbeKey())
            && utils_goap_world_state::Has_Key(_SubB, ProbeKey()));
    }

    UFUNCTION()
    private void Step_AssertOrderingOutcomes(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Pair A - the documented hazard: without pre-registration the probe lands sub-local.
        Assert_True(DoImportedContains(_SubA, ProbeKey()) == false,
            "pair A: probe must classify SUB-LOCAL when the parent never pre-registered it");
        Assert_True(utils_goap_world_state::Has_Key(_ParentA, ProbeKey()) == false,
            "pair A: the parent registry must not have gained the probe");

        // Pair B - pre-registration pins the intended residency.
        Assert_True(DoImportedContains(_SubB, ProbeKey()),
            "pair B: probe must classify as an IMPORT when the parent pre-registered it");
        Assert_True(utils_goap_world_state::Has_Key(_ParentB, ProbeKey()),
            "pair B: the parent owns the probe");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_AdversarialOrdering_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_AdversarialOrdering;
    default _TimeoutSeconds = 10.0f;
}
