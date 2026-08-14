// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PARENT-FALLBACK PARENT TEARDOWN
//============================================================================
//
// Validates the dead-parent contract (WsParentFallback design §3.9): when the
// parent WS is destroyed before the sub-WS, imported keys degrade to MISS
// semantics — reads return false (never the stale alias slot), forwarded
// writes are dropped — and nothing crashes or ensures.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_ParentTeardown : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Goap_WorldState _Parent;
    private FCk_Handle_Goap_WorldState _Sub;
    private FCk_Handle_Goap_Planner _Planner;

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

        Add_Step_WaitUntil("import established and parent truth visible via sub", n"Check_ImportLive");
        Add_Step("destroy the parent WS", n"Step_DestroyParent");
        Add_Step_WaitUntil("parent handle goes invalid", n"Check_ParentDead");
        Add_Step("assert imported reads degrade to false", n"Step_AssertReadsFalse");
        Add_Step("attempt a write through the sub (must drop)", n"Step_WriteViaSub");
        Add_Step_WaitFrames("let the drain run", 5);
        Add_Step("assert the dropped write never surfaced", n"Step_AssertWriteDropped");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ImportLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoImportedContains(_Sub, SharedKey())
            && utils_goap_world_state::Get_Value(_Sub, SharedKey()));
    }

    UFUNCTION()
    private void Step_DestroyParent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_Parent);
    }

    UFUNCTION()
    private void Check_ParentDead(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::Is_NOT_Valid(_Parent));
    }

    UFUNCTION()
    private void Step_AssertReadsFalse(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Get_Value(_Sub, SharedKey()) == false,
            "dead parent: imported key must read false, never the stale alias slot");
    }

    UFUNCTION()
    private void Step_WriteViaSub(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_goap_world_state::Set_Value(_Sub, SharedKey(), true);
    }

    UFUNCTION()
    private void Step_AssertWriteDropped(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Get_Value(_Sub, SharedKey()) == false,
            "dead parent: a forwarded write must be dropped, not served from the alias slot");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_ParentTeardown_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_ParentTeardown;
    default _TimeoutSeconds = 10.0f;
}
