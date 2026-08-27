// Language=angelscript

//============================================================================
// CK TIMER - AUTOMATION TEST: REQUEST COMPLETION SUCCEEDS ON DRAIN
//============================================================================
//
// A Request_* that carries a completion delegate must fire it exactly once
// with Succeeded, on the request's owner, AFTER the request was processed:
//   1. Add a running timer.
//   2. Request_Pause with a completion delegate.
//   3. On completion assert Succeeded, owner match, and that the timer is
//      observably Paused (proving the fire is post-processing).
//   4. Settle one more frame and assert the delegate fired exactly once.
//============================================================================

class UCk_AutoTest_Timer_RequestCompletion_SucceedsOnDrain : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Timer _Timer;
    private int _FireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(60.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);

        _Timer = utils_timer::Add(LocalHandle, Params);

        utils_timer::Request_Pause(_Timer, FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _FireCount += 1;

        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"A drained request must complete with Succeeded (got {InResult})");

        Assert_True(InRequestOwner == _Timer,
            "Completion must report the request's owner entity");

        Assert_True(_Timer.Get_CurrentState() == ECk_Timer_State::Paused,
            "Completion must fire after the request was processed (timer observably Paused)");

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 1, "Completion delegate must fire exactly once");

        FinishSuccess();
    }
}
