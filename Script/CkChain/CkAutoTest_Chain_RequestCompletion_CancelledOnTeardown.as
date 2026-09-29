// Language=angelscript
class UCk_AutoTest_Chain_RequestCompletion_CancelledOnTeardown : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private FCk_Handle _CompletionOwner;
    private int32 _ReentrantCompletions = 0;
    private ECk_Request_OperationResult _ReentrantResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("enqueue then destroy owner before drain", n"Step_Arrange");
        Add_Step_WaitUntil("cancellation arrives", n"Check_Completed");
        Add_Step_WaitSeconds("exclude repeated cancellation", 0.1f);
        Add_Step("assert cancelled", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Links.Add(_F.Spawn(FVector(0.0, 500.0, 0.0)));
        utils_chain::Request_AttachLink(_F.Chain, FCk_Request_Chain_AttachLink(_F.Links[0],
            FCk_ChainLink_Spec(100.0f)), FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        FCk_Handle ChainEntity = _F.Chain;
        utils_entity_lifetime::Request_DestroyEntity(ChainEntity);
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
        _CompletionOwner = InOwner;
        utils_chain::Request_ReseedHistory(_F.Chain, FCk_Request_Chain_ReseedHistory(),
            FCk_Delegate_Request_OnCompleted(this, n"OnReentrantCompleted"));
        Assert_Equals_Int(_ReentrantCompletions, 1, "destroying owner rejects callback request synchronously");
    }

    UFUNCTION()
    private void OnReentrantCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_ReentrantCompletions;
        _ReentrantResult = InResult;
        Assert_True(InOwner == _F.Chain, "reentrant rejection identifies dying owner");
    }

    UFUNCTION()
    private void Check_Completed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Completions > 0);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "cancel exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Failed_Cancelled, "teardown cancels queued attach");
        Assert_True(_CompletionOwner == _F.Chain, "cancel reports original owner");
        Assert_False(utils_chain_link::Has(_F.Links[0]), "cancelled attach composes no link");
        Assert_Equals_Int(_ReentrantCompletions, 1, "reentrant completion exactly once");
        Assert_True(_ReentrantResult == ECk_Request_OperationResult::Failed_NotEnqueued, "reseed cannot resurrect requests during teardown");
        Assert_Invalid(_F.Chain, "dying owner reaches destruction");
        FinishSuccess();
    }
}
