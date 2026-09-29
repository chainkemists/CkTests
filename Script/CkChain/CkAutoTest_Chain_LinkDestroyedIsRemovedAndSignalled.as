// Language=angelscript
class UCk_AutoTest_Chain_LinkDestroyedIsRemovedAndSignalled : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private int32 _DetachedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach two links", n"Step_Arrange");
        Add_Step_WaitUntil("both attached", n"Check_Ready");
        Add_Step("destroy first link", n"Step_Destroy");
        Add_Step_WaitUntil("prune and signal observed", n"Check_Pruned");
        Add_Step("move surviving link", n"Step_Move");
        Add_Step_WaitUntil("survivor follows", n"Check_Follows");
        Add_Step("assert compact roster", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(100.0f);
        _F.Attach(200.0f);
        utils_chain::BindTo_OnLinkDetached(_F.Chain, FCk_Delegate_Chain_OnLinkDetached(this, n"OnDetached"));
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(2));
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Handle LinkEntity = _F.Links[0];
        utils_entity_lifetime::Request_DestroyEntity(LinkEntity);
    }

    UFUNCTION()
    private void OnDetached(FCk_Handle_Chain InChain, FCk_Chain_Payload_LinkDetached InPayload)
    {
        Assert_True(InChain == _F.Chain, "detach signal identifies source");
        Assert_True(InPayload.Get_Reason() == ECk_Chain_LinkDetachReason::LinkDestroyed, "detach reason");
        ++_DetachedCount;
    }

    UFUNCTION()
    private void Check_Pruned(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DetachedCount == 1 && utils_chain::Get_NumLinks(_F.Chain) == 1 && ck::Is_NOT_Valid(_F.Links[0]));
    }

    UFUNCTION()
    private void Step_Move(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Move(FVector(500.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_Follows(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Location(1).Equals(FVector(300.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_DetachedCount, 1, "one destroyed-link signal");
        Assert_Equals_Int(utils_chain_link::Get_Index(_F.Links[1].As_ChainLink()), 0, "survivor index compacted");
        Assert_True(_F.Location(1).Equals(FVector(300.0, 0.0, 0.0), 1.0), "survivor still follows");
        FinishSuccess();
    }
}
