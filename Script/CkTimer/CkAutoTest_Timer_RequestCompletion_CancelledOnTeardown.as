// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: REQUEST COMPLETION CANCELLED ON TEARDOWN
//============================================================================
//
// A request enqueued on a timer that is destroyed before it can be processed
// must complete with Failed_Cancelled (the EndPlay cancel drain), so a caller
// awaiting completion terminates instead of hanging. HandleRequests excludes
// owners tagged FTag_DestroyEntity_Initiate, leaving the queued request to
// FProcessor_Timer_CancelPendingRequests in FGroup_EndPlay.
//============================================================================

class UCk_AutoTest_Timer_RequestCompletion_CancelledOnTeardown : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Timer _Timer;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = FCk_Timer_Spec(FCk_Time(60.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);

        _Timer = utils_timer::Add(LocalHandle, Params);

        utils_timer::Request_Pause(_Timer, FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));

        FCk_Handle TimerEntity = _Timer;
        utils_entity_lifetime::Request_DestroyEntity(TimerEntity);
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Request_OperationResult::Failed_Cancelled,
            f"A request whose owner is destroyed before draining must complete with Failed_Cancelled (got {InResult})");

        FinishSuccess();
    }
}
