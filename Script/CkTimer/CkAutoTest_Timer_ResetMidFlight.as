// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: RESET MID-FLIGHT
//============================================================================
//
// Verifies Request_Reset rewinds elapsed time back to zero on a running
// timer:
//   1. Add a long-goal Running timer (60s — never naturally completes
//      within the harness window).
//   2. Wait for elapsed > 200ms (well past one frame).
//   3. Snapshot elapsed.
//   4. Issue Request_Reset.
//   5. Poll until elapsed drops back to zero (or strictly less than the
//      pre-reset snapshot).
//   6. Assert.
//
// Catches the regression where Reset is silently dropped or only resets
// part of the state. Pairs with Timer_PauseHaltsElapsed and
// Timer_ResumeAfterPause to cover the runtime-control surface.
//============================================================================

class UCk_AutoTest_Timer_ResetMidFlight : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private bool _ResetRequested = false;
    private double _ElapsedAtResetMs = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Long goal so natural completion can't happen during the test window.
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(60.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        _Timer = utils_timer::Add(LocalHandle, Params);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!_ResetRequested)
        {
            // Accumulate well past one frame of elapsed time before resetting —
            // the post-reset dip below the snapshot then stays observable for
            // many frames regardless of timer update iteration order.
            auto Elapsed = _Timer.Get_CurrentTimerValue().Get_TimeElapsed();
            if (Elapsed.Get_Milliseconds() > 200.0)
            {
                _ElapsedAtResetMs = Elapsed.Get_Milliseconds();
                _Timer.Request_Reset();
                _ResetRequested = true;
            }
            return;
        }

        // After the reset request, poll until elapsed has dropped below
        // the snapshot — that confirms the reset took effect.
        auto NowMs = _Timer.Get_CurrentTimerValue().Get_TimeElapsed().Get_Milliseconds();
        if (NowMs < _ElapsedAtResetMs)
        {
            Assert_True(NowMs < _ElapsedAtResetMs,
                f"Elapsed should drop after Reset (snapshot {_ElapsedAtResetMs}ms, now {NowMs}ms)");
            FinishSuccess();
        }
    }
}
