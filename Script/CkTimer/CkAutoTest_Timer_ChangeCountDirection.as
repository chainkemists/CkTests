// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: CHANGE COUNT DIRECTION
//============================================================================
//
// Verifies Request_ChangeCountDirection swaps a running timer's direction
// at runtime:
//   1. Add a CountUp timer with goal 60s (long enough to never naturally
//      finish during the test window).
//   2. Verify Get_CountDirection reports CountUp.
//   3. Issue Request_ChangeCountDirection(CountDown).
//   4. Poll until Get_CountDirection reports CountDown.
//
// Pins down the runtime-control contract for direction. Pairs with the
// existing Timer_PauseHaltsElapsed / Timer_ResumeAfterPause /
// Timer_ResetMidFlight / Timer_RequestComplete tests to cover the full
// runtime-control surface.
//============================================================================

class UCk_AutoTest_Timer_ChangeCountDirection : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private bool _ChangeRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(60.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
        // CountUp is the default direction; assert below that it actually is.

        _Timer = utils_timer::Add(LocalHandle, Params);

        Assert_True(_Timer.Get_CountDirection() == ECk_Timer_CountDirection::CountUp,
            f"New timer should report CountUp by default (got {_Timer.Get_CountDirection()})");

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!_ChangeRequested)
        {
            _Timer.Request_ChangeCountDirection(ECk_Timer_CountDirection::CountDown);
            _ChangeRequested = true;
            return;
        }

        if (_Timer.Get_CountDirection() == ECk_Timer_CountDirection::CountDown)
        {
            Assert_True(true,
                "Get_CountDirection should reflect Request_ChangeCountDirection(CountDown)");
            FinishSuccess();
        }
    }
}
