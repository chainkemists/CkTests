// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: PARENT-FALLBACK WRITE-THROUGH
//============================================================================
//
// Validates SetValue forwarding (WsParentFallback design Sec.3.4): a Set issued
// through the sub handle for a parent-resident key lands in the PARENT's
// values - no local shadow copy is created on the sub - and a later parent-
// side change is what the sub keeps reading (the alias never becomes truth).
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_WriteThrough : UCk_AutoTest_Base
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

        // Write through the SUB handle.
        utils_goap_world_state::Set_Value(_Sub, SharedKey(), true);

        Add_Step_WaitUntil("forwarded write lands in the parent", n"Check_ParentHasValue");
        Add_Step("assert no local shadow on the sub", n"Step_AssertNoShadow");
        Add_Step("flip the key back through the parent handle", n"Step_ParentWritesFalse");
        Add_Step_WaitUntil("sub reads the parent's new value", n"Check_SubReadsFalse");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ParentHasValue(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_world_state::Get_Value(_Parent, SharedKey()));
    }

    UFUNCTION()
    private void Step_AssertNoShadow(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Get_Value(_Sub, SharedKey()),
            "sub and parent must agree after the forwarded write");
        Assert_True(utils_goap_world_state::Has_Key(_Sub, SharedKey()) == false,
            "forwarding must not register the key on the sub (no shadow copy)");
    }

    UFUNCTION()
    private void Step_ParentWritesFalse(FCk_Handle InHandle, FInstancedStruct InPayload)
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

class ACk_AutoTest_Goap_ParentFallback_WriteThrough_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_WriteThrough;
}
