// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: RESET-ON-DONE BEHAVIOR
//============================================================================
//
// Verifies the ResetOnDone behavior: after a Running timer hits its goal,
// the processor enqueues Request_Reset, the chrono restarts at 0, and the
// timer continues running. We observe this by counting OnDone fires across
// multiple cycles — a single fire could be ResetOnDone OR PauseOnDone OR
// StopOnDone, but two fires unambiguously means the timer auto-restarted.
//============================================================================

class UCk_AutoTest_Timer_ResetOnDone : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private int32 _DoneCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Timer_Spec(FCk_Time(0.15f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::ResetOnDone);

        _Timer = utils_timer::Add(LocalHandle, Params);
        _Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnTimerDone"));
    }

    UFUNCTION()
    private void OnTimerDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _DoneCount++;

        if (_DoneCount >= 2)
        {
            Assert_True(_DoneCount >= 2, "ResetOnDone timer should fire OnDone repeatedly");
            FinishSuccess();
        }
    }
}
