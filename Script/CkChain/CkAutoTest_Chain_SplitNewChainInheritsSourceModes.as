// Language=angelscript
class UCk_AutoTest_Chain_SplitNewChainInheritsSourceModes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FCk_Handle_Chain _NewChain;
    private bool _DisabledStartIsImmediate = false;
    private bool _Reseeded = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose hold-seeded everywhere chain with two links", n"Step_Arrange");
        Add_Step_WaitUntil("roster ready", n"Check_Ready");
        Add_Step("disable, then split in the same frame", n"Step_Split");
        Add_Step_WaitUntil("split drained", n"Check_Split");
        Add_Step("assert the new chain carries the source modes", n"Step_Verify");
        Add_Step_WaitUntil("new chain reseeded", n"Check_Reseeded");
        Add_Step("assert the new chain keeps the source spacing", n"Step_VerifySpacing");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Owner = InHandle;
        _F.Head = _F.Spawn(FVector::ZeroVector);
        auto Spec = FCk_Chain_Spec(ECk_Chain_Solver::PathHistory);
        Spec.Set_HistorySeed(ECk_Chain_HistorySeed::HoldUntilCovered);
        Spec.Set_NetPolicy(ECk_Chain_NetPolicy::Everywhere);
        Spec.Set_SampleSpacingCm(25.0f);
        _F.Chain = utils_chain::Add(_F.Head, Spec);
        _F.Attach(100.0f);
        _F.Attach(200.0f);

        auto DisabledHead = _F.Spawn(FVector(0.0, 300.0, 0.0));
        auto DisabledSpec = FCk_Chain_Spec(ECk_Chain_Solver::PathHistory);
        DisabledSpec.Set_StartingState(ECk_EnableDisable::Disable);
        _DisabledStartIsImmediate = !utils_chain::Get_IsEnabled(utils_chain::Add(DisabledHead, DisabledSpec));
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
        Assert_True(utils_chain::Get_IsEnabled(_F.Chain), "source is enabled when the split is requested");
        utils_chain::Request_EnableDisable(_F.Chain, FCk_Request_Chain_EnableDisable(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted());
        _NewChain = utils_chain::Request_Split(_F.Chain, FCk_Request_Chain_Split(_F.Links[0].As_ChainLink()),
            FCk_Delegate_Request_OnCompleted());
    }

    UFUNCTION()
    private void Check_Split(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_NewChain) && utils_chain::Get_NumLinks(_NewChain) == 1);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_DisabledStartIsImmediate, "a disabled starting state holds from Add, before setup");
        Assert_False(utils_chain::Get_IsEnabled(_F.Chain), "the queued disable applied to the source");
        Assert_False(utils_chain::Get_IsEnabled(_NewChain), "the new chain takes the source's enable state at drain");
        Assert_True(utils_chain::Get_NetPolicy(_NewChain) == ECk_Chain_NetPolicy::Everywhere, "the new chain keeps the net policy");
        Assert_True(utils_chain::Get_NumHistorySamples(_NewChain) > 0, "the new chain has history to query");
        Assert_False(utils_chain::Get_PoseAtDistance(_NewChain, 10000.0f).Get_IsValid(),
            "the new chain keeps HoldUntilCovered: an uncovered distance is unavailable");
        utils_chain::Request_ReseedHistory(_NewChain, FCk_Request_Chain_ReseedHistory(), FCk_Delegate_Request_OnCompleted(this, n"OnReseeded"));
    }

    UFUNCTION()
    private void OnReseeded(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        _Reseeded = InResult == ECk_Request_OperationResult::Succeeded;
    }

    UFUNCTION()
    private void Check_Reseeded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Reseeded);
    }

    UFUNCTION()
    private void Step_VerifySpacing(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(Math::IsNearlyEqual(utils_chain::Get_HistoryLengthCm(_NewChain), 25.0f, 0.01f),
            "a reseeded new chain spaces its seed by the source's 25 cm, not the 10 cm default");
        FinishSuccess();
    }
}
