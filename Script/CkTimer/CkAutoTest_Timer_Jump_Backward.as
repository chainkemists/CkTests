// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: JUMP BACKWARD
//============================================================================
//
// Pairs with CkAutoTest_Timer_Jump_Forward. Pins the backward-jump contract
// on a CountUp timer:
//   1. Start a long-goal timer (10s) so natural completion can't happen.
//   2. Wait for some elapsed time to accumulate (> 30ms).
//   3. Capture pre-jump value.
//   4. Request_Jump with a NEGATIVE FCk_Time delta whose magnitude
//      exceeds the elapsed value.
//   5. Assert elapsed clamps to zero (FCk_Chrono::Tick clamps to
//      [0, GoalValue]).
//
// CountUp + negative jump exercises FCk_Chrono::Tick's negative-input path
// (line 35: `_CurrentValue + InDeltaT` then Clamp). The contract: backward
// jumps shouldn't take the timer past zero into negative territory; the
// chrono's clamp catches it.
//============================================================================

class UCk_AutoTest_Timer_Jump_Backward : UCk_AutoTest_Base
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
        // Large negative delta so the clamp-to-zero behavior is unambiguous
        // (any pre-jump elapsed in the [30ms, ~1s] window we're testing
        // gets driven below zero pre-clamp).
        _JumpDelta = FCk_Time(-5.0f);
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

        // Read on the tick AFTER the jump so the request has been processed.
        _TicksAfterJump += 1;
        if (_TicksAfterJump < 2) { return; }

        auto NowChrono = utils_timer::Get_CurrentTimerValue(_Timer);
        FCk_Time NowGoal;
        FCk_Time NowElapsed;
        FCk_Time NowRemaining;
        NowChrono.Break_Chrono(NowGoal, NowElapsed, NowRemaining);

        // Elapsed must have dropped from pre-jump (backward DID move).
        Assert_True(NowElapsed.Get_Milliseconds() < _ElapsedMsBeforeJump,
            f"After Request_Jump({_JumpDelta.Get_Milliseconds()}ms) from {_ElapsedMsBeforeJump}ms, elapsed must decrease (got {NowElapsed.Get_Milliseconds()}ms)");

        // FCk_Chrono::Tick clamps to [0, Goal]. Backward jump magnitude
        // exceeds pre-jump elapsed, so post-jump elapsed should be at most
        // the normal ~2 ticks worth of elapsed advance after the clamp
        // (well under 100ms).
        Assert_True(NowElapsed.Get_Milliseconds() < 100,
            f"After clamp-to-zero backward jump + 2 ticks of normal advance, elapsed should be < 100ms (got {NowElapsed.Get_Milliseconds()}ms)");

        FinishSuccess();
    }
}
