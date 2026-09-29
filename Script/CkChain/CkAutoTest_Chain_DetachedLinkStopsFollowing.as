// Language=angelscript
class UCk_AutoTest_Chain_DetachedLinkStopsFollowing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FTransform _Before;
    private bool _Detached = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach link", n"Step_Arrange");
        Add_Step_WaitUntil("attach drained", n"Check_Ready");
        Add_Step("move first head", n"Step_MoveFirst");
        Add_Step_WaitUntil("first placement", n"Check_First");
        Add_Step("detach with completion", n"Step_Detach");
        Add_Step_WaitUntil("detach completed", n"Check_Detached");
        Add_Step("move old head again", n"Step_MoveAgain");
        Add_Step_WaitUntil("second head write drained", n"Check_HeadMoved");
        Add_Step_WaitSeconds("observe detached hold", 0.1f);
        Add_Step("assert hold", n"Step_Verify");
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
        Res.Set(_F.Ready(1));
    }

    UFUNCTION()
    private void Step_MoveFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Move(FVector(400.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_First(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Location(0).Equals(FVector(300.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Detach(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_chain::Request_DetachLink(_F.Chain, FCk_Request_Chain_DetachLink(_F.Links[0].As_ChainLink()),
            FCk_Delegate_Request_OnCompleted(this, n"OnDetached"));
    }

    UFUNCTION()
    private void OnDetached(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        Assert_True(InResult == ECk_Request_OperationResult::Succeeded, "detach succeeds");
        _Before = utils_transform::Get_EntityCurrentTransform(_F.Links[0]);
        _Detached = true;
    }

    UFUNCTION()
    private void Check_Detached(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Detached);
    }

    UFUNCTION()
    private void Step_MoveAgain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Move(FVector(800.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_HeadMoved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_transform::Get_EntityCurrentLocation(_F.Head).Equals(FVector(800.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_transform::Get_EntityCurrentTransform(_F.Links[0]).Equals(_Before, 0.01), "detached full pose held");
        Assert_Equals_Int(utils_chain::Get_NumLinks(_F.Chain), 0, "empty roster");
        Assert_False(utils_chain_link::Has(_F.Links[0]), "ChainLink feature removed");
        FinishSuccess();
    }
}
