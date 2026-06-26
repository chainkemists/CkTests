// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: ForEach_Timer visits all timers on entity
//============================================================================
//
// Pins the ForEach_Timer iteration contract: after Add-ing N timers to
// the same owner entity, utils_timer::ForEach_Timer must invoke the
// supplied lambda exactly N times.
//
// Adds 3 paused timers (different goals to distinguish them in case
// of debugging) and verifies the visit count.
//
// Closes one of the four CkTimer audit gaps (alongside Jump_Backward).
//============================================================================

class UCk_AutoTest_Timer_ForEach_Timer_VisitsAll : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private int32 _VisitCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // 3 timers, all paused so they don't complete during this test
        // (PauseOnDone with Paused starting state never advances).
        for (int32 i = 0; i < 3; ++i)
        {
            auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
            Params.Set_StartingState(ECk_Timer_State::Paused);
            Params.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
            utils_timer::Add(LocalHandle, Params);
        }

        utils_timer::ForEach_Timer(
            LocalHandle,
            FInstancedStruct(),
            FCk_Lambda_InHandle(this, n"OnVisitTimer"));

        Assert_Equals_Int(_VisitCount, 3,
            "ForEach_Timer should invoke the visitor lambda once per timer on the owner");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnVisitTimer(FCk_Handle InHandle, FInstancedStruct InOptionalPayload)
    {
        _VisitCount += 1;
    }
}
