// Language=angelscript

//============================================================================
// CK TIMER - AUTOMATION TEST: JUMP FORWARD
//============================================================================
//
// Pins Request_Jump on a CountUp timer:
//   1. Start a long-goal timer (10s) so natural completion can't happen in
//      the test window.
//   2. Wait a few ticks for some elapsed time to accumulate.
//   3. Capture pre-jump value.
//   4. Request_Jump with a positive FCk_Time delta.
//   5. Read post-jump value; assert it's >= pre-jump value + jump delta
//      (allowing for one more tick of normal elapsed advance between the
//      capture and the post-jump read).
//
// Note: only forward jumps are covered here. The backward variant requires
// either a negative FCk_Time or a separate JumpDirection field; the audit
// gap "Jump_ForwardAndBackward" deserves a second test once we confirm the
// API shape (FCk_Time sign vs. enum direction) - splitting them keeps each
// test focused on a single semantic.
//============================================================================

class UCk_AutoTest_Timer_Jump_Forward : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Timer _Timer;
    private int32 _ElapsedMsBeforeJump = 0;
    private FCk_Time _JumpDelta;
    private bool _JumpDone = false;
    private int32 _TicksAfterJump = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        _Timer = utils_timer::Add(LocalHandle, Params);
        _JumpDelta = FCk_Time(2.0f);
        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_JumpDone == false)
        {
            auto LiveChrono = utils_timer::Get_CurrentTimerValue(_Timer);
            FCk_Time LiveGoal;
            FCk_Time LiveElapsed;
            FCk_Time LiveRemaining;
            LiveChrono.Break_Chrono(LiveGoal, LiveElapsed, LiveRemaining);

            if (LiveElapsed.Get_Milliseconds() > 30)
            {
                _ElapsedMsBeforeJump = int32(LiveElapsed.Get_Milliseconds());
                utils_timer::Request_Jump(_Timer, FCk_Request_Timer_Jump(_JumpDelta));
                _JumpDone = true;
            }
            return;
        }

        _TicksAfterJump += 1;
        if (_TicksAfterJump < 2) { return; }

        auto NowChrono = utils_timer::Get_CurrentTimerValue(_Timer);
        FCk_Time NowGoal;
        FCk_Time NowElapsed;
        FCk_Time NowRemaining;
        NowChrono.Break_Chrono(NowGoal, NowElapsed, NowRemaining);
        auto ExpectedAtLeast = _ElapsedMsBeforeJump + _JumpDelta.Get_Milliseconds();
        Assert_True(NowElapsed.Get_Milliseconds() >= ExpectedAtLeast,
            f"After Request_Jump(+{_JumpDelta.Get_Milliseconds()}ms) from {_ElapsedMsBeforeJump}ms, elapsed must be >= {ExpectedAtLeast}ms (got {NowElapsed.Get_Milliseconds()}ms)");

        FinishSuccess();
    }
}
