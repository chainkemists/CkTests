// Language=angelscript

//============================================================================
// CK TAGSET - NET AUTOMATION TEST: ADD TAG REPLICATES
//============================================================================
//
// The default NetSubject's entity-script adds a Replicates TagSet (empty
// initial) on both worlds and stashes the handle on the actor as `_TestTagSet`.
// The server Request_AddTag's a registered tag; the client polls HasTag for it
// via the FCk_RepData_TagSet container handler. A TagSet is single-per-entity,
// so the actor-stash avoids any by-name lookup.
//
// Surface: Ck.TagSet.Net.AS_AddTag_Replicates
//============================================================================

class UCk_AutoTest_Net_AddTag_Replicates : UCk_AutoTest_NetBase
{
    private FName _TagName = n"Probe.Gyms.A";

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("DIAG-A: subject not found"); return; }

        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto NetSubject = Cast<ACk_AutoTest_NetSubject>(SubjectActor);
        if (NetSubject == nullptr)
        { FinishFailure("DIAG-B: actor cast to ACk_AutoTest_NetSubject failed"); return; }

        auto TagSet = NetSubject._TestTagSet;
        if (ck::Is_NOT_Valid(TagSet))
        { FinishFailure("DIAG-C: TagSet handle null - entity-script Construct didn't stash it?"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            auto Tag = utils_gameplay_tag::ResolveGameplayTag(_TagName);
            utils_tag_set::Request_AddTag(TagSet, Tag);
            // Verify the add lands server-side (poll our own TagSet) before declaring success
            // distinguishes "add failed on server" from "replication failed to client".
            WaitOneFrame(n"OnServerVerify");
            return;
        }

        WaitOneFrame(n"OnPollTag");
    }

    private int _PollCount = 0;
    private const int kPollBudget = 400;

    UFUNCTION()
    private void OnServerVerify(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        auto Subject = Get_SubjectEntity();
        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto NetSubject = Cast<ACk_AutoTest_NetSubject>(SubjectActor);
        auto TagSet = NetSubject._TestTagSet;
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_TagName);

        if (utils_tag_set::HasTag(TagSet, Tag))
        {
            FinishSuccess();
            return;
        }
        if (_PollCount > kPollBudget)
        { FinishFailure("DIAG-SERVER: server's own TagSet never gained the tag after Request_AddTag"); return; }

        WaitOneFrame(n"OnServerVerify");
    }

    UFUNCTION()
    private void OnPollTag(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        auto Subject = Get_SubjectEntity();
        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto NetSubject = Cast<ACk_AutoTest_NetSubject>(SubjectActor);
        if (NetSubject == nullptr)
        { WaitOneFrame(n"OnPollTag"); return; }

        auto TagSet = NetSubject._TestTagSet;
        if (ck::Is_NOT_Valid(TagSet))
        { WaitOneFrame(n"OnPollTag"); return; }

        auto Tag = utils_gameplay_tag::ResolveGameplayTag(_TagName);
        if (utils_tag_set::HasTag(TagSet, Tag))
        {
            FinishSuccess();
            return;
        }
        if (_PollCount > kPollBudget)
        { FinishFailure("DIAG-CLIENT: client TagSet never gained the replicated tag (server-side add presumably worked)"); return; }

        WaitOneFrame(n"OnPollTag");
    }
}
