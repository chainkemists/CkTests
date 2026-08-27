// Language=angelscript

//============================================================================
// CK DIALOG - AUTOMATION TEST: QUERY RETURNS ALL LINES WITH STATES
//============================================================================
// Three global lines under one ENTER tag (one gated by an always-fail
// condition). A query returns ALL three, each classified: two Passed, one
// Fail_LineCondition. Proves the query returns everything, not just winners.
//============================================================================

class UCk_AutoTest_Dialog_Query_ReturnsAllLines_WithStates : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_DialogEmitter _Emitter;
    private FGameplayTag _EventTag;
    private bool _Queried = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _EventTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.All.Enter");
        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        // Line 1 - no conditions -> Passed
        {
            auto LineData = FCk_DialogBank_LineData(n"AutoTest.All.Line1", _EventTag);
            LineData.Set_Text(FText::FromString("Line 1"));
            Track_ForCleanup(FCk_Handle(Registry.Request_RegisterLine(LineData, FGameplayTagContainer())));
        }
        // Line 2 - one always-fail condition -> Fail_LineCondition
        {
            auto LineData = FCk_DialogBank_LineData(n"AutoTest.All.Line2", _EventTag);
            LineData.Set_Text(FText::FromString("Line 2"));
            Track_ForCleanup(FCk_Handle(Registry.Request_RegisterLine_WithCondition(
                LineData, FGameplayTagContainer(), NewObject(this, UCk_DialogTestCond_AlwaysFail))));
        }
        // Line 3 - no conditions -> Passed
        {
            auto LineData = FCk_DialogBank_LineData(n"AutoTest.All.Line3", _EventTag);
            LineData.Set_Text(FText::FromString("Line 3"));
            Track_ForCleanup(FCk_Handle(Registry.Request_RegisterLine(LineData, FGameplayTagContainer())));
        }

        _Emitter = UCk_Utils_DialogEmitter_UE::Add(LocalHandle, FCk_Fragment_DialogEmitter_ParamsData(FGameplayTagContainer()));

        // Querying before all three deferred registrations land would
        // legitimately return fewer lines and fail misleadingly - wait until
        // the registry can see all of them.
        WaitUntil(n"Check_AllLinesRegistered", n"OnSettled");
    }

    UFUNCTION()
    private void Check_AllLinesRegistered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        auto Res = OutResult;
        Res.Set(ck::IsValid(Registry) && Registry.Get_Lines_ByEventTag(_EventTag).Num() >= 3);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_Queried) { return; }
        _Queried = true;

        _Emitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnQueryCompleted"));
        _Emitter.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
    }

    UFUNCTION()
    private void OnQueryCompleted(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
    {
        if (IsFinished()) { return; }

        auto Entries = InResult.Get_Entries();
        Assert_True(Entries.Num() == 3, "All three matched lines returned regardless of pass/fail");

        int PassedCount = 0;
        int FailLineCount = 0;
        for (int i = 0; i < Entries.Num(); i++)
        {
            auto Result = Entries[i].Get_Result();
            if (Result == ECk_DialogLine_QueryResult::Passed) { PassedCount++; }
            else if (Result == ECk_DialogLine_QueryResult::Fail_LineCondition) { FailLineCount++; }
        }

        Assert_True(PassedCount == 2, "Two conditionless lines Pass");
        Assert_True(FailLineCount == 1, "One always-fail line reports Fail_LineCondition");

        FinishSuccess();
    }
}
