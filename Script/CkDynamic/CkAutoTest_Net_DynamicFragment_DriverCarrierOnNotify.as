// Language=angelscript

//============================================================================
// CK DYNAMIC — NET AUTOMATION TEST: STOREDRIVER CARRIER, ASSERTED INSIDE OnRepNotify
//============================================================================
//
// The decisive notify-DRIVEN test. Identical setup to DriverCarrierReplicates (driver A
// carries a SEPARATE replicated entity B's dynamic handle in an empty->filled replicated
// carrier), but the handle-resolution assertion runs INSIDE the OnRepNotify callback —
// exactly where the real StoreDriver reads it (Reconcile_Subordinates).
//
// This is the key difference from the poll-based DriverCarrierReplicates (which passes):
// if B's rep-driver GUID is unmapped when the carrier replicates, the handle is BLANK at
// notify time and only re-resolves later. A poll loop hides that (it retries until valid);
// reading at notify time catches it — which is what the production consumer suffers.
//
// Surface: Ck.Dynamic.Net.AS_DynamicFragment_DriverCarrierOnNotify
//============================================================================

class UCk_AutoTest_Net_DynamicFragment_DriverCarrierOnNotify : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 15.0f;

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
            auto Owner = Subject;
            _PendingB = utils_entity_script::Request_SpawnEntity(
                Owner, UBb_AutoTest_TESTONLY_Subordinate_EntityScript, FInstancedStruct());
            utils_pending_entity_script::Promise_OnConstructed(
                _PendingB, FCk_Delegate_EntityScript_Constructed(this, n"OnSubordinateConstructed"));
            return;
        }

        Subject.BindTo_OnRepNotify(FCk_Fragment_TESTONLY_DriverCarrier,
            FCk_DynamicFragment_OnRepNotify(this, n"OnRepNotify"));
        WaitOneFrame(n"OnTimeoutTick");
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

        auto& Carrier = Subject.AddOrGet_Fragment(FCk_Fragment_TESTONLY_DriverCarrier);
        Carrier.Handle = BHandle;
        Subject.Request_MarkReplicationDirty(FCk_Fragment_TESTONLY_DriverCarrier);

        FinishSuccess();
    }

    // The assertion happens HERE, at notify time — like StoreDriver's Reconcile_Subordinates.
    UFUNCTION()
    private void OnRepNotify(FCk_Handle InHandle, FCk_DynamicFragment_RepNotifyInfo InInfo)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject) || Subject.Has_Fragment(FCk_Fragment_TESTONLY_DriverCarrier) == false)
        { FinishFailure("OnRepNotify fired but the carrier is missing on the client"); return; }

        const auto& Carrier = Subject.Get_Fragment(FCk_Fragment_TESTONLY_DriverCarrier);
        Assert_True(Carrier.Handle.IsValid(),
            "the dynamic handle to B must resolve (validated) AT OnRepNotify time, not eventually");
        Assert_True((Carrier.Handle == Subject) == false,
            "the carried handle should resolve to B, NOT the subject/driver itself");

        FinishSuccess();
    }

    // Backstop only: fail if OnRepNotify never fires within budget.
    UFUNCTION()
    private void OnTimeoutTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;
        if (_PollCount > kPollBudget)
        { FinishFailure("client OnRepNotify never fired for the StoreDriver-shaped carrier"); return; }
        WaitOneFrame(n"OnTimeoutTick");
    }
}
