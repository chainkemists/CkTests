// Language=angelscript

//============================================================================
// CK TIMER - AUTOMATION TEST: ON_UPDATE FIRES EVERY TICK WHILE ACTIVE
//============================================================================
//
// Pins the OnUpdate signal contract:
//   - Fires every tick while the timer is Running.
//   - Stops firing when the timer is Paused.
//   - Resumes firing when the timer is Resumed.
//
// We bind OnUpdate, run for N ticks, pause, wait, verify the update count
// did not climb during pause. Then resume and verify it climbs again.
//============================================================================

class UCk_AutoTest_Timer_OnUpdate_FiresEveryTickWhileActive : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Timer _Timer;
    private int32 _UpdateCount = 0;
    private int32 _UpdateCountAtPause = 0;
    private int32 _UpdateCountAtResume = 0;
    private int32 _TicksSincePause = 0;
    private bool _Paused = false;
    private bool _Resumed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        _Timer = utils_timer::Add(LocalHandle, Params);
        utils_timer::BindTo_OnUpdate(_Timer, FCk_Delegate_Timer(this, n"OnUpdate"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnUpdate(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _UpdateCount += 1;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_Paused == false)
        {
            // Run a few ticks then pause.
            if (_UpdateCount >= 3)
            {
                _Paused = true;
                _UpdateCountAtPause = _UpdateCount;
                _Timer.Request_Pause();
            }
            return;
        }

        if (_Resumed == false)
        {
            _TicksSincePause += 1;
            if (_TicksSincePause >= 3)
            {
                Assert_Equals_Int(_UpdateCount, _UpdateCountAtPause,
                    "OnUpdate must NOT fire while the timer is Paused");
                _Resumed = true;
                _UpdateCountAtResume = _UpdateCount;
                _Timer.Request_Resume();
            }
            return;
        }

        if (_UpdateCount > _UpdateCountAtResume + 1)
        {
            Assert_True(_UpdateCount > _UpdateCountAtResume,
                "OnUpdate must resume firing after Request_Resume");
            FinishSuccess();
        }
    }
}
