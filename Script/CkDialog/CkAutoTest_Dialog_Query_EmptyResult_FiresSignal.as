// Language=angelscript

//============================================================================
// CK DIALOG — AUTOMATION TEST: EMPTY QUERY STILL FIRES THE SIGNAL
//============================================================================
// A query for an ENTER tag with no registered lines fires OnQueryCompleted
// with an empty entry list (an empty answer is still an answer) and no
// warnings. Warning/Error logs auto-fail the test, so this doubles as a
// "no-match path does not warn" check.
//============================================================================

class UCk_AutoTest_Dialog_Query_EmptyResult_FiresSignal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_DialogEmitter _Emitter;
    private FGameplayTag _EventTag;
    private bool _Queried = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Deliberately register NOTHING under this tag.
        _EventTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Empty.Enter");

        _Emitter = UCk_Utils_DialogEmitter_UE::Add(LocalHandle, FCk_DialogEmitter_Spec(FGameplayTagContainer()));

        WaitOneFrame(n"OnSettled");
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

        Assert_True(InResult.Get_Entries().Num() == 0, "Empty query returns zero entries");
        Assert_True(InResult.Get_EventTag() == _EventTag, "Result echoes the queried enter tag");

        FinishSuccess();
    }
}
