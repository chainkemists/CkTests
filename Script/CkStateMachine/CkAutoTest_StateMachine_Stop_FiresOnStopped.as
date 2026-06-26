// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: STOP FIRES ON_STOPPED
//============================================================================
//
// Pins Request_Stop's contract on a running SM:
//   - OnStopped delegate fires with the SM handle.
//   - Get_RunStatus reports ECk_SmRunStatus::Stopped after OnStopped fires.
//
// Setup: standard Idle->Patrol->Alert test SM. We bind OnStopped, wait
// for the SM to settle into its initial state (Idle), then issue
// Request_Stop. The OnStopped delegate finishes the test.
//============================================================================

class UCk_AutoTest_StateMachine_Stop_FiresOnStopped : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_StateMachine _SmHandle;
    private bool _StopRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmTest_State_Idle));

        FCk_Delegate_Sm_OnStopped StoppedDelegate;
        StoppedDelegate.BindUFunction(this, n"OnStopped");
        utils_state_machine::BindTo_OnStopped(_SmHandle, StoppedDelegate);

        // Issue Stop on a slight delay so the SM has time to enter the initial state.
        System::SetTimer(this, n"DoRequestStop", 0.5f, false);
    }

    UFUNCTION()
    private void DoRequestStop()
    {
        if (IsFinished()) { return; }
        _StopRequested = true;
        utils_state_machine::Request_Stop(_SmHandle);
    }

    UFUNCTION()
    private void OnStopped(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStopped InPayload)
    {
        if (IsFinished()) { return; }

        Assert_True(_StopRequested,
            "OnStopped should fire only after the explicit Request_Stop");

        // Check the run status reflects the stop. Run-status update is processed
        // in the same pass as OnStopped fires; if there's a one-frame lag the
        // assertion needs a WaitOneFrame, but try the synchronous read first.
        auto Status = utils_state_machine::Get_RunStatus(_SmHandle);
        Assert_True(Status == ECk_SmRunStatus::Stopped,
            f"After Request_Stop and OnStopped fire, Get_RunStatus must report Stopped (got {Status})");

        FinishSuccess();
    }
}
