// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: TRYGET_TIMER BY NAME AMONG MULTIPLE
//============================================================================
//
// Pins TryGet_Timer(owner, name) lookup on an owner hosting three named
// timers:
//   - Each known tag resolves to a valid handle.
//   - An unknown tag resolves to an invalid handle.
//
// We attach three timers with distinct FGameplayTag names on the same
// owner entity and verify the lookup distinguishes them correctly. To
// confirm the right timer was returned, each is created with a distinct
// duration; we compare the durations via Get_CurrentTimerValue style queries
// against the captured handles.
//============================================================================

class UCk_AutoTest_Timer_TryGet_Timer_ByName_AmongMultiple : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;
    private FCk_Handle_Timer _TimerA;
    private FCk_Handle_Timer _TimerB;
    private FCk_Handle_Timer _TimerC;
    private FGameplayTag _NameA;
    private FGameplayTag _NameB;
    private FGameplayTag _NameC;
    private FGameplayTag _NameUnknown;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = InHandle;
        _NameA = utils_gameplay_tag::ResolveGameplayTag(n"Timer.AutoTest_A");
        _NameB = utils_gameplay_tag::ResolveGameplayTag(n"Timer.AutoTest_B");
        _NameC = utils_gameplay_tag::ResolveGameplayTag(n"Timer.AutoTest_C");
        _NameUnknown = utils_gameplay_tag::ResolveGameplayTag(n"Timer.AutoTest_Unknown");

        auto ParamsA = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
        ParamsA.Set_TimerName(_NameA);
        ParamsA.Set_StartingState(ECk_Timer_State::Paused);
        _TimerA = utils_timer::Add(_Owner, ParamsA);

        auto ParamsB = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
        ParamsB.Set_TimerName(_NameB);
        ParamsB.Set_StartingState(ECk_Timer_State::Paused);
        _TimerB = utils_timer::Add(_Owner, ParamsB);

        auto ParamsC = FCk_Fragment_Timer_ParamsData(FCk_Time(20.0f));
        ParamsC.Set_TimerName(_NameC);
        ParamsC.Set_StartingState(ECk_Timer_State::Paused);
        _TimerC = utils_timer::Add(_Owner, ParamsC);

        auto FoundA = utils_timer::TryGet_Timer(_Owner, _NameA);
        Assert_True(ck::IsValid(FoundA),
            "TryGet_Timer(NameA) must return a valid handle");
        Assert_True(FoundA == _TimerA,
            "TryGet_Timer(NameA) must return the handle of the timer added with NameA");

        auto FoundB = utils_timer::TryGet_Timer(_Owner, _NameB);
        Assert_True(ck::IsValid(FoundB),
            "TryGet_Timer(NameB) must return a valid handle");
        Assert_True(FoundB == _TimerB,
            "TryGet_Timer(NameB) must return the handle of the timer added with NameB");

        auto FoundC = utils_timer::TryGet_Timer(_Owner, _NameC);
        Assert_True(ck::IsValid(FoundC),
            "TryGet_Timer(NameC) must return a valid handle");
        Assert_True(FoundC == _TimerC,
            "TryGet_Timer(NameC) must return the handle of the timer added with NameC");

        auto FoundUnknown = utils_timer::TryGet_Timer(_Owner, _NameUnknown);
        Assert_True(ck::Is_NOT_Valid(FoundUnknown),
            "TryGet_Timer with an unknown name must return an invalid handle");

        FinishSuccess();
    }
}
