// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PARENT-FALLBACK READ-THROUGH
//============================================================================
//
// Validates chain-aware Get_Value (WsParentFallback design §3.3): a key that
// is not registered on the sub-WS at all reads through to the parent's value.
// No planner involved — this is the pure miss-path fallback.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_ReadThrough : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _Parent;
    private FCk_Handle_Goap_WorldState _Sub;

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
        _Sub = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Sub"),
            SubParams);

        Assert_True(utils_goap_world_state::Get_Value(_Sub, SharedKey()) == false,
            "before any write, the shared key reads false through the sub handle");
        Assert_True(utils_goap_world_state::Has_Key_InChain(_Sub, SharedKey()),
            "Has_Key_InChain must see the parent-resident key from the sub handle");
        Assert_True(utils_goap_world_state::Has_Key(_Sub, SharedKey()) == false,
            "a pure read-through key is not registered on the sub itself");

        utils_goap_world_state::Set_Value(_Parent, SharedKey(), true);

        Add_Step_WaitUntil("parent write becomes visible through the sub handle", n"Check_SubSeesParentValue");
        Add_Step("assert parent agrees", n"Step_AssertParent");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SubSeesParentValue(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_world_state::Get_Value(_Sub, SharedKey()));
    }

    UFUNCTION()
    private void Step_AssertParent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Get_Value(_Parent, SharedKey()),
            "the parent handle reads its own value");
        Assert_True(utils_goap_world_state::Has_Key(_Sub, SharedKey()) == false,
            "read-through must not register the key on the sub");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_ReadThrough_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_ReadThrough;
}
