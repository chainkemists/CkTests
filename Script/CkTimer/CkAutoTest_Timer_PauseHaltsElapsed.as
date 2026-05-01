// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: PAUSE HALTS ELAPSED
//============================================================================
//
// Verifies that Request_Pause stops chrono accumulation:
//   1. Start a long-goal timer Running (so it never naturally completes).
//   2. After a few ticks of progress, Request_Pause.
//   3. Wait until state == Paused.
//   4. Snapshot elapsed.
//   5. Wait additional ticks; assert elapsed has not advanced.
//
// This is the most direct test that pause actually halts time accumulation
// rather than just flipping the state label.
//============================================================================

class UCk_AutoTest_Timer_PauseHaltsElapsed : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private bool _PauseRequested = false;
    private bool _ElapsedSnapshotted = false;
    private double _ElapsedAtPauseMs = 0.0;
    private int32 _TicksSinceSnapshot = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // Long goal so the timer never completes during the test.
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

        // Step 1: let the timer run a couple of ticks, then request pause.
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

        // Step 2: wait until the pause request has been processed.
        if (!_ElapsedSnapshotted)
        {
            if (_Timer.Get_CurrentState() == ECk_Timer_State::Paused)
            {
                _ElapsedAtPauseMs = _Timer.Get_CurrentTimerValue().Get_TimeElapsed().Get_Milliseconds();
                _ElapsedSnapshotted = true;
            }
            return;
        }

        // Step 3: confirm elapsed does not advance over several subsequent ticks.
        _TicksSinceSnapshot++;
        if (_TicksSinceSnapshot >= 5)
        {
            auto NowMs = _Timer.Get_CurrentTimerValue().Get_TimeElapsed().Get_Milliseconds();
            Assert_True(NowMs == _ElapsedAtPauseMs,
                f"Paused timer's elapsed should not advance (snapshot {_ElapsedAtPauseMs}ms, now {NowMs}ms)");
            FinishSuccess();
        }
    }
}
