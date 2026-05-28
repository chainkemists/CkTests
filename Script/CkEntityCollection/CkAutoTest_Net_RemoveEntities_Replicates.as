// Language=angelscript

//============================================================================
// CK ENTITY COLLECTION — NET AUTOMATION TEST: Remove Entities Replicates
//============================================================================
//
// Server adds the subject's own entity, settles to let the post-Add snapshot
// reach the client, then removes it. Each world independently asserts the
// full add-then-remove cycle on its own collection.
//
// Snapshot-not-deltas gotcha (same as CkInventory DataOnly RemoveItem): the
// container handler delivers only the post-mutation snapshot. Back-to-back
// Add then Remove without a settle would coalesce into a single "empty"
// snapshot, and the client would never observe the "added" state — making it
// impossible to distinguish "remove worked" from "add never landed".
//============================================================================

class UCk_AutoTest_Net_RemoveEntities_Replicates : UCk_AutoTest_NetBase
{
    default _NetSubjectClass = ACk_AutoTest_NetSubject_EntityCollection_UE;

    private FCk_Handle_EntityCollection _ServerCollection;
    private FCk_Handle _EntityToRemove;
    private bool _SawEntryPresent = false;
    private int _PollCount = 0;

    // Settle iterations between server-side Add and Remove. 20 frames ≈ 1s — plenty for the
    // post-Add snapshot to reach the client before the Remove queues a new one. Same constant as
    // the Inventory RemoveItem test (kServerSettleIterations).
    private const int kServerSettleIterations = 20;
    private int _ServerSettleCount = 0;

    private const int kPollBudget = 400;  // 400 * 0.05s ≈ 20s — within harness 30s timeout

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("DIAG-A: subject not found"); return; }

        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto CollectionActor = Cast<ACk_AutoTest_NetSubject_EntityCollection_UE>(SubjectActor);
        if (CollectionActor == nullptr)
        { FinishFailure("DIAG-B: actor cast failed"); return; }

        auto Collection = CollectionActor._TestCollection;
        if (ck::Is_NOT_Valid(Collection))
        { FinishFailure("DIAG-C: collection handle null"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            _ServerCollection = Collection;
            _EntityToRemove = Subject;
            utils_entity_collection::Request_AddSingleEntity(_ServerCollection, _EntityToRemove);
            WaitOneFrame(n"OnServerSettleTick");
            return;
        }

        WaitOneFrame(n"OnClientPollTick");
    }

    UFUNCTION()
    private void OnServerSettleTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ServerSettleCount++;
        if (_ServerSettleCount < kServerSettleIterations)
        {
            WaitOneFrame(n"OnServerSettleTick");
            return;
        }

        utils_entity_collection::Request_RemoveSingleEntity(_ServerCollection, _EntityToRemove);
        WaitOneFrame(n"OnServerPostRemovePoll");
    }

    UFUNCTION()
    private void OnServerPostRemovePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _PollCount++;

        if (utils_entity_collection::Get_NumEntitiesInCollection(_ServerCollection) == 0)
        {
            FinishSuccess();
            return;
        }

        if (_PollCount > kPollBudget)
        { FinishFailure("DIAG-D: server NumEntities never reached 0 after Remove"); return; }

        WaitOneFrame(n"OnServerPostRemovePoll");
    }

    UFUNCTION()
    private void OnClientPollTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _PollCount++;

        auto Subject = Get_SubjectEntity();
        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto CollectionActor = Cast<ACk_AutoTest_NetSubject_EntityCollection_UE>(SubjectActor);
        if (CollectionActor == nullptr)
        { WaitOneFrame(n"OnClientPollTick"); return; }

        auto Collection = CollectionActor._TestCollection;
        if (ck::Is_NOT_Valid(Collection))
        { WaitOneFrame(n"OnClientPollTick"); return; }

        auto Num = utils_entity_collection::Get_NumEntitiesInCollection(Collection);
        if (Num >= 1)
        { _SawEntryPresent = true; }

        if (_SawEntryPresent && Num == 0)
        {
            FinishSuccess();
            return;
        }

        if (_PollCount > kPollBudget)
        {
            if (!_SawEntryPresent)
            { FinishFailure("DIAG-E: client never observed NumEntities>=1 (Add never replicated — possibly NetGuid resolution rejected the rep payload, see CkEntityCollection_Fragment.cpp DoApplyEntityCollections AllValidEntities check)"); return; }
            else
            { FinishFailure("DIAG-F: client saw Add but never observed NumEntities==0 (Remove never replicated)"); return; }
        }

        WaitOneFrame(n"OnClientPollTick");
    }
}
