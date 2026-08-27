// Language=angelscript

//============================================================================
// CK TIMER - AUTOMATION TEST: STOP-ON-DONE BEHAVIOR
//============================================================================
//
// Verifies the StopOnDone behavior. NOTE: ECk_Timer_State only has Paused
// and Running - there is no Stopped enum value. After a Stop request the
// processor removes the NeedsUpdate tag and broadcasts a separate OnStop
// signal (see CkTimer_Processor.cpp). Get_CurrentState() reports Paused
// for both Stop and Pause, so the only way to distinguish StopOnDone from
// PauseOnDone is to bind OnStop. This test passes when OnStop fires after
// the timer hits its goal.
//============================================================================

class UCk_AutoTest_Timer_StopOnDone : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private bool _DoneObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.25f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::StopOnDone);

        _Timer = utils_timer::Add(LocalHandle, Params);
        _Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnTimerDone"));
        _Timer.BindTo_OnStop(FCk_Delegate_Timer(this, n"OnTimerStop"));
    }

    UFUNCTION()
    private void OnTimerDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _DoneObserved = true;
    }

    UFUNCTION()
    private void OnTimerStop(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_DoneObserved,
            "OnStop should follow OnDone for a StopOnDone timer that completed naturally");
        FinishSuccess();
    }
}
