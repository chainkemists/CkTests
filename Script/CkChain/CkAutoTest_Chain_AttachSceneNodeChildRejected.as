// Language=angelscript
class UCk_AutoTest_Chain_AttachSceneNodeChildRejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private FCk_Handle _CompletionOwner;
    private FCk_Handle_Transform _Child;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("reject parented link", n"Step_Arrange");
        Add_Step_WaitSeconds("exclude delayed composition", 0.1f);
        Add_Step("assert no fragments", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        auto ChildNode = utils_scene_node::Create(_F.Head, FTransform(FRotator::ZeroRotator, FVector(0.0, 50.0, 0.0), FVector::OneVector));
        _Child = ChildNode.As_Transform();
        utils_chain::Request_AttachLink(_F.Chain, FCk_Request_Chain_AttachLink(_Child,
            FCk_ChainLink_Spec(100.0f)), FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Completions, 1, "SceneNode child rejected synchronously");
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
        Assert_True(_Result == ECk_Request_OperationResult::Failed_NotEnqueued, "parented link not enqueued");
        Assert_Equals_Int(_Completions, 1, "rejection exactly once");
        Assert_False(utils_chain_link::Has(_Child), "no ChainLink fragments composed");
        Assert_Equals_Int(utils_chain::Get_NumLinks(_F.Chain), 0, "roster unchanged");
        FinishSuccess();
    }
}

class ACk_AutoTest_Chain_AttachSceneNodeChildRejected_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Chain_AttachSceneNodeChildRejected;
    default _TimeoutSeconds = 6.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Chain AttachLink rejected incompatible link or parameters");
        return Errors;
    }
}

