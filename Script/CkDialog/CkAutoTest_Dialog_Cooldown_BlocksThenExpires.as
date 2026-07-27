// Language=angelscript

//============================================================================
// CK DIALOG — AUTOMATION TEST: COOLDOWN BLOCKS THEN EXPIRES
//============================================================================
// Query a line (Passed) -> start a 0.25s cooldown -> re-query
// (Fail_EmitterCondition) -> wait for expiry -> re-query (Passed again).
//
// Expiry is awaited on Get_IsLineOnCooldown, not on a timer sized to outlast
// the cooldown. The old form armed a 0.4s wait against a 0.25s cooldown — a
// 60% margin that converges no faster than its constant and fails outright if
// cooldown accounting ever slips past it. Polling the emitter's own predicate
// advances the instant the cooldown actually clears and, if it never does,
// names that condition rather than dying on the engine timeout.
//
// Query results arrive on OnQueryCompleted, so each query's outcome is
// latched into _LastResult and the waits observe the latch.
//============================================================================

class UCk_AutoTest_Dialog_Cooldown_BlocksThenExpires : UCk_AutoTest_Base
{
    private FCk_Handle_DialogEmitter _Emitter;
    private FCk_Handle_DialogLine _Line;
    private FGameplayTag _EventTag;

    private bool _HasResult = false;
    private ECk_DialogLine_QueryResult _LastResult = ECk_DialogLine_QueryResult::Fail_EmitterCondition;

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

        // The original settled a frame before binding. Preserve that ordering
        // rather than binding inline — stated as a condition on the emitter
        // instead of a hop, but deliberately still AFTER composition.
        Add_Step_WaitUntil("the emitter is composed",                n"Check_EmitterReady");
        Add_Step(          "bind the query-completed signal",        n"Step_Bind");

        Add_Step(          "query the line before any cooldown",     n"Step_Query");
        Add_Step_WaitUntil("the query completes",                    n"Check_HasResult");
        Add_Step(          "assert it passed, then start a cooldown", n"Step_AssertPassed_StartCooldown");

        Add_Step(          "re-query while on cooldown",             n"Step_Query");
        Add_Step_WaitUntil("the query completes",                    n"Check_HasResult");
        Add_Step(          "assert the cooldown blocked it",         n"Step_AssertBlocked");

        Add_Step_WaitUntil("the cooldown expires",                   n"Check_CooldownExpired");
        Add_Step(          "re-query after expiry",                  n"Step_Query");
        Add_Step_WaitUntil("the query completes",                    n"Check_HasResult");
        Add_Step(          "assert it passes again",                 n"Step_AssertPassedAgain");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Bind(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Emitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnQueryCompleted"));
    }

    UFUNCTION()
    private void Step_Query(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _HasResult = false;
        _Emitter.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
    }

    UFUNCTION()
    private void Step_AssertPassed_StartCooldown(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_DialogLine_QueryResult::Passed,
            "the line should Pass before any cooldown");
        _Emitter.Request_StartCooldown(FCk_Request_DialogEmitter_StartCooldown(_Line, FCk_Time(0.25)));
    }

    UFUNCTION()
    private void Step_AssertBlocked(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_DialogLine_QueryResult::Fail_EmitterCondition,
            "the line should report Fail_EmitterCondition while on cooldown");
    }

    UFUNCTION()
    private void Step_AssertPassedAgain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_DialogLine_QueryResult::Passed,
            "the line should Pass again once the cooldown has expired");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_EmitterReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_Emitter));
    }

    UFUNCTION()
    private void Check_HasResult(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_HasResult);
    }

    UFUNCTION()
    private void Check_CooldownExpired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_dialog_emitter::Get_IsLineOnCooldown(_Emitter, _Line) == false);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnQueryCompleted(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
    {
        auto Entries = InResult.Get_Entries();
        _LastResult = Entries.Num() == 0
            ? ECk_DialogLine_QueryResult::Fail_EmitterCondition
            : Entries[0].Get_Result();
        _HasResult = true;
    }
}
