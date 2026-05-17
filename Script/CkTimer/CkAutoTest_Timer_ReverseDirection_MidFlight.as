// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: REVERSE DIRECTION MID-FLIGHT
//============================================================================
//
// Pins Request_ReverseDirection toggling a running timer's direction:
//   1. Start a CountDown timer (long goal, never completes naturally).
//   2. Verify Get_CountDirection == CountDown.
//   3. Issue Request_ReverseDirection (no args — toggle).
//   4. Poll until Get_CountDirection == CountUp.
//
// Pairs with the existing Timer_ChangeCountDirection test (which pins the
// explicit-direction Request_ChangeCountDirection). This one pins the
// argument-less toggle variant.
//============================================================================

class UCk_AutoTest_Timer_ReverseDirection_MidFlight : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private bool _ReverseRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(60.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
        Params.Set_CountDirection(ECk_Timer_CountDirection::CountDown);

        _Timer = utils_timer::Add(LocalHandle, Params);

        Assert_True(_Timer.Get_CountDirection() == ECk_Timer_CountDirection::CountDown,
            f"Timer should report CountDown direction at setup (got {_Timer.Get_CountDirection()})");

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_ReverseRequested == false)
        {
            utils_timer::Request_ReverseDirection(_Timer);
            _ReverseRequested = true;
            return;
        }

        if (_Timer.Get_CountDirection() == ECk_Timer_CountDirection::CountUp)
        {
            FinishSuccess();
        }
    }
}
