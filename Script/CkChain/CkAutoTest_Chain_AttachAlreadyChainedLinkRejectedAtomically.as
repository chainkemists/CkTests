// Language=angelscript
class UCk_AutoTest_Chain_AttachAlreadyChainedLinkRejectedAtomically : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private FCk_Handle _CompletionOwner;
    private FCk_ChainAutoTestFixture _Other;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach to first chain", n"Step_Arrange");
        Add_Step_WaitUntil("first attach drained", n"Check_Ready");
        Add_Step("reject second ownership", n"Step_Reject");
        Add_Step_WaitSeconds("exclude stray second drain", 0.1f);
        Add_Step("assert ownership unchanged", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(100.0f);
        _Other.Init(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1));
    }

    UFUNCTION()
    private void Step_Reject(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_chain::Request_AttachLink(_Other.Chain, FCk_Request_Chain_AttachLink(_F.Links[0],
            FCk_ChainLink_Spec(100.0f)), FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Completions, 1, "second owner rejected synchronously");
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
        _CompletionOwner = InOwner;
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Result == ECk_Request_OperationResult::Failed_NotEnqueued, "second attach not enqueued");
        Assert_Equals_Int(_Completions, 1, "rejection exactly once");
        Assert_True(utils_chain_link::Get_Chain(_F.Links[0].As_ChainLink()) == _F.Chain, "first owner retained");
        Assert_Equals_Int(utils_chain::Get_NumLinks(_F.Chain), 1, "first roster unchanged");
        Assert_Equals_Int(utils_chain::Get_NumLinks(_Other.Chain), 0, "second roster empty");
        FinishSuccess();
    }
}

class ACk_AutoTest_Chain_AttachAlreadyChainedLinkRejectedAtomically_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Chain_AttachAlreadyChainedLinkRejectedAtomically;
    default _TimeoutSeconds = 6.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Chain AttachLink rejected incompatible link or parameters");
        return Errors;
    }
}

