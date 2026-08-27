// Language=angelscript

//============================================================================
// CK TIMER - AUTOMATION TEST: GET_CURRENTTIMERVALUE DURING PAUSE
//============================================================================
//
// Pins Get_CurrentTimerValue's pause semantic: while a timer is Paused, the
// reported value must NOT advance with world-time. Reading it at frame N
// during pause must return the same value as reading at frame N+K (for any
// K) while the pause is unbroken.
//
// We start a long timer, let it tick for several frames, pause it, capture
// the value, then wait additional frames and verify the value hasn't moved.
//
// Note: paired with the existing Timer_PauseHaltsElapsed test which pins
// the chrono's _Elapsed field; this test pins the Utils-exposed
// Get_CurrentTimerValue accessor specifically.
//============================================================================

class UCk_AutoTest_Timer_Get_CurrentTimerValue_DuringPause : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Timer _Timer;
    private int32 _ElapsedMsAtPause = 0;
    private int32 _TicksSincePause = 0;
    private bool _Paused = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        _Timer = utils_timer::Add(LocalHandle, Params);
        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_Paused == false)
        {
            // Let it tick a few frames before pausing.
            auto LiveChrono = utils_timer::Get_CurrentTimerValue(_Timer);
            FCk_Time LiveGoal;
            FCk_Time LiveElapsed;
            FCk_Time LiveRemaining;
            LiveChrono.Break_Chrono(LiveGoal, LiveElapsed, LiveRemaining);

            if (LiveElapsed.Get_Milliseconds() > 30)
            {
                _Paused = true;
                _Timer.Request_Pause();

                auto AtPauseChrono = utils_timer::Get_CurrentTimerValue(_Timer);
                FCk_Time AtPauseGoal;
                FCk_Time AtPauseElapsed;
                FCk_Time AtPauseRemaining;
                AtPauseChrono.Break_Chrono(AtPauseGoal, AtPauseElapsed, AtPauseRemaining);
                _ElapsedMsAtPause = int32(AtPauseElapsed.Get_Milliseconds());
            }
            return;
        }

        _TicksSincePause += 1;
        if (_TicksSincePause < 5) { return; }

        auto NowChrono = utils_timer::Get_CurrentTimerValue(_Timer);
        FCk_Time NowGoal;
        FCk_Time NowElapsed;
        FCk_Time NowRemaining;
        NowChrono.Break_Chrono(NowGoal, NowElapsed, NowRemaining);
        Assert_Equals_Int(int32(NowElapsed.Get_Milliseconds()), _ElapsedMsAtPause,
            "Get_CurrentTimerValue must not advance while Paused");

        FinishSuccess();
    }
}
