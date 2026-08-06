// Language=angelscript

//============================================================================
// CK DIALOG — AUTOMATION TEST: EXIT-TAG CHAIN ADJACENCY
//============================================================================
// Line A's ExitTag equals Line B's EnterTag. Querying A's enter tag returns A
// (whose entry exposes the exit tag); Request_QueryFollowUp on the played A
// line then resolves to B.
//============================================================================

class UCk_AutoTest_Dialog_ExitTag_ChainAdjacency : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_DialogEmitter _Emitter;
    private FGameplayTag _EnterA;
    private FGameplayTag _EnterB;
    private int _Stage = 0;
    private bool _Started = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _EnterA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Chain.A");
        _EnterB = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Dialog.Chain.B");

        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        {
            auto LineData = FCk_DialogBank_LineData(n"AutoTest.Chain.LineA", _EnterA);
            LineData.Set_Text(FText::FromString("Line A"));
            LineData.Set_LinkedEventTag(_EnterB);
            Track_ForCleanup(FCk_Handle(Registry.Request_RegisterLine(LineData, FGameplayTagContainer())));
        }
        {
            auto LineData = FCk_DialogBank_LineData(n"AutoTest.Chain.LineB", _EnterB);
            LineData.Set_Text(FText::FromString("Line B"));
            Track_ForCleanup(FCk_Handle(Registry.Request_RegisterLine(LineData, FGameplayTagContainer())));
        }

        _Emitter = UCk_Utils_DialogEmitter_UE::Add(LocalHandle, FCk_DialogEmitter_Spec(FGameplayTagContainer()));

        // Both chain links must be registered before the query: the follow-up
        // resolving to B is the contract, so B's registration is load-bearing.
        WaitUntil(n"Check_BothChainLinesRegistered", n"OnSettled");
    }

    UFUNCTION()
    private void Check_BothChainLinesRegistered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Registry = UCk_DialogRegistry_Subsystem_UE::Get_DialogRegistry();

        auto Res = OutResult;
        Res.Set(ck::IsValid(Registry)
             && Registry.Get_Lines_ByEventTag(_EnterA).Num() >= 1
             && Registry.Get_Lines_ByEventTag(_EnterB).Num() >= 1);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_Started) { return; }
        _Started = true;

        _Emitter.BindTo_OnQueryCompleted(FCk_Delegate_DialogEmitter_OnQueryCompleted(this, n"OnQueryCompleted"));
        _Emitter.Request_Query(FCk_Request_DialogEmitter_Query(_EnterA));
    }

    UFUNCTION()
    private void OnQueryCompleted(FCk_Handle_DialogEmitter InEmitter, FCk_DialogEmitter_QueryResult InResult)
    {
        if (IsFinished()) { return; }

        auto Entries = InResult.Get_Entries();

        if (_Stage == 0)
        {
            Assert_True(Entries.Num() == 1, "Query A returns exactly line A");
            if (Entries.Num() != 1) { FinishFailure("Stage 0 expected 1 entry"); return; }

            Assert_True(Entries[0].Get_LineID() == n"AutoTest.Chain.LineA", "Line A returned");
            Assert_True(Entries[0].Get_LinkedEventTag() == _EnterB, "Line A's exit tag is line B's enter tag");

            _Stage = 1;
            auto PlayedLine = Entries[0].Get_Line();
            _Emitter.Request_QueryFollowUp(PlayedLine);
        }
        else if (_Stage == 1)
        {
            Assert_True(Entries.Num() == 1, "Follow-up query resolves to exactly line B");
            if (Entries.Num() == 1)
            {
                Assert_True(Entries[0].Get_LineID() == n"AutoTest.Chain.LineB", "Follow-up returned line B");
            }
            FinishSuccess();
        }
    }
}
