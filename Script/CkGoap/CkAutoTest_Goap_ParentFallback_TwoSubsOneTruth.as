// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: PARENT-FALLBACK TWO SUBS ONE TRUTH
//============================================================================
//
// Validates single-source-of-truth under fan-out (WsParentFallback design
// test 8): two sibling sub-WS under one parent. A shared-key write through
// sub A is visible through sub B and the parent - one value, no divergence.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_TwoSubsOneTruth : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _Parent;
    private FCk_Handle_Goap_WorldState _SubA;
    private FCk_Handle_Goap_WorldState _SubB;

    private FGameplayTag SharedKey() { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.Shared"); }

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
        _SubA = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Sub"),
            SubParams);
        _SubB = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Sub2"),
            SubParams);

        utils_goap_world_state::Set_Value(_SubA, SharedKey(), true);

        Add_Step_WaitUntil("sub A's write is visible through sub B", n"Check_SubBSees");
        Add_Step("assert one truth everywhere", n"Step_AssertAllAgree");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SubBSees(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_world_state::Get_Value(_SubB, SharedKey()));
    }

    UFUNCTION()
    private void Step_AssertAllAgree(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Get_Value(_Parent, SharedKey()),
            "the parent owns the one true value");
        Assert_True(utils_goap_world_state::Get_Value(_SubA, SharedKey()),
            "sub A agrees");
        Assert_True(utils_goap_world_state::Has_Key(_SubA, SharedKey()) == false
            && utils_goap_world_state::Has_Key(_SubB, SharedKey()) == false,
            "neither sub registers a shadow copy");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_TwoSubsOneTruth_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_TwoSubsOneTruth;
}
