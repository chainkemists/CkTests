// Language=angelscript

//============================================================================
// CK DYNAMIC - NET AUTOMATION TEST: STOREDRIVER-SHAPED DYNAMIC-HANDLE CARRIER
//============================================================================
//
// Faithful reproduction of the reported StoreDriver setup (origin/Feature/
// storedriver-replicated-reconcile): driver A carries a SEPARATE replicated entity
// B's dynamic typesafe handle in a replicated dynamic fragment that is added EMPTY on
// both worlds and filled on the server when B constructs (+ MarkReplicationDirty).
//
// Differences from the simpler self-target tests (which all pass):
//   1. The handle points at a SEPARATE replicated entity B (spawned under the subject),
//      not the same entity - B's rep-driver may be unmapped when A's carrier deserializes.
//   2. The carrier is added empty then FILLED (empty -> B), an OnChange not an authored add.
//   3. B replicates INDEPENDENTLY of A's carrier (the cross-driver ordering race the
//      production comments call the "blank-client bug").
//
// B is spawned UNDER the (actor-bridged) subject so it inherits an owning-actor chain
// production spawns subordinates under the driver for exactly this reason (channel-owned
// entities get HasOwningActorInChain=false on clients and never net-translate).
//
// Client asserts: OnRepNotify fires AND the carried dynamic handle resolves (validated
// IsValid(), i.e. B replicated + its feature composed + the handle net-translated).
//
// Surface: Ck.Dynamic.Net.AS_DynamicFragment_DriverCarrierReplicates
//============================================================================

class UCk_AutoTest_Net_DynamicFragment_DriverCarrierReplicates : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_PendingEntityScript _PendingB;

    private bool _NotifyFired = false;

    private int _PollCount = 0;
    private const int kPollBudget = 600;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        // Both worlds pre-add the empty replicated carrier (mirrors utils_store_driver::Add
        // adding the carrier on both sides; server fills + dirties, client receives the value).
        if (Subject.Has_Fragment(FCk_Fragment_TESTONLY_DriverCarrier) == false)
        { Subject.Add_Fragment(FCk_Fragment_TESTONLY_DriverCarrier(), ECk_Replication::Replicates); }

        if (utils_net::Get_HasAuthority(Subject))
        {
            // Spawn B UNDER the subject so it inherits the owning-actor chain.
            auto Owner = Subject;
            _PendingB = utils_entity_script::Request_SpawnEntity(
                Owner, UBb_AutoTest_TESTONLY_Subordinate_EntityScript, FInstancedStruct());
            utils_pending_entity_script::Promise_OnConstructed(
                _PendingB, FCk_Delegate_EntityScript_Constructed(this, n"OnSubordinateConstructed"));
            return;
        }

        // Client: bind the carrier rep-notify BEFORE the server fills it, then poll.
        Subject.BindTo_OnRepNotify(FCk_Fragment_TESTONLY_DriverCarrier,
            FCk_DynamicFragment_OnRepNotify(this, n"OnRepNotify"));
        WaitOneFrame(n"OnPoll");
    }

    UFUNCTION()
    private void OnSubordinateConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _PendingB = FCk_Handle_PendingEntityScript();

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("server lost the subject before filling the carrier"); return; }

        auto BHandle = InEntityScriptHandle.As_TESTONLY_Subordinate(ECk_SanityCheck::UnChecked);
        if (ck::Is_NOT_Valid(BHandle))
        { FinishFailure("spawned subordinate B did not resolve to FCk_Handle_TESTONLY_Subordinate on the server"); return; }

        // Fill the carrier with B's handle and re-replicate (mirrors Fill_RepCustomization).
        auto& Carrier = Subject.AddOrGet_Fragment(FCk_Fragment_TESTONLY_DriverCarrier);
        Carrier.Handle = BHandle;
        Subject.Request_MarkReplicationDirty(FCk_Fragment_TESTONLY_DriverCarrier);

        FinishSuccess();
    }

    UFUNCTION()
    private void OnRepNotify(FCk_Handle InHandle, FCk_DynamicFragment_RepNotifyInfo InInfo)
    {
        _NotifyFired = true;
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        if (_NotifyFired)
        {
            auto Subject = Get_SubjectEntity();
            Assert_True(ck::IsValid(Subject) && Subject.Has_Fragment(FCk_Fragment_TESTONLY_DriverCarrier),
                "the replicated carrier should exist on the client when OnRepNotify fires");

            const auto& Carrier = Subject.Get_Fragment(FCk_Fragment_TESTONLY_DriverCarrier);

            // Validated IsValid(): true only if B replicated to this client, B's DoConstruct
            // composed Ck_Fragment_TESTONLY_SubordinateFeature, AND the dynamic handle net-translated.
            Assert_True(Carrier.Handle.IsValid(),
                "the dynamic handle to the separate replicated entity B should resolve (validated) on the client");
            Assert_True((Carrier.Handle == Subject) == false,
                "the carried handle should resolve to B, NOT the subject/driver itself");

            FinishSuccess();
            return;
        }

        if (_PollCount > kPollBudget)
        { FinishFailure("client OnRepNotify never fired for the StoreDriver-shaped dynamic-handle carrier"); return; }

        WaitOneFrame(n"OnPoll");
    }
}
