// Language=angelscript

//============================================================================
// CK DIALOG — AUTOMATION TEST: COOLDOWN BLOCKS THEN EXPIRES
//============================================================================
// Query a line (Passed) -> start a 0.25s cooldown -> re-query
// (Fail_EmitterCondition) -> wait past expiry -> re-query (Passed again).
//============================================================================

class UCk_AutoTest_Dialog_Cooldown_BlocksThenExpires : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_DialogEmitter _Emitter;
    private FCk_Handle_DialogLine _Line;
    private FGameplayTag _EventTag;
    private int _Stage = 0;
    private bool _Started = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _EventTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Cooldown.Enter");
        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        auto LineData = FCk_DialogBank_LineData(n"AutoTest.Cooldown.Line", _EventTag);
        LineData.Set_Text(FText::FromString("Cooldown line"));
        _Line = Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
        Track_ForCleanup(FCk_Handle(_Line));

        _Emitter = UCk_Utils_DialogEmitter_UE::Add(LocalHandle, FCk_Fragment_DialogEmitter_ParamsData(FGameplayTagContainer()));

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_Started) { return; }
        _Started = true;

        _Emitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnQueryCompleted"));
        DoQuery();
    }

    private void DoQuery()
    {
        _Emitter.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
    }

    private ECk_DialogLine_QueryResult DoFirstResult(FCk_DialogEmitter_QueryResult InResult)
    {
        auto Entries = InResult.Get_Entries();
        if (Entries.Num() == 0) { return ECk_DialogLine_QueryResult::Fail_EmitterCondition; }
        return Entries[0].Get_Result();
    }

    UFUNCTION()
    private void OnQueryCompleted(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
    {
        if (IsFinished()) { return; }

        auto Result = DoFirstResult(InResult);

        if (_Stage == 0)
        {
            Assert_True(Result == ECk_DialogLine_QueryResult::Passed, "Stage 0: line Passes before any cooldown");
            _Stage = 1;
            _Emitter.Request_StartCooldown(FCk_Request_DialogEmitter_StartCooldown(_Line, FCk_Time(0.25)));
            DoQuery();
        }
        else if (_Stage == 1)
        {
            Assert_True(Result == ECk_DialogLine_QueryResult::Fail_EmitterCondition,
                "Stage 1: line reports Fail_EmitterCondition while on cooldown");
            _Stage = 2;

            auto Self = ck::ToEntity(this);
            auto WaitParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.4));
            WaitParams.Set_StartingState(ECk_Timer_State::Running);
            WaitParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);
            auto WaitTimer = utils_timer::Add(Self, WaitParams);
            WaitTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnExpiryWaitDone"));
        }
        else if (_Stage == 2)
        {
            Assert_True(Result == ECk_DialogLine_QueryResult::Passed, "Stage 2: line Passes again after cooldown expiry");
            FinishSuccess();
        }
    }

    UFUNCTION()
    private void OnExpiryWaitDone(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        DoQuery();
    }
}
