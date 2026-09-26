// Language=angelscript

//============================================================================
// CK ENTITY SCRIPT - NET AUTOTEST: A REPLICATED CHILD SPAWNED IN DoBeginPlay
//============================================================================
//
// A Replicates entity script spawned from a server DoBeginPlay is drained by the
// Gameplay_Script local settle pass, not by the main pass. Every replicated child
// must still reach its clients regardless of which pass constructed it.
//
// Server: spawns EARLY from DoBeginPlay (the case under test) and LATE from a
// poll callback kLateSpawnPolls later (the positive control - a spawn the main
// pass drains). Asserts both complete replication on the authority.
//
// Client: asserts both children construct under its copy of the subject. Each
// child composes FCk_Fragment_TESTONLY_SubordinateFeature with its own Tag, so
// the client tells them apart without a replicated handle carrier.
//
// Surface: Ck.EntityScript.Net.AS_EntityScript_ChildSpawnedInBeginPlayReplicates
//
// NAMING: the class MUST start with "Ck_AutoTest_Net_" so the net stub
// generator emits a runnable C++ stub (a C++ rebuild is required after
// adding this file).
//============================================================================

class UCk_AutoTest_TESTONLY_NetChild_EntityScript : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::Replicates;

    int32 _ChildTag = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        auto Feature = FCk_Fragment_TESTONLY_SubordinateFeature();
        Feature.Tag = _ChildTag;
        InHandle.Add_Fragment(Feature);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

class UCk_AutoTest_TESTONLY_NetChild_Early_EntityScript : UCk_AutoTest_TESTONLY_NetChild_EntityScript
{
    default _ChildTag = 1;
}

class UCk_AutoTest_TESTONLY_NetChild_Late_EntityScript : UCk_AutoTest_TESTONLY_NetChild_EntityScript
{
    default _ChildTag = 2;
}

class UCk_AutoTest_Net_EntityScript_ChildSpawnedInBeginPlayReplicates : UCk_AutoTest_NetBase
{
    private const int32 kEarlyTag = 1;
    private const int32 kLateTag = 2;
    private const int kLateSpawnPolls = 40;
    // Wall-clock, not frames: the multi-PIE harness ticks slowly and ends every world at 30 s,
    // so the budget has to expire first for a failure to report what it measured.
    private const float kBudgetSeconds = 12.0f;

    private FCk_Handle _EarlyChild;
    private FCk_Handle _LateChild;
    private bool _LateSpawnRequested = false;
    private int _PollCount = 0;
    private float _ElapsedSeconds = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            auto Pending = utils_entity_script::Request_SpawnEntity(
                Subject, UCk_AutoTest_TESTONLY_NetChild_Early_EntityScript, FInstancedStruct());
            utils_pending_entity_script::Promise_OnConstructed(
                Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnEarlyConstructed"));
            WaitOneFrame(n"OnServerPoll");
            return;
        }

        WaitOneFrame(n"OnClientPoll");
    }

    //------------------------------------------------------------------------
    // Server
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnEarlyConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _EarlyChild = FCk_Handle(InEntityScriptHandle);
    }

    UFUNCTION()
    private void OnLateConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _LateChild = FCk_Handle(InEntityScriptHandle);
    }

    UFUNCTION()
    private void OnServerPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;
        _ElapsedSeconds += float(InDeltaT.Get_Seconds());

        if (!_LateSpawnRequested && _PollCount >= kLateSpawnPolls)
        {
            _LateSpawnRequested = true;
            auto Pending = utils_entity_script::Request_SpawnEntity(
                Get_SubjectEntity(), UCk_AutoTest_TESTONLY_NetChild_Late_EntityScript, FInstancedStruct());
            utils_pending_entity_script::Promise_OnConstructed(
                Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnLateConstructed"));
        }

        const auto EarlyComplete = Get_IsServerChildReplicated(_EarlyChild);
        const auto LateComplete = Get_IsServerChildReplicated(_LateChild);

        if (EarlyComplete && LateComplete)
        {
            FinishSuccess();
            return;
        }

        if (_ElapsedSeconds > kBudgetSeconds)
        {
            FinishFailure(f"server: a child never completed replication on the authority "
                + f"[early: constructed={ck::IsValid(_EarlyChild)} replicated={EarlyComplete}] "
                + f"[late: constructed={ck::IsValid(_LateChild)} replicated={LateComplete}]");
            return;
        }

        WaitOneFrame(n"OnServerPoll");
    }

    private bool Get_IsServerChildReplicated(FCk_Handle InChild) const
    {
        if (ck::Is_NOT_Valid(InChild) || !utils_entity_replication_driver::Has(InChild))
        { return false; }

        return utils_entity_replication_driver::Get_IsReplicationComplete(InChild);
    }

    //------------------------------------------------------------------------
    // Client
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnClientPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;
        _ElapsedSeconds += float(InDeltaT.Get_Seconds());

        auto Subject = Get_SubjectEntity();
        const auto EarlyPresent = Get_HasChildWithTag(Subject, kEarlyTag);
        const auto LatePresent = Get_HasChildWithTag(Subject, kLateTag);

        if (EarlyPresent && LatePresent)
        {
            FinishSuccess();
            return;
        }

        if (_ElapsedSeconds > kBudgetSeconds)
        {
            const auto NumDependents = ck::IsValid(Subject)
                ? utils_entity_lifetime::Get_LifetimeDependents(Subject).Num()
                : -1;
            FinishFailure(f"client: a replicated child never constructed under the subject "
                + f"[early (spawned in DoBeginPlay): {EarlyPresent}] "
                + f"[late (spawned from a poll callback): {LatePresent}] "
                + f"[subject valid: {ck::IsValid(Subject)}, dependents: {NumDependents}]");
            return;
        }

        WaitOneFrame(n"OnClientPoll");
    }

    private bool Get_HasChildWithTag(FCk_Handle InSubject, int32 InTag) const
    {
        if (ck::Is_NOT_Valid(InSubject))
        { return false; }

        for (auto Dependent : utils_entity_lifetime::Get_LifetimeDependents(InSubject))
        {
            if (!Dependent.Has_Fragment(FCk_Fragment_TESTONLY_SubordinateFeature))
            { continue; }

            if (Dependent.Get_Fragment(FCk_Fragment_TESTONLY_SubordinateFeature).Tag == InTag)
            { return true; }
        }

        return false;
    }
}
