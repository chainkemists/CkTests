// Language=angelscript
class UCk_AutoTest_Chain_ChainDestroyedReleasesLinksAndKeepsPose : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private int32 _DetachedCount = 0;
    private TArray<FTransform> _Before;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach two links", n"Step_Arrange");
        Add_Step_WaitUntil("links placed", n"Check_Ready");
        Add_Step("destroy chain", n"Step_Destroy");
        Add_Step_WaitUntil("chain teardown finished", n"Check_Released");
        Add_Step_WaitSeconds("observe released pose hold", 0.1f);
        Add_Step("assert release", n"Step_Verify");
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
        Res.Set(_F.Ready(2) && _F.Location(0).Equals(FVector(-100.0, 0.0, 0.0), 1.0) && _F.Location(1).Equals(FVector(-200.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Link : _F.Links)
        {
            _Before.Add(utils_transform::Get_EntityCurrentTransform(Link));
        }
        FCk_Handle ChainEntity = _F.Chain;
        utils_entity_lifetime::Request_DestroyEntity(ChainEntity);
    }

    UFUNCTION()
    private void OnDetached(FCk_Handle_Chain InChain, FCk_Chain_Payload_LinkDetached InPayload)
    {
        Assert_True(InChain == _F.Chain, "detach signal identifies source");
        Assert_True(InPayload.Get_Reason() == ECk_Chain_LinkDetachReason::ChainDestroyed, "detach reason");
        ++_DetachedCount;
    }

    UFUNCTION()
    private void Check_Released(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::Is_NOT_Valid(_F.Chain) && _DetachedCount == 2 && !utils_chain_link::Has(_F.Links[0]) && !utils_chain_link::Has(_F.Links[1]));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_DetachedCount, 2, "each link receives ChainDestroyed");
        for (int32 Index = 0; Index < 2; ++Index)
        {
            Assert_Valid(_F.Links[Index], "link survives chain destruction");
            Assert_True(utils_transform::Get_EntityCurrentTransform(_F.Links[Index]).Equals(_Before[Index], 0.01), "released full pose retained");
        }
        FinishSuccess();
    }
}
