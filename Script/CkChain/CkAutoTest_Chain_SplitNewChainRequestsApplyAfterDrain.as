// Language=angelscript
class UCk_AutoTest_Chain_SplitNewChainRequestsApplyAfterDrain : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FCk_Handle_Chain _NewChain;
    private int32 _EnableCompletions = 0;
    private ECk_Request_OperationResult _EnableResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose a disabled chain with two links", n"Step_Arrange");
        Add_Step_WaitUntil("roster ready", n"Check_Ready");
        Add_Step("split, then enable the new chain before the split drains", n"Step_Split");
        Add_Step_WaitUntil("split drained and enable completed", n"Check_Drained");
        Add_Step("assert the new chain's enable applied after the split", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Owner = InHandle;
        _F.Head = _F.Spawn(FVector::ZeroVector);
        auto Spec = FCk_Chain_Spec(ECk_Chain_Solver::PathHistory);
        Spec.Set_StartingState(ECk_EnableDisable::Disable);
        _F.Chain = utils_chain::Add(_F.Head, Spec);
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
    private void Step_Split(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _NewChain = utils_chain::Request_Split(_F.Chain, FCk_Request_Chain_Split(_F.Links[0].As_ChainLink()),
            FCk_Delegate_Request_OnCompleted());
        utils_chain::Request_EnableDisable(_NewChain, FCk_Request_Chain_EnableDisable(ECk_EnableDisable::Enable),
            FCk_Delegate_Request_OnCompleted(this, n"OnEnableCompleted"));
    }

    UFUNCTION()
    private void OnEnableCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_EnableCompletions;
        _EnableResult = InResult;
    }

    UFUNCTION()
    private void Check_Drained(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_NewChain) && utils_chain::Get_NumLinks(_NewChain) == 1 && _EnableCompletions > 0);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_EnableCompletions, 1, "the new chain's enable completes exactly once");
        Assert_True(_EnableResult == ECk_Request_OperationResult::Succeeded, "the new chain's enable succeeds");
        Assert_True(utils_chain::Get_IsEnabled(_NewChain), "the enable queued on the new chain holds after the split synced the disabled source");
        Assert_False(utils_chain::Get_IsEnabled(_F.Chain), "the source stays disabled");
        FinishSuccess();
    }
}
