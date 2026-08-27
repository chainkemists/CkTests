// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: PARENT-FALLBACK RESIDENCY CLASSIFICATION
//============================================================================
//
// Validates the import-aliasing residency split (WsParentFallback design Sec.3.2):
// an action on a sub-WS references one parent-resident key (Key.Shared,
// pre-registered on the parent at composition) and one brand-new key
// (Key.Local). Setup must classify Shared as an IMPORT alias (locally
// registered, truth in the parent) and Local as sub-resident - and Local must
// never leak into the parent registry.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_Classification : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Goap_WorldState _Parent;
    private FCk_Handle_Goap_WorldState _Sub;

    private FGameplayTag SharedKey() { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Shared"); }
    private FGameplayTag LocalKey()  { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Local"); }

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

        auto ParentParams = FCk_Fragment_Goap_WorldState_ParamsData();
        auto PreReg = TArray<FGameplayTag>();
        PreReg.Add(SharedKey());
        ParentParams.Set_PreRegisteredKeys(PreReg);
        _Parent = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Parent"),
            ParentParams);
        Assert_True(ck::IsValid(_Parent), "parent WS should be a valid handle");

        // Pre-registration is synchronous at composition - resident immediately, no settle.
        Assert_True(utils_goap_world_state::Has_Key(_Parent, SharedKey()),
            "pre-registered Key.Shared must be resident on the parent the moment Create returns");

        auto SubParams = FCk_Fragment_Goap_WorldState_ParamsData();
        SubParams.Set_FallbackParent(_Parent);
        _Sub = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Sub"),
            SubParams);
        Assert_True(ck::IsValid(_Sub), "sub WS should be a valid handle");
        Assert_True(utils_goap_world_state::Get_FallbackParent(_Sub) == _Parent,
            "sub WS must report the parent it was composed with");

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(LocalKey(), true));
        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Set"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(_Sub);
        PlannerParams.Set_AllowPlanFailed(true);
        auto Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(Planner), "Add Planner should return a valid handle");

        utils_goap_planner::AddAction(Planner, FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ParentFallback_AchieveLocal));

        Add_Step_WaitUntil("action setup classifies Key.Shared as an import on the sub-WS", n"Check_Classified");
        Add_Step("assert the residency split", n"Step_AssertResidency");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Classified(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoImportedContains(_Sub, SharedKey()));
    }

    UFUNCTION()
    private void Step_AssertResidency(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Has_Key(_Sub, SharedKey()),
            "the import alias must register Key.Shared in the sub registry (single index space)");
        Assert_True(utils_goap_world_state::Has_Key(_Sub, LocalKey()),
            "Key.Local must be sub-resident");
        Assert_True(DoImportedContains(_Sub, LocalKey()) == false,
            "Key.Local must NOT be classified as an import");
        Assert_True(utils_goap_world_state::Has_Key(_Parent, LocalKey()) == false,
            "Key.Local must not leak into the parent registry");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_Classification_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_Classification;
    default _TimeoutSeconds = 10.0f;
}
