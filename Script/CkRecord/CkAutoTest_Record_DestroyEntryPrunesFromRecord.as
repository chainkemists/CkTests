// Language=angelscript

//============================================================================
// CK RECORD - AUTOMATION TEST: DESTROY ENTRY PRUNES FROM RECORD
//============================================================================
//
// Pins the auto-prune contract on entity destruction: when a connected entry
// entity is destroyed, the Record's internal entry array prunes it on the
// next ForEach traversal (the framework's documented behavior - see
// DoForEach_Entry which RemoveAtSwaps pending-kill entries during iteration).
//
// Setup:
//   - Owner with the Record feature.
//   - Connect three labeled entries A, B, C.
//   - Destroy B's entity directly.
//   - WaitOneFrame to settle destruction.
//   - Verify A and C are still ContainsEntry; B is not.
//============================================================================

class UCk_AutoTest_Record_DestroyEntryPrunesFromRecord : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _RecordOwner;
    private FCk_Handle _EntryA;
    private FCk_Handle _EntryB;
    private FCk_Handle _EntryC;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _RecordOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_record_of_entities::Add(_RecordOwner);

        _EntryA = MakeLabeledEntry(LocalHandle, n"AutoTest.Record.Prune.A");
        _EntryB = MakeLabeledEntry(LocalHandle, n"AutoTest.Record.Prune.B");
        _EntryC = MakeLabeledEntry(LocalHandle, n"AutoTest.Record.Prune.C");

        utils_record_of_entities::Request_Connect(_RecordOwner, _EntryA);
        utils_record_of_entities::Request_Connect(_RecordOwner, _EntryB);
        utils_record_of_entities::Request_Connect(_RecordOwner, _EntryC);

        Assert_True(utils_record_of_entities::Get_ContainsEntry(_RecordOwner, _EntryB),
            "Pre-destroy: Record should contain EntryB");

        utils_entity_lifetime::Request_DestroyEntity(_EntryB);

        WaitUntil(n"Check_EntryDestroyed", n"OnSettled");
    }

    UFUNCTION()
    private void Check_EntryDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_handle::Get_IsValid(_EntryB) == false);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(!utils_handle::Get_IsValid(_EntryB),
            "EntryB should be invalid after Request_DestroyEntity");
        Assert_True(utils_record_of_entities::Get_ContainsEntry(_RecordOwner, _EntryA),
            "Surviving sibling EntryA should still be in the Record");
        Assert_True(utils_record_of_entities::Get_ContainsEntry(_RecordOwner, _EntryC),
            "Surviving sibling EntryC should still be in the Record");
        Assert_True(!utils_record_of_entities::Get_ContainsEntry(_RecordOwner, _EntryB),
            "Destroyed EntryB should NOT be in the Record after pending-kill prune");

        FinishSuccess();
    }

    private FCk_Handle MakeLabeledEntry(FCk_Handle InOwner, FName InTagName)
    {
        auto Entry = utils_entity_lifetime::Request_CreateEntity(InOwner);
        utils_gameplay_label::Add(Entry, utils_gameplay_tag::ResolveGameplayTag(InTagName));
        return Entry;
    }
}
