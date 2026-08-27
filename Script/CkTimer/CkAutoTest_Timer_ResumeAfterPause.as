// Language=angelscript

//============================================================================
// CK TIMER - AUTOMATION TEST: RESUME AFTER PAUSE
//============================================================================
//
// Verifies that Request_Resume restarts chrono accumulation after a pause:
//   1. Start a long-goal timer, pause it once it's running.
//   2. Snapshot elapsed once Paused state is observed.
//   3. Request_Resume.
//   4. Wait until state == Running, then verify elapsed has advanced past
//      the snapshot.
//============================================================================

class UCk_AutoTest_Timer_ResumeAfterPause : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private bool _PauseRequested = false;
    private bool _PauseObserved = false;
    private bool _ResumeRequested = false;
    private double _ElapsedAtPauseMs = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

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

        if (!_PauseRequested)
        {
            auto Elapsed = _Timer.Get_CurrentTimerValue().Get_TimeElapsed();
            if (Elapsed.Get_Milliseconds() > 0.0)
            {
                _Timer.Request_Pause();
                _PauseRequested = true;
            }
            return;
        }

        if (!_PauseObserved)
        {
            if (_Timer.Get_CurrentState() == ECk_Timer_State::Paused)
            {
                _ElapsedAtPauseMs = _Timer.Get_CurrentTimerValue().Get_TimeElapsed().Get_Milliseconds();
                _PauseObserved = true;
            }
            return;
        }

        if (!_ResumeRequested)
        {
            _Timer.Request_Resume();
            _ResumeRequested = true;
            return;
        }

        if (_Timer.Get_CurrentState() == ECk_Timer_State::Running)
        {
            auto NowMs = _Timer.Get_CurrentTimerValue().Get_TimeElapsed().Get_Milliseconds();
            if (NowMs > _ElapsedAtPauseMs)
            {
                Assert_True(NowMs > _ElapsedAtPauseMs,
                    f"Resumed timer should advance past pause snapshot ({_ElapsedAtPauseMs}ms -> {NowMs}ms)");
                FinishSuccess();
            }
        }
    }
}
