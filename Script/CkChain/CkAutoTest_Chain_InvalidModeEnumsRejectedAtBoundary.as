// Language=angelscript
class UCk_AutoTest_Chain_InvalidModeEnumsRejectedAtBoundary : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FCk_Handle_Transform _RejectedHead;
    private FCk_Handle_Chain _RejectedChain;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("reject invalid solver and orientation", n"Step_Reject");
        Add_Step_WaitSeconds("exclude delayed composition", 0.1f);
        Add_Step("assert nothing composed", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Reject(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _RejectedHead = _F.Spawn(FVector(0.0, 300.0, 0.0));
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        _RejectedChain = utils_chain::Add(_RejectedHead, FCk_Chain_Spec(ECk_Chain_Solver(255)));
        Assert_Invalid(_RejectedChain, "invalid solver Add returns an invalid chain synchronously");

        auto InvalidSeed = FCk_Chain_Spec(ECk_Chain_Solver::PathHistory);
        InvalidSeed.Set_HistorySeed(ECk_Chain_HistorySeed(255));
        Assert_Invalid(utils_chain::Add(_RejectedHead, InvalidSeed), "invalid history seed is rejected");

        auto InvalidNetPolicy = FCk_Chain_Spec(ECk_Chain_Solver::PathHistory);
        InvalidNetPolicy.Set_NetPolicy(ECk_Chain_NetPolicy(255));
        Assert_Invalid(utils_chain::Add(_RejectedHead, InvalidNetPolicy), "invalid net policy is rejected");

        auto InvalidStartingState = FCk_Chain_Spec(ECk_Chain_Solver::PathHistory);
        InvalidStartingState.Set_StartingState(ECk_EnableDisable(255));
        Assert_Invalid(utils_chain::Add(_RejectedHead, InvalidStartingState), "invalid starting state is rejected");
        Assert_True(utils_ensure::Get_EnsureCount() == EnsuresBefore + 4, "each rejected Spec diagnoses once");

        auto Link = _F.Spawn(FVector(0.0, 500.0, 0.0));
        _F.Links.Add(Link);
        auto LinkSpec = FCk_ChainLink_Spec(100.0f);
        LinkSpec.Set_Orientation(ECk_Chain_LinkOrientation(255));
        utils_chain::Request_AttachLink(_F.Chain, FCk_Request_Chain_AttachLink(Link, LinkSpec),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Completions, 1, "invalid orientation rejection is synchronous");
        Assert_True(_Result == ECk_Request_OperationResult::Failed_NotEnqueued, "invalid orientation is not enqueued");
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_chain::Has_Any(_RejectedHead), "invalid solver leaves no chain record on its head");
        Assert_Equals_Int(utils_chain::Get_NumLinks(_F.Chain), 0, "invalid orientation composes no link");
        Assert_False(utils_chain_link::Has(_F.Links[0]), "rejected link carries no chain fragments");
        Assert_Equals_Int(_Completions, 1, "completion exactly once");
        FinishSuccess();
    }
}

class ACk_AutoTest_Chain_InvalidModeEnumsRejectedAtBoundary_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Chain_InvalidModeEnumsRejectedAtBoundary;
    default _TimeoutSeconds = 6.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Chain Add rejected invalid parameters");
        Errors.Add("Chain AttachLink rejected incompatible link or parameters");
        return Errors;
    }
}
