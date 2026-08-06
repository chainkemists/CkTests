// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: OnDepleted fires when Consume drains timer
//============================================================================
//
// Pins the OnDepleted broadcast contract (CkTimer_Processor.cpp:263–283):
// OnDepleted fires when Request_Consume causes the timer's elapsed value
// to reach the depleted endpoint of its count direction. For CountUp
// (default), depleted = elapsed clamped to zero.
//
// OnDepleted is NOT broadcast on natural tick completion of a Looping
// timer — that path uses OnDone. OnDepleted is specifically a
// Consume-triggered signal. The original "OnDepleted Loop semantics"
// audit row name turned out to be misleading.
//
// Flow:
//   1. Add a long-goal (10s) running CountUp timer.
//   2. Bind OnDepleted.
//   3. Let it tick naturally for a few frames so elapsed accumulates
//      above 30ms.
//   4. Request_Consume with a duration that exceeds the current elapsed
//      (clamps to zero = depleted).
//   5. Wait a tick for the broadcast to propagate.
//   6. Assert OnDepleted fired exactly once.
//
// Closes the last of four CkTimer audit gaps (after Jump_Backward,
// ForEach_Timer, AddOrReplace).
//============================================================================

class UCk_AutoTest_Timer_OnDepleted_FiresOnConsume : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Timer _Timer;
    private int32 _DepletedCount = 0;
    private bool _ConsumeIssued = false;
    private int32 _TicksAfterConsume = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Timer_Spec(FCk_Time(10.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        _Timer = utils_timer::Add(LocalHandle, Params);
        _Timer.BindTo_OnDepleted(FCk_Delegate_Timer(this, n"OnDepleted"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnDepleted(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _DepletedCount += 1;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_ConsumeIssued == false)
        {
            auto LiveChrono = utils_timer::Get_CurrentTimerValue(_Timer);
            FCk_Time LiveGoal;
            FCk_Time LiveElapsed;
            FCk_Time LiveRemaining;
            LiveChrono.Break_Chrono(LiveGoal, LiveElapsed, LiveRemaining);

            if (LiveElapsed.Get_Milliseconds() > 30)
            {
                // Consume more than the elapsed so far → Consume's clamp
                // drives elapsed to 0 → IsDepleted true → OnDepleted broadcast.
                utils_timer::Request_Consume(_Timer, FCk_Request_Timer_Consume(FCk_Time(5.0f)));
                _ConsumeIssued = true;
            }
            return;
        }

        // Give the broadcast a tick to land on the delegate.
        _TicksAfterConsume += 1;
        if (_TicksAfterConsume < 2) { return; }

        Assert_Equals_Int(_DepletedCount, 1,
            "OnDepleted should fire exactly once after Request_Consume drains the elapsed to zero");

        FinishSuccess();
    }
}
