// Language=angelscript

//============================================================================
// CK ENTITY COLLECTION - NET AUTOMATION TEST: Add Entities Replicates
//============================================================================
//
// Server adds the subject's own entity handle to a Replicates EntityCollection
// on the subject; FCk_RepData_EntityCollections delivers the post-mutation
// snapshot to the client. The subject's own entity is used because it's
// guaranteed-resolvable on both worlds via the WithActor bridge (any
// non-bridged entity would fail the rep handler's AllValidEntities check).
//
// Each world independently asserts NumEntities>=1 and FinishSuccess's on its
// own poll. Server-side polling is needed because Request_AddSingleEntity has
// no completion-delegate API - without polling, the server-side test never
// finishes and the harness times out.
//============================================================================

class UCk_AutoTest_Net_AddEntities_Replicates : UCk_AutoTest_NetBase
{
    default _NetSubjectClass = ACk_AutoTest_NetSubject_EntityCollection_UE;

    private int _PollCount = 0;
    private const int kPollBudget = 400;  // 400 * 0.05s ~ 20s - within the 30s harness timeout

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("DIAG-A: subject not found"); return; }

        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto CollectionActor = Cast<ACk_AutoTest_NetSubject_EntityCollection_UE>(SubjectActor);
        if (CollectionActor == nullptr)
        { FinishFailure("DIAG-B: actor cast failed"); return; }

        auto Collection = CollectionActor._TestCollection;
        if (ck::Is_NOT_Valid(Collection))
        { FinishFailure("DIAG-C: collection handle null - entity-script Construct didn't stash it?"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            utils_entity_collection::Request_AddSingleEntity(Collection, Subject);
        }

        // Both worlds poll their own collection. The server settles its own deferred Add and
        // confirms the request landed; the client waits for the rep handler to apply the snapshot.
        WaitOneFrame(n"OnPollCount");
    }

    UFUNCTION()
    private void OnPollCount(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _PollCount++;

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { WaitOneFrame(n"OnPollCount"); return; }

        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto CollectionActor = Cast<ACk_AutoTest_NetSubject_EntityCollection_UE>(SubjectActor);
        if (CollectionActor == nullptr)
        { WaitOneFrame(n"OnPollCount"); return; }

        auto Collection = CollectionActor._TestCollection;
        if (ck::Is_NOT_Valid(Collection))
        { WaitOneFrame(n"OnPollCount"); return; }

        if (utils_entity_collection::Get_NumEntitiesInCollection(Collection) >= 1)
        {
            FinishSuccess();
            return;
        }

        if (_PollCount > kPollBudget)
        {
            auto Side = utils_net::Get_HasAuthority(Subject) ? "server" : "client";
            FinishFailure(f"DIAG-D: {Side} never observed NumEntities>=1 within poll budget");
            return;
        }

        WaitOneFrame(n"OnPollCount");
    }
}
