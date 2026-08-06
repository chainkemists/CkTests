// Language=angelscript

//============================================================================
// CK DIALOG — AUTOMATION TEST: COOLDOWN PER-EMITTER ISOLATION
//============================================================================
// One line, two emitters. Emitter 1 starts a cooldown on the line; a query
// from emitter 1 reports Fail_EmitterCondition while a query from emitter 2
// still Passes. Cooldowns are per-emitter, keyed by the line entity handle.
//============================================================================

class UCk_AutoTest_Dialog_Cooldown_PerEmitterIsolation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_DialogEmitter _Emitter1;
    private FCk_Handle_DialogEmitter _Emitter2;
    private FCk_Handle_DialogLine _Line;
    private FGameplayTag _EventTag;
    private bool _Started = false;
    private bool _CooldownStarted = false;

    private bool _Got1 = false;
    private bool _Got2 = false;
    private ECk_DialogLine_QueryResult _Result1;
    private ECk_DialogLine_QueryResult _Result2;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _EventTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.CdIso.Enter");
        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        auto LineData = FCk_DialogBank_LineData(n"AutoTest.CdIso.Line", _EventTag);
        LineData.Set_Text(FText::FromString("Shared line"));
        _Line = Registry.Request_RegisterLine(LineData, FGameplayTagContainer());
        Track_ForCleanup(FCk_Handle(_Line));

        _Emitter1 = UCk_Utils_DialogEmitter_UE::Add(LocalHandle, FCk_DialogEmitter_Spec(FGameplayTagContainer()));

        auto Child2 = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Emitter2 = UCk_Utils_DialogEmitter_UE::Add(Child2, FCk_DialogEmitter_Spec(FGameplayTagContainer()));

        WaitUntil(n"Check_LineRegistered", n"OnSettled");
    }

    UFUNCTION()
    private void Check_LineRegistered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        auto Res = OutResult;
        Res.Set(ck::IsValid(Registry) && Registry.Get_Lines_ByEventTag(_EventTag).Num() >= 1);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_Started) { return; }
        _Started = true;

        _Emitter1.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnResult1"));
        _Emitter2.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnResult2"));

        // Cool the line on emitter 1 only, then query BOTH.
        _Emitter1.Request_StartCooldown(FCk_Request_DialogEmitter_StartCooldown(_Line, FCk_Time(2.0)));
        _CooldownStarted = true;
        _Emitter1.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
        _Emitter2.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
    }

    private ECk_DialogLine_QueryResult DoFirstResult(FCk_DialogEmitter_QueryResult InResult)
    {
        auto Entries = InResult.Get_Entries();
        if (Entries.Num() == 0) { return ECk_DialogLine_QueryResult::Fail_EmitterCondition; }
        return Entries[0].Get_Result();
    }

    UFUNCTION()
    private void OnResult1(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
    {
        if (IsFinished()) { return; }
        _Result1 = DoFirstResult(InResult);
        _Got1 = true;
        DoTryFinish();
    }

    UFUNCTION()
    private void OnResult2(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
    {
        if (IsFinished()) { return; }
        _Result2 = DoFirstResult(InResult);
        _Got2 = true;
        DoTryFinish();
    }

    private void DoTryFinish()
    {
        if (!_Got1 || !_Got2) { return; }

        Assert_True(_Result1 == ECk_DialogLine_QueryResult::Fail_EmitterCondition,
            "Emitter 1 (cooled) reports Fail_EmitterCondition");
        Assert_True(_Result2 == ECk_DialogLine_QueryResult::Passed,
            "Emitter 2 (not cooled) still Passes — cooldowns are per-emitter");

        FinishSuccess();
    }
}
