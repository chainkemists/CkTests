// Language=angelscript

//============================================================================
// CK TIMER - AUTOMATION TEST: REQUEST CONSUME
//============================================================================
//
// Verifies Request_Consume on a CountDown timer:
//   - Goal is large enough that natural completion can't happen in-window.
//   - We Request_Consume(SmallChunk) until the chrono is depleted, then
//     OnDepleted should fire. (The gym binds OnDepleted for consume-driven
//     completion specifically - see CkTimerGym_Countdown.as.)
//
// We poll on each tick: if not yet depleted, request another consume chunk.
// The harness timeout catches the case where consume never depletes.
//============================================================================

class UCk_AutoTest_Timer_RequestConsume : UCk_AutoTest_Base
{
    private FCk_Handle_Timer _Timer;
    private int32 _ChunksConsumed = 0;
    private bool _DepletedObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(60.0f));
        Params.Set_StartingState(ECk_Timer_State::Running);
        Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
        Params.Set_CountDirection(ECk_Timer_CountDirection::CountDown);

        _Timer = utils_timer::Add(LocalHandle, Params);
        _Timer.BindTo_OnDepleted(FCk_Delegate_Timer(this, n"OnTimerDepleted"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_DepletedObserved) { return; }

        // Consume a big chunk each tick - should deplete in 3 ticks.
        _Timer.Request_Consume(FCk_Request_Timer_Consume(FCk_Time(25.0f)));
        _ChunksConsumed++;
    }

    UFUNCTION()
    private void OnTimerDepleted(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _DepletedObserved = true;

        Assert_True(_ChunksConsumed > 0,
            "OnDepleted should follow at least one Request_Consume");
        // Surprising but real: Request_Consume on a CountDown timer calls
        // Tick() (current UP), not Consume() (current DOWN) - see
        // CkTimer_Processor.cpp. So the consume-driven OnDepleted path
        // completes with current=goal, and Get_IsDone() (current >= goal)
        // returns TRUE. This is the OPPOSITE of the natural-tick countdown
        // completion path. See CountdownCompletion test for that case.
        //
        // TODO(API): the asymmetry between consume-on-countdown (Tick + IsDone)
        // and natural-tick-on-countdown (Consume + IsDepleted) is at minimum
        // surprising and may be a framework bug worth investigating. If/when
        // it is unified, this test's assertion will need to be updated to match
        // whichever direction is canonical. Also: Get_IsDepleted is not yet
        // exposed to AngelScript - see the followup note in
        // CkAutoTest_Timer_CountdownCompletion.as.
        Assert_True(InChrono.Get_IsDone(),
            "Chrono should report IsDone in consume-driven OnDepleted on a countdown timer");
        FinishSuccess();
    }
}
