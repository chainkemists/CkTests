// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: ENABLE/DISABLE ON AN INVALID HANDLE IS REJECTED, NOT ENQUEUED
//============================================================================
//
// The validation boundary of Request_EnableDisable. An invalid handle must be rejected at the Utils
// boundary with Failed_NotEnqueued, delivered synchronously and exactly once, and must not disturb
// a valid agent that exists alongside it.
//============================================================================

class UCk_AutoTest_Crowd_Disable_InvalidHandleNotEnqueued : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_CrowdAgent _Bystander;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Succeeded;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(           "reject an Enable/Disable addressed to an invalid handle",
                            n"Step_RejectInvalid");
        Add_Step_WaitFrames("let any stray drain run", 3);
        Add_Step(           "exactly one Failed_NotEnqueued, and the bystander untouched",
                            n"Step_Verify");

        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_RejectInvalid(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 100.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _Bystander = utils_crowd_agent::Add(AgentTransform, FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f));

        auto Invalid = FCk_Handle_CrowdAgent();
        utils_crowd_agent::Request_EnableDisable(Invalid,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));

        Assert_True(_Completions == 1,
            f"the rejection must complete synchronously, before Request_EnableDisable returns (completions={_Completions})");
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Completions == 1,
            f"the rejected request completed {_Completions} times - the contract is exactly once");

        Assert_True(_Result == ECk_Request_OperationResult::Failed_NotEnqueued,
            f"an invalid handle completed {_Result}, not Failed_NotEnqueued");

        Assert_True(utils_crowd_agent::Get_IsEnabled(_Bystander),
            "a rejected request addressed to an invalid handle disabled an unrelated agent");

        Assert_True(!utils_crowd_agent::Get_IsEnabled(FCk_Handle_CrowdAgent()),
            "Get_IsEnabled on an invalid handle must read false, not report a body that does not exist");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }
}

class ACk_AutoTest_Crowd_Disable_InvalidHandleNotEnqueued_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Disable_InvalidHandleNotEnqueued;
    default _TimeoutSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        // The rejection under test is a CK_ENSURE at the Utils boundary.
        Out.Add("passed to Request_EnableDisable");
        return Out;
    }
}
