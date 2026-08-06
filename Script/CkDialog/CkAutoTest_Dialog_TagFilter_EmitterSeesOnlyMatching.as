// Language=angelscript

//============================================================================
// CK DIALOG — AUTOMATION TEST: TAG FILTER — EMITTER SEES ONLY MATCHING
//============================================================================
// Two lines under one ENTER tag with disjoint filter tags. An emitter tagged
// Townie sees only the Townie line — the Named line is excluded entirely
// (not "failed").
//============================================================================

class UCk_AutoTest_Dialog_TagFilter_EmitterSeesOnlyMatching : UCk_AutoTest_Base
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

        _EventTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Filter.Enter");
        auto TownieTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Filter.Townie");
        auto NamedTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Filter.Named");

        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        {
            auto TownieBank = FGameplayTagContainer();
            TownieBank.AddTag(TownieTag);
            auto LineData = FCk_DialogBank_LineData(n"AutoTest.Filter.Townie", _EventTag);
            LineData.Set_Text(FText::FromString("Townie line"));
            Track_ForCleanup(FCk_Handle(Registry.Request_RegisterLine(LineData, TownieBank)));
        }
        {
            auto NamedBank = FGameplayTagContainer();
            NamedBank.AddTag(NamedTag);
            auto LineData = FCk_DialogBank_LineData(n"AutoTest.Filter.Named", _EventTag);
            LineData.Set_Text(FText::FromString("Named line"));
            Track_ForCleanup(FCk_Handle(Registry.Request_RegisterLine(LineData, NamedBank)));
        }

        auto EmitterTags = FGameplayTagContainer();
        EmitterTags.AddTag(TownieTag);
        _Emitter = UCk_Utils_DialogEmitter_UE::Add(LocalHandle, FCk_DialogEmitter_Spec(EmitterTags));

        // Wait until BOTH lines are registered, which is load-bearing for the
        // contract: with only the Townie line landed, "emitter sees exactly the
        // Townie line" would pass without the filter doing anything.
        WaitUntil(n"Check_BothLinesRegistered", n"OnSettled");
    }

    UFUNCTION()
    private void Check_BothLinesRegistered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        auto Res = OutResult;
        Res.Set(ck::IsValid(Registry) && Registry.Get_Lines_ByEventTag(_EventTag).Num() >= 2);
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
        Assert_True(Entries.Num() == 1, "Only the tag-overlapping line is visible to the emitter");
        if (Entries.Num() == 1)
        {
            Assert_True(Entries[0].Get_LineID() == n"AutoTest.Filter.Townie", "The Townie line is the one seen");
            Assert_True(Entries[0].Get_Result() == ECk_DialogLine_QueryResult::Passed, "It Passes (no conditions)");
        }

        FinishSuccess();
    }
}
