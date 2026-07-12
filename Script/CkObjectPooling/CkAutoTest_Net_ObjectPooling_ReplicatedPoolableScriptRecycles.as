// Language=angelscript

//============================================================================
// CK OBJECT POOLING — NET AUTOMATION TEST: replicated poolable script recycles
//============================================================================
//
// Decision 3 allowed replicated EntityScripts to use the Poolable policy; this
// is its safety net. Server: spawn a replicated poolable script under the
// subject, destroy it (EndPlay releases the instance to the pool), respawn the
// same class — the pool stats must prove a recycle (1 hit, 1 live instance).
// The respawned entity's handle then rides a replicated dynamic fragment to
// the client, which asserts the recycled respawn re-established cleanly on its
// world: the handle resolves, and the CLIENT-side Construct ran for it (the
// subject script marks its entity with a local variable on every world). The
// server's destroy also replicates, so the client exercises its own
// release-then-recycle path implicitly.
//
// Surface: Ck.ObjectPooling.Net.AS_ObjectPooling_ReplicatedPoolableScriptRecycles
//============================================================================

class UCk_AutoTest_Net_ObjectPooling_ReplicatedPoolableScriptRecycles : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle _FirstEntity;
    private bool _RespawnedRefArrived = false;

    private int _PollCount = 0;
    private int _ServerPollCount = 0;
    private const int kPollBudget = 600;

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
                Subject, UCk_ObjectPoolingTest_ReplicatedPoolableScript, FInstancedStruct());
            utils_pending_entity_script::Promise_OnConstructed(
                Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnFirstConstructed"));
            return;
        }

        // Client: bind BEFORE the server authors the carrier, then poll
        Subject.BindTo_OnRepNotify(FCk_Fragment_PoolingTest_RespawnedRef,
            FCk_DynamicFragment_OnRepNotify(this, n"OnRespawnedRefNotify"));
        WaitOneFrame(n"OnClientPoll");
    }

    //------------------------------------------------------------------------
    // Server
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnFirstConstructed(FCk_Handle_EntityScript InEntity)
    {
        if (IsFinished()) { return; }

        _FirstEntity = FCk_Handle(InEntity);
        utils_entity_lifetime::Request_DestroyEntity(_FirstEntity);
        WaitOneFrame(n"OnDestroySettled");
    }

    UFUNCTION()
    private void OnDestroySettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // replicated entity destruction is deferred beyond one frame (replication teardown) —
        // poll until EndPlay has released the instance back to the pool
        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_ReplicatedPoolableScript, nullptr);

        if (Stats.Get_NumFree() < 1)
        {
            _ServerPollCount++;
            if (_ServerPollCount > kPollBudget)
            { FinishFailure("server: EndPlay never parked the replicated script instance"); return; }

            WaitOneFrame(n"OnDestroySettled");
            return;
        }

        auto Subject = Get_SubjectEntity();
        auto Pending = utils_entity_script::Request_SpawnEntity(
            Subject, UCk_ObjectPoolingTest_ReplicatedPoolableScript, FInstancedStruct());
        utils_pending_entity_script::Promise_OnConstructed(
            Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnSecondConstructed"));
    }

    UFUNCTION()
    private void OnSecondConstructed(FCk_Handle_EntityScript InEntity)
    {
        if (IsFinished()) { return; }

        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_ReplicatedPoolableScript, nullptr);
        Assert_Equals_Int(Stats.Get_NumHits(), 1, "server: respawn must RECYCLE the parked instance (1 hit)");
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 1, "server: exactly 1 live script instance across both spawns");
        if (IsFinished()) { return; }

        // hand the recycled respawn's entity to the client via the replicated carrier
        auto Subject = Get_SubjectEntity();
        auto Carrier = FCk_Fragment_PoolingTest_RespawnedRef();
        Carrier.TheEntity = FCk_Handle(InEntity);
        Subject.Add_Fragment(Carrier, ECk_Replication::Replicates);

        FinishSuccess();
    }

    //------------------------------------------------------------------------
    // Client
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnRespawnedRefNotify(FCk_Handle InHandle, FCk_DynamicFragment_RepNotifyInfo InInfo)
    {
        _RespawnedRefArrived = true;
    }

    UFUNCTION()
    private void OnClientPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        if (_RespawnedRefArrived)
        {
            auto Subject = Get_SubjectEntity();
            const auto& Carrier = Subject.Get_Fragment(FCk_Fragment_PoolingTest_RespawnedRef);

            // the respawned entity and its client-side construction may land a few frames after
            // the carrier — keep polling inside the budget until both are observable
            if (ck::IsValid(Carrier.TheEntity))
            {
                auto ConstructedTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.ObjectPooling.NetConstructed");
                ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
                auto Constructed = utils_variables_int32::Get_ByName(
                    Carrier.TheEntity, ConstructedTag.GetTagName(), ECk_Recursion::NotRecursive, Status);

                if (Status == ECk_SucceededFailed::Succeeded)
                {
                    Assert_Equals_Int(Constructed, 1,
                        "client: the recycled respawn must have run Construct on the CLIENT world too");
                    FinishSuccess();
                    return;
                }
            }
        }

        if (_PollCount > kPollBudget)
        {
            FinishFailure(_RespawnedRefArrived
                ? "client: the respawned (recycled) entity never became observable/constructed on the client"
                : "client: the replicated carrier fragment never arrived");
            return;
        }

        WaitOneFrame(n"OnClientPoll");
    }
}
