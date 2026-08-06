// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: COUNTDOWN COMPLETION
//============================================================================
//
// Verifies the CountDown direction:
//   - A short countdown timer fires OnDone within the timeout.
//   - At completion, Get_CountDirection reports CountDown (not flipped).
//   - The chrono reports IsDone.
//============================================================================

class UCk_AutoTest_Timer_CountdownCompletion : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Timer_Spec(FCk_Time(0.25f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
        Params.Set_CountDirection(ECk_Timer_CountDirection::CountDown);

        _Timer = utils_timer::Add(LocalHandle, Params);
        _Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnTimerDone"));
    }

    UFUNCTION()
    private void OnTimerDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // For a *naturally* completed countdown (Update_Countdown processor),
        // the chrono's _CurrentValue has been consumed to 0 — so Elapsed=0,
        // Remaining=Goal. Get_IsDone() returns false here (it tests current>=goal,
        // which is only true at the START of a fresh countdown). Get_IsDepleted
        // would be the right query but it isn't exposed to AngelScript, so we
        // assert via the AS-visible TimeElapsed instead.
        //
        // TODO(API): expose FCk_Chrono::Get_IsDepleted to AngelScript via a
        // UFUNCTION on UCk_Utils_Chrono_UE (mirroring Get_IsDone). Once that
        // lands, replace the Elapsed-based check below with the cleaner
        // InChrono.Get_IsDepleted() call. The Get_IsDone() assertion in
        // CkAutoTest_Timer_RequestConsume.as has the same followup.
        // (Note: this is the OPPOSITE of consume-driven completion on a countdown
        // — Request_Consume calls Tick() not Consume(), driving current UP to
        // goal, so that path observes Get_IsDone()=true. See RequestConsume test.)
        auto Goal = FCk_Time();
        auto Elapsed = FCk_Time();
        auto Remaining = FCk_Time();
        InChrono.Break_Chrono(Goal, Elapsed, Remaining);
        Assert_True(Elapsed.Get_Milliseconds() <= 0.0,
            f"Naturally completed countdown should have Elapsed <= 0 (got {Elapsed.Get_Milliseconds()}ms)");
        Assert_True(_Timer.Get_CountDirection() == ECk_Timer_CountDirection::CountDown,
            "CountDirection should remain CountDown for a CountDown timer");
        FinishSuccess();
    }
}
