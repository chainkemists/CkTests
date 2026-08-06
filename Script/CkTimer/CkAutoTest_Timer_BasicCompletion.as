// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: BASIC COMPLETION
//============================================================================
//
// Smoke test for the timer framework. Adds a short Running timer with
// PauseOnDone behavior, binds OnDone, and asserts:
//   - OnDone fires within the timeout
//   - Chrono reports IsDone == true at completion
//   - Elapsed >= Goal
//   - State eventually transitions to Paused (PauseOnDone behavior applied)
//
// NOTE on state polling: PauseOnDone is implemented in the timer processor
// by enqueuing a Request_Pause when the chrono crosses its goal (see
// CkTimer_Processor.cpp). The OnDone signal fires in the same processor pass
// as the pause request is enqueued, but the request itself is consumed by a
// separate handler on a later frame. There is no fixed tick offset we can
// rely on, so this test polls Get_CurrentState() on each tick after OnDone
// and finishes the moment Paused is observed. If the state never flips, the
// harness _TimeoutSeconds catches it as a real failure.
//============================================================================

class UCk_AutoTest_Timer_BasicCompletion : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private bool _DoneObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Timer_Spec(FCk_Time(0.25f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        _Timer = utils_timer::Add(LocalHandle, Params);
        _Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnTimerDone"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTimerDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_DoneObserved) { return; }
        _DoneObserved = true;

        Assert_True(InChrono.Get_IsDone(), "Chrono should report IsDone in OnDone callback");

        auto Goal = FCk_Time();
        auto Elapsed = FCk_Time();
        auto Remaining = FCk_Time();
        InChrono.Break_Chrono(Goal, Elapsed, Remaining);
        Assert_True(Elapsed.Get_Milliseconds() >= Goal.Get_Milliseconds(),
            "Elapsed should be >= Goal at completion");
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (!_DoneObserved) { return; }

        if (_Timer.Get_CurrentState() == ECk_Timer_State::Paused)
        {
            FinishSuccess();
        }
    }
}
