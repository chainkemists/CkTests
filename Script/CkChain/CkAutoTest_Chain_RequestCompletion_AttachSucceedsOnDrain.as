// Language=angelscript
class UCk_AutoTest_Chain_RequestCompletion_AttachSucceedsOnDrain : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private FCk_Handle _CompletionOwner;
    private bool _VisibleOnCompletion = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("create and enqueue attach", n"Step_Arrange");
        Add_Step_WaitUntil("completion arrives", n"Check_Completed");
        Add_Step_WaitSeconds("exclude repeated completion", 0.1f);
        Add_Step("assert completion contract", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Links.Add(_F.Spawn(FVector(0.0, 500.0, 0.0)));
        utils_chain::Request_AttachLink(_F.Chain, FCk_Request_Chain_AttachLink(_F.Links[0],
            FCk_ChainLink_Spec(100.0f)), FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Completions, 0, "attach must remain deferred until drain");
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
        _CompletionOwner = InOwner;
        _VisibleOnCompletion = utils_chain_link::Has(_F.Links[0]) && utils_chain::Get_NumLinks(_F.Chain) == 1;
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
        Assert_Equals_Int(_Completions, 1, "attach completion exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Succeeded, "attach succeeds on drain");
        Assert_True(_CompletionOwner == _F.Chain, "completion identifies chain owner");
        Assert_True(_VisibleOnCompletion, "composition and roster observable inside completion");
        FinishSuccess();
    }
}

