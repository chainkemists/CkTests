// Language=angelscript
class UCk_AutoTest_Chain_SplitCancelledDestroysNewChain : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FCk_Handle_Chain _NewChain;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("create split source", n"Step_Arrange");
        Add_Step_WaitUntil("links attached", n"Check_Ready");
        Add_Step("split then tear down source in same step", n"Step_Cancel");
        Add_Step_WaitUntil("cancellation drain completed", n"Check_Cancelled");
        Add_Step_WaitSeconds("no leaked chain or repeated completion", 0.1f);
        Add_Step("assert cancellation cleanup", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(100.0f);
        _F.Attach(200.0f);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(2));
    }

    UFUNCTION()
    private void Step_Cancel(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _NewChain = utils_chain::Request_Split(_F.Chain, FCk_Request_Chain_Split(_F.Links[0].As_ChainLink()), FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Valid(_NewChain, "split returns provisional chain before drain");
        auto Source = _F.Chain;
        utils_entity_lifetime::Request_DestroyEntity(Source);
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Check_Cancelled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Completions > 0 && ck::Is_NOT_Valid(_NewChain));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "split cancellation exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Failed_Cancelled, "source teardown cancels pending split");
        Assert_Invalid(_NewChain, "provisional split child destroyed");
        Assert_Valid(_F.Links[0], "surviving split link");
        Assert_Valid(_F.Links[1], "surviving follower");
        Assert_False(utils_chain_link::Has(_F.Links[0]), "no dangling split membership");
        Assert_False(utils_chain_link::Has(_F.Links[1]), "no dangling follower membership");
        FinishSuccess();
    }
}
