// Language=angelscript

//============================================================================
// CK DYNAMIC - NET AUTOMATION TEST: CHANNEL-OWNED SUBORDINATE (LEVER PROBE)
//============================================================================
//
// Same as DriverCarrierOnNotify EXCEPT B is spawned under the ActorRelay CHANNEL entity
// instead of under the (actor-bridged) subject/driver. The production StoreDriver comment
// states this is the broken shape:
//
//   "Spawn UNDER THE DRIVER (not the ActorRelay channel) ... required for the replicated
//    carrier handle to net-translate to clients. (The channel's relay actor is server-only,
//    so channel-owned entities get HasOwningActorInChain=false on clients and their
//    replicated fragments never cross the wire.)"
//
// So this test asserts the SAME correct behavior (handle resolves at notify time). If the
// owning-actor chain is the lever, channel-owned B fails to net-translate and this test goes
// RED - proving the dynamic-handle type is a red herring and the chain is the real cause.
//
// Surface: Ck.Dynamic.Net.AS_DynamicFragment_DriverCarrierChannelOwned
//============================================================================

class UCk_AutoTest_Net_DynamicFragment_DriverCarrierChannelOwned : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_PendingActorRelay   _PendingChannel;
    private FCk_Handle_PendingEntityScript _PendingB;

    private int _PollCount = 0;
    private const int kPollBudget = 600;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        if (Subject.Has_Fragment(FCk_Fragment_TESTONLY_DriverCarrier) == false)
        { Subject.Add_Fragment(FCk_Fragment_TESTONLY_DriverCarrier(), ECk_Replication::Replicates); }

        if (utils_net::Get_HasAuthority(Subject))
        {
            // Acquire a channel and spawn B UNDER THE CHANNEL (the broken shape).
            _PendingChannel = utils_actor_relay::Request_AcquireChannel(GameplayTags::ActorRelay_Generic);
            _PendingChannel.Promise_OnAcquired(FCk_Delegate_ActorRelay_Acquired(this, n"OnChannelAcquired"));
            return;
        }

        Subject.BindTo_OnRepNotify(FCk_Fragment_TESTONLY_DriverCarrier,
            FCk_DynamicFragment_OnRepNotify(this, n"OnRepNotify"));
        WaitOneFrame(n"OnTimeoutTick");
    }

    UFUNCTION()
    private void OnChannelAcquired(FCk_ActorRelay_ChannelResult InResult)
    {
        _PendingChannel = FCk_Handle_PendingActorRelay();

        auto Owner = InResult.Get_ChannelEntity();
        if (ck::Is_NOT_Valid(Owner))
        { FinishFailure("ActorRelay channel acquired but channel entity is invalid"); return; }

        _PendingB = utils_entity_script::Request_SpawnEntity(
            Owner, UBb_AutoTest_TESTONLY_Subordinate_EntityScript, FInstancedStruct());
        utils_pending_entity_script::Promise_OnConstructed(
            _PendingB, FCk_Delegate_EntityScript_Constructed(this, n"OnSubordinateConstructed"));
    }

    UFUNCTION()
    private void OnSubordinateConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _PendingB = FCk_Handle_PendingEntityScript();

        // B hangs off the ActorRelay CHANNEL, not off this runner, so the harness teardown never
        // reaches it. Tracked before the early-returns below so a failed resolve still cleans up.
        // (The channel entity itself is pooled and shared - never track that.)
        Track_ForCleanup(FCk_Handle(InEntityScriptHandle));

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("server lost the subject before filling the carrier"); return; }

        auto BHandle = InEntityScriptHandle.As_TESTONLY_Subordinate(ECk_SanityCheck::UnChecked);
        if (ck::Is_NOT_Valid(BHandle))
        { FinishFailure("spawned subordinate B did not resolve to FCk_Handle_TESTONLY_Subordinate on the server"); return; }

        auto& Carrier = Subject.AddOrGet_Fragment(FCk_Fragment_TESTONLY_DriverCarrier);
        Carrier.Handle = BHandle;
        Subject.Request_MarkReplicationDirty(FCk_Fragment_TESTONLY_DriverCarrier);

        FinishSuccess();
    }

    UFUNCTION()
    private void OnRepNotify(FCk_Handle InHandle, FCk_DynamicFragment_RepNotifyInfo InInfo)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject) || Subject.Has_Fragment(FCk_Fragment_TESTONLY_DriverCarrier) == false)
        { FinishFailure("OnRepNotify fired but the carrier is missing on the client"); return; }

        const auto& Carrier = Subject.Get_Fragment(FCk_Fragment_TESTONLY_DriverCarrier);
        Assert_True(Carrier.Handle.IsValid(),
            "the channel-owned subordinate's handle must resolve (validated) AT OnRepNotify time");
        Assert_True((Carrier.Handle == Subject) == false,
            "the carried handle should resolve to B, NOT the subject/driver itself");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnTimeoutTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;
        if (_PollCount > kPollBudget)
        { FinishFailure("client OnRepNotify never fired for the channel-owned carrier"); return; }
        WaitOneFrame(n"OnTimeoutTick");
    }
}
