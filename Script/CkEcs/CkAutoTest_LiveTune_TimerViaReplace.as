// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: TIMER PILOT (ViaReplace)
//============================================================================
//
// The first real-feature registration of the ViaReplace tier: retuning a
// linked Timer's params replaces the live params fragment and the PostReplace
// fixup re-syncs the derived count-direction state through the Timer's own
// deferred request — so the observable direction flips within a tick, without
// stopping PIE.
//============================================================================

class UCk_AutoTest_LiveTune_TimerViaReplace : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private UCk_LiveTuneTest_TuningAsset _Asset;
    private FCk_Handle_Timer _Timer;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        _Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(0, 0);

        auto Owner = utils_entity_lifetime::Request_CreateEntity(Self);
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
        _Timer = utils_timer::Add(Owner, Params);
        UCk_LiveTuneTest_Utils::Set_TimerParams(_Asset, Params);

        auto TimerBase = FCk_Handle(_Timer);
        UCk_LiveTuneTest_Utils::Link(TimerBase, _Asset, n"_TimerParams");

        Assert_True(utils_timer::Get_CountDirection(_Timer) == ECk_Timer_CountDirection::CountUp,
            "a freshly added timer should count up");

        auto Retuned = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
        Retuned.Set_CountDirection(ECk_Timer_CountDirection::CountDown);
        UCk_LiveTuneTest_Utils::Set_TimerParams(_Asset, Retuned);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, _Asset, n"_TimerParams");

        Add_Step_WaitUntil("the retuned count direction lands through the deferred request", n"Check_CountsDown");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_CountsDown(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_timer::Get_CountDirection(_Timer) == ECk_Timer_CountDirection::CountDown);
    }
}
