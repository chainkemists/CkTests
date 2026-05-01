// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: REQUEST COMPLETE
//============================================================================
//
// Verifies that Request_Complete fires OnDone immediately rather than
// waiting for the chrono to reach its goal naturally. The timer is created
// with a long goal that would take longer than the harness timeout to
// complete on its own — so if OnDone fires within the timeout, it must
// have come from the explicit Request_Complete.
//============================================================================

class UCk_AutoTest_Timer_RequestComplete : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private bool _CompleteRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // 60s goal: would never naturally complete inside the 5s harness timeout.
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(60.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        _Timer = utils_timer::Add(LocalHandle, Params);
        _Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnTimerDone"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_CompleteRequested) { return; }

        _Timer.Request_Complete();
        _CompleteRequested = true;
    }

    UFUNCTION()
    private void OnTimerDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_CompleteRequested,
            "OnDone should only fire after Request_Complete (long-goal timer can't complete naturally in test window)");
        Assert_True(InChrono.Get_IsDone(), "Chrono should report IsDone after Request_Complete");
        FinishSuccess();
    }
}
