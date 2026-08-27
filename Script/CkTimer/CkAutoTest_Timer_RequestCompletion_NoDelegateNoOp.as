// Language=angelscript

//============================================================================
// CK TIMER - AUTOMATION TEST: REQUEST WITHOUT A COMPLETION DELEGATE
//============================================================================
//
// The completion delegate is optional: a Request_* called without one must
// behave exactly as it did before the delegate existed - the state change
// still lands, no request entity is spawned, nothing ensures. This also pins
// the AS surface: the trailing delegate argument is omittable from script.
//============================================================================

class UCk_AutoTest_Timer_RequestCompletion_NoDelegateNoOp : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Timer _Timer;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(60.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);

        _Timer = utils_timer::Add(LocalHandle, Params);

        Assert_True(_Timer.Get_CurrentState() == ECk_Timer_State::Running,
            "Timer must start Running for the pause to be observable");

        utils_timer::Request_Pause(_Timer);

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_Timer.Get_CurrentState() == ECk_Timer_State::Paused,
            "Request_Pause without a completion delegate must still pause the timer");

        FinishSuccess();
    }
}
