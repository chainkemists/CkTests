// Language=angelscript
class UCk_AutoTest_Chain_AttachInvalidLinkNotEnqueued : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FCk_ChainAutoTestFixture _Other;
    private FVector _OtherHead;
    private FTransform _OtherPose;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("create independent bystander", n"Step_Arrange");
        Add_Step_WaitUntil("bystander attached and settled", n"Check_Ready");
        Add_Step("reject invalid link", n"Step_Reject");
        Add_Step_WaitSeconds("observe rejection window", 0.1f);
        Add_Step("assert independent bystander unchanged", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _Other.Init(InHandle);
        _Other.Attach(100.0f);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Other.Ready(1) && _Other.Location(0).Equals(FVector(-100.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Reject(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _OtherHead = utils_transform::Get_EntityCurrentLocation(_Other.Head);
        _OtherPose = utils_transform::Get_EntityCurrentTransform(_Other.Links[0]);
        auto Invalid = FCk_Handle_Transform();
        utils_chain::Request_AttachLink(_F.Chain, FCk_Request_Chain_AttachLink(Invalid, FCk_ChainLink_Spec(100.0f)), FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Completions, 1, "invalid rejection is synchronous");
        Assert_True(_Result == ECk_Request_OperationResult::Failed_NotEnqueued, "invalid request not enqueued");
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
        Assert_True(InOwner == _F.Chain, "completion identifies request owner");
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "completion exactly once");
        Assert_Equals_Int(utils_chain::Get_NumLinks(_F.Chain), 0, "request owner remains empty");
        Assert_Equals_Int(utils_chain::Get_NumLinks(_Other.Chain), 1, "independent bystander roster unchanged");
        Assert_True(utils_chain::Get_Head(_Other.Chain) == _Other.Head, "bystander head identity unchanged");
        Assert_True(utils_transform::Get_EntityCurrentLocation(_Other.Head).Equals(_OtherHead, 0.01), "bystander head pose unchanged");
        Assert_True(utils_transform::Get_EntityCurrentTransform(_Other.Links[0]).Equals(_OtherPose, 0.01), "bystander link pose unchanged");
        Assert_True(utils_chain_link::Get_Chain(_Other.Links[0].As_ChainLink()) == _Other.Chain, "bystander membership unchanged");
        FinishSuccess();
    }
}

class ACk_AutoTest_Chain_AttachInvalidLinkNotEnqueued_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Chain_AttachInvalidLinkNotEnqueued;
    default _TimeoutSeconds = 6.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Chain AttachLink rejected invalid link");
        return Errors;
    }
}
