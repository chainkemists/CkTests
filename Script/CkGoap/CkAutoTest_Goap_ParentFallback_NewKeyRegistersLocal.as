// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PARENT-FALLBACK NEW KEY REGISTERS LOCAL
//============================================================================
//
// Validates decision 3 of the WsParentFallback design: a Set for a key that
// is resident NOWHERE in the chain keeps today's contract — it registers on
// the written (sub) WS, and never touches the parent.
//============================================================================

class UCk_AutoTest_Goap_ParentFallback_NewKeyRegistersLocal : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_WorldState _Parent;
    private FCk_Handle_Goap_WorldState _Sub;

    private FGameplayTag NewKey() { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.Key.New"); }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _Parent = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Parent"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        auto SubParams = FCk_Fragment_Goap_WorldState_ParamsData();
        SubParams.Set_FallbackParent(_Parent);
        _Sub = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ParentFallback.WS.Sub"),
            SubParams);

        utils_goap_world_state::Set_Value(_Sub, NewKey(), true);

        Add_Step_WaitUntil("new-key write lands locally on the sub", n"Check_SubHasValue");
        Add_Step("assert local residency, parent untouched", n"Step_AssertLocal");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SubHasValue(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_world_state::Get_Value(_Sub, NewKey()));
    }

    UFUNCTION()
    private void Step_AssertLocal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_goap_world_state::Has_Key(_Sub, NewKey()),
            "the nowhere-resident key must register on the written (sub) WS");
        Assert_True(utils_goap_world_state::Has_Key(_Parent, NewKey()) == false,
            "the parent registry must be untouched");
        Assert_True(utils_goap_world_state::Get_Value(_Parent, NewKey()) == false,
            "the parent must not see the sub-local value");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ParentFallback_NewKeyRegistersLocal_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ParentFallback_NewKeyRegistersLocal;
}
