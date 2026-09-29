// Language=angelscript
class UCk_AutoTest_Chain_SplitProducesNewChainHeadedByLink : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FCk_Handle_Chain _NewChain;
    private int32 _Moved = 0;
    private int32 _Splits = 0;
    private int32 _Completions = 0;
    private FVector _FollowerPose;
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach four idle links", n"Step_Arrange");
        Add_Step_WaitUntil("idle seeded placement", n"Check_Ready");
        Add_Step("split idle history behind oldest sample", n"Step_Split");
        Add_Step_WaitUntil("split drained", n"Check_Split");
        Add_Step("verify transfer and move old head", n"Step_OldHead");
        Add_Step_WaitUntil("old chain moved", n"Check_OldMoved");
        Add_Step("assert isolation and move new head", n"Step_NewHead");
        Add_Step_WaitUntil("new head drives transferred follower", n"Check_NewMoved");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        for (int32 Index = 0; Index < 4; ++Index)
        {
            _F.Attach(float32((Index + 1) * 100));
        }
        utils_chain::BindTo_OnLinkDetached(_F.Chain, FCk_Delegate_Chain_OnLinkDetached(this, n"OnDetached"));
        utils_chain::BindTo_OnSplit(_F.Chain, FCk_Delegate_Chain_OnSplit(this, n"OnSplit"));
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(4) && _F.Location(3).Equals(FVector(-400.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Split(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FollowerPose = _F.Location(3);
        _NewChain = utils_chain::Request_Split(_F.Chain, FCk_Request_Chain_Split(_F.Links[2].As_ChainLink()), FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Valid(_NewChain, "new chain immediately valid");
        Assert_Equals_Int(utils_chain::Get_NumLinks(_NewChain), 0, "new roster empty before drain");
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        Assert_True(InResult == ECk_Request_OperationResult::Succeeded, "split succeeds");
    }
    UFUNCTION()
    private void OnDetached(FCk_Handle_Chain InChain, FCk_Chain_Payload_LinkDetached InPayload)
    {
        Assert_True(InPayload.Get_Reason() == ECk_Chain_LinkDetachReason::MovedBySplit, "transfer detach reason");
        ++_Moved;
    }
    UFUNCTION()
    private void OnSplit(FCk_Handle_Chain InChain, FCk_Chain_Payload_Split InPayload)
    {
        Assert_True(InPayload.Get_NewChain() == _NewChain, "split payload new chain");
        Assert_Equals_Int(InPayload.Get_AtIndex(), 2, "split index");
        Assert_Equals_Int(InPayload.Get_MovedLinkCount(), 1, "split moves one follower to new roster");
        ++_Splits;
    }

    UFUNCTION()
    private void Check_Split(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Completions == 1 && _Splits == 1 && utils_chain::Get_NumLinks(_F.Chain) == 2 && utils_chain::Get_NumLinks(_NewChain) == 1);
    }

    UFUNCTION()
    private void Step_OldHead(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Moved, 2, "two transfer detach signals");
        Assert_True(utils_chain::Get_Head(_NewChain) == _F.Links[2], "split link becomes new head");
        Assert_False(utils_chain_link::Has(_F.Links[2]), "new head stops being link");
        Assert_True(utils_chain_link::Get_Chain(_F.Links[3].As_ChainLink()) == _NewChain, "follower belongs to new chain");
        Assert_Equals_Int(utils_chain_link::Get_Index(_F.Links[3].As_ChainLink()), 0, "transferred index compacted");
        Assert_Equals_Float(utils_chain_link::Get_DistanceFromHeadCm(_F.Links[3].As_ChainLink()), 100.0f, 0.01f, "distance rebased");
        _F.Move(FVector(500.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_OldMoved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Location(0).Equals(FVector(400.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_NewHead(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_F.Location(3).Equals(_FollowerPose, 1.0), "old head cannot drive moved follower");
        utils_transform::Request_SetLocation(_F.Links[2], FCk_Request_Transform_SetLocation(FVector(200.0, 0.0, 0.0)));
    }

    UFUNCTION()
    private void Check_NewMoved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Location(3).Equals(FVector(100.0, 0.0, 0.0), 1.0));
        if (_F.Location(3).Equals(FVector(100.0, 0.0, 0.0), 1.0))
        {
            Assert_Equals_Int(_Completions, 1, "split completes only once");
            Assert_Equals_Int(_Splits, 1, "split signal only once");
            FinishSuccess();
        }
    }
}
