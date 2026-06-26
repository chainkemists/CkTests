// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: MULTIPLE CONCURRENT TIMERS
//============================================================================
//
// Verifies that multiple timers on the same entity tick independently and
// fire OnDone in goal-order:
//   1. Add Timer A with goal 0.10s and Timer B with goal 0.30s.
//   2. Bind separate OnDone delegates on each.
//   3. Both fire; the short timer's callback fires before the long one's.
//   4. After both fire, FinishSuccess.
//
// Catches the regression where multiple timers on one entity interfere
// with each other (e.g. Timer A's chrono accidentally drives Timer B).
//============================================================================

class UCk_AutoTest_Timer_MultipleConcurrent : UCk_AutoTest_Base
{
    private bool _ShortFired = false;
    private bool _LongFired = false;
    private bool _ShortFiredFirst = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ShortParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.10f));
        ShortParams.Set_StartingState(ECk_Timer_State::Running);
        ShortParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
        auto ShortTimer = utils_timer::Add(LocalHandle, ShortParams);
        ShortTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnShortDone"));

        auto LongParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.30f));
        LongParams.Set_StartingState(ECk_Timer_State::Running);
        LongParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
        auto LongTimer = utils_timer::Add(LocalHandle, LongParams);
        LongTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnLongDone"));
    }

    UFUNCTION()
    private void OnShortDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ShortFired = true;
        if (!_LongFired) { _ShortFiredFirst = true; }
        TryFinish();
    }

    UFUNCTION()
    private void OnLongDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _LongFired = true;
        TryFinish();
    }

    private void TryFinish()
    {
        if (!_ShortFired || !_LongFired) { return; }

        Assert_True(_ShortFired, "Short timer (0.10s) should fire");
        Assert_True(_LongFired, "Long timer (0.30s) should fire");
        Assert_True(_ShortFiredFirst,
            "Short timer should fire before long timer");

        FinishSuccess();
    }
}
