// Language=angelscript
class UCk_AutoTest_Chain_DisabledChainHoldsLinks : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FTransform _Before;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach link", n"Step_Arrange");
        Add_Step_WaitUntil("seed placement", n"Check_Ready");
        Add_Step("disable chain", n"Step_Disable");
        Add_Step_WaitUntil("disable drained", n"Check_Disabled");
        Add_Step("move head while disabled", n"Step_Move");
        Add_Step_WaitUntil("head movement drained", n"Check_HeadMoved");
        Add_Step_WaitSeconds("observe disabled hold", 0.1f);
        Add_Step("assert hold and enable", n"Step_Enable");
        Add_Step_WaitUntil("placement resumed", n"Check_Resumed");
        Add_Step("assert resumed", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(100.0f);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1) && _F.Location(0).Equals(FVector(-100.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Disable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Before = utils_transform::Get_EntityCurrentTransform(_F.Links[0]);
        utils_chain::Request_EnableDisable(_F.Chain, FCk_Request_Chain_EnableDisable(ECk_EnableDisable::Disable), FCk_Delegate_Request_OnCompleted());
    }

    UFUNCTION()
    private void Check_Disabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(!utils_chain::Get_IsEnabled(_F.Chain));
    }

    UFUNCTION()
    private void Step_Move(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Move(FVector(500.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_HeadMoved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_transform::Get_EntityCurrentLocation(_F.Head).Equals(FVector(500.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Enable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_transform::Get_EntityCurrentTransform(_F.Links[0]).Equals(_Before, 0.01), "disabled links hold full pose");
        utils_chain::Request_EnableDisable(_F.Chain, FCk_Request_Chain_EnableDisable(ECk_EnableDisable::Enable), FCk_Delegate_Request_OnCompleted());
    }

    UFUNCTION()
    private void Check_Resumed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_chain::Get_IsEnabled(_F.Chain) && _F.Location(0).Equals(FVector(400.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_F.Location(0).Equals(FVector(400.0, 0.0, 0.0), 1.0), "enable places links");
        FinishSuccess();
    }
}
