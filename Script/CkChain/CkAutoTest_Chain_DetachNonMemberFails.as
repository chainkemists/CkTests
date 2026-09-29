// Language=angelscript
class UCk_AutoTest_Chain_DetachNonMemberFails : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FCk_ChainAutoTestFixture _Other;
    private bool _Done = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach one link in each roster", n"Step_Arrange");
        Add_Step_WaitUntil("both rosters ready", n"Check_Ready");
        Add_Step("detach foreign member", n"Step_Detach");
        Add_Step_WaitUntil("failed completion", n"Check_Done");
        Add_Step("assert atomic refusal", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(100.0f);
        _Other.Init(InHandle);
        _Other.Attach(200.0f);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1) && _Other.Ready(1));
    }

    UFUNCTION()
    private void Step_Detach(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_chain::Request_DetachLink(_Other.Chain, FCk_Request_Chain_DetachLink(_F.Links[0].As_ChainLink()),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        Assert_True(InResult == ECk_Request_OperationResult::Failed, "foreign detach fails after drain");
        _Done = true;
    }

    UFUNCTION()
    private void Check_Done(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Done);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_F.Ready(1) && _Other.Ready(1), "both rosters unchanged");
        Assert_True(utils_chain_link::Get_Chain(_F.Links[0].As_ChainLink()) == _F.Chain, "original ownership retained");
        FinishSuccess();
    }
}
