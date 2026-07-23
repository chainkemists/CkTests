// Language=angelscript

//============================================================================
// CK DIALOG — AUTOMATION TEST: CONDITION RECEIVES CALLER (EMITTER) CONTEXT
//============================================================================
// One line, gated by a condition that Passes only when the querying emitter
// carries a required tag. Two emitters query it: the tagged one gets Passed,
// the untagged one gets Fail_LineCondition. Proves the per-emitter purity
// contract — the same line resolves differently per caller in the same frame.
//============================================================================

class UCk_AutoTest_Dialog_Condition_ReceivesCallerContext : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_DialogEmitter _EmitterWithTag;
    private FCk_Handle_DialogEmitter _EmitterNoTag;
    private FGameplayTag _EventTag;
    private bool _Queried = false;

    private bool _GotWithTag = false;
    private bool _GotNoTag = false;
    private ECk_DialogLine_QueryResult _ResultWithTag;
    private ECk_DialogLine_QueryResult _ResultNoTag;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _EventTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Ctx.Enter");
        auto RequiredTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Ctx.Required");

        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        {
            auto Cond = NewObject(this, UCk_DialogTestCond_RequiresEmitterTag);
            Cond.RequiredEmitterTag = RequiredTag;

            auto LineData = FCk_DialogBank_LineData(n"AutoTest.Ctx.Line", _EventTag);
            LineData.Set_Text(FText::FromString("Context-sensitive line"));
            Track_ForCleanup(FCk_Handle(Registry.Request_RegisterLine_WithCondition(
                LineData, FGameplayTagContainer(), Cond)));
        }

        // Emitter A: carries the required tag.
        auto TaggedEmitterTags = FGameplayTagContainer();
        TaggedEmitterTags.AddTag(RequiredTag);
        _EmitterWithTag = UCk_Utils_DialogEmitter_UE::Add(LocalHandle, FCk_Fragment_DialogEmitter_ParamsData(TaggedEmitterTags));

        // Emitter B: a separate child entity, no tags.
        auto ChildB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _EmitterNoTag = UCk_Utils_DialogEmitter_UE::Add(ChildB, FCk_Fragment_DialogEmitter_ParamsData(FGameplayTagContainer()));

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_Queried) { return; }
        _Queried = true;

        _EmitterWithTag.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnResultWithTag"));
        _EmitterNoTag.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnResultNoTag"));

        _EmitterWithTag.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
        _EmitterNoTag.Request_Query(FCk_Request_DialogEmitter_Query(_EventTag));
    }

    private ECk_DialogLine_QueryResult DoFirstResult(FCk_DialogEmitter_QueryResult InResult)
    {
        auto Entries = InResult.Get_Entries();
        if (Entries.Num() == 0) { return ECk_DialogLine_QueryResult::Fail_EmitterCondition; }
        return Entries[0].Get_Result();
    }

    UFUNCTION()
    private void OnResultWithTag(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
    {
        if (IsFinished()) { return; }
        _ResultWithTag = DoFirstResult(InResult);
        _GotWithTag = true;
        DoTryFinish();
    }

    UFUNCTION()
    private void OnResultNoTag(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
    {
        if (IsFinished()) { return; }
        _ResultNoTag = DoFirstResult(InResult);
        _GotNoTag = true;
        DoTryFinish();
    }

    private void DoTryFinish()
    {
        if (!_GotWithTag || !_GotNoTag) { return; }

        Assert_True(_ResultWithTag == ECk_DialogLine_QueryResult::Passed,
            "Emitter WITH the required tag: line Passes");
        Assert_True(_ResultNoTag == ECk_DialogLine_QueryResult::Fail_LineCondition,
            "Emitter WITHOUT the required tag: same line reports Fail_LineCondition");

        FinishSuccess();
    }
}
