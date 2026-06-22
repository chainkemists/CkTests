// Language=angelscript

//============================================================================
// CK DYNAMIC — NET AUTOMATION TEST: DYNAMIC-HANDLE PROPERTY IN A REPLICATED DYN FRAGMENT
//============================================================================
//
// REPRODUCTION of the reported bug: a replicated dynamic fragment whose payload
// carries a DYNAMIC handle (FCk_Handle_TESTONLY_NetSubject) instead of a raw
// FCk_Handle. Identical flow to the RawHandle control test — handle points at the
// subject entity itself — so any divergence is attributable to the handle TYPE.
//
// The client binds OnRepNotify before the server authors, then asserts:
//   (1) OnRepNotify fired,
//   (2) it reported the correct changed type,
//   (3) the carried dynamic handle resolves to the CLIENT's subject entity.
//
// Per the report this is expected to FAIL today (either the notify never fires,
// or the handle is invalid on the client). The companion RawHandle test is the
// passing baseline that isolates the cause to the dynamic-handle type.
//
// Surface: Ck.Dynamic.Net.AS_DynamicFragment_DynHandleReplicates
//============================================================================

class UCk_AutoTest_Net_DynamicFragment_DynHandleReplicates : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 10.0f;

    private bool          _NotifyFired = false;
    private UScriptStruct _ReportedType;

    private int _PollCount = 0;
    private const int kPollBudget = 400;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        // FCk_Handle_TESTONLY_NetSubject requires Ck_Fragment_TESTONLY_HandleMarker — its validated
        // IsValid()/As_X() only succeed when the entity holds that fragment. Compose it on THIS world's
        // subject (DoesNotReplicate, so each machine composes it locally, mirroring a per-machine feature
        // marker) so the client's validated read below has the required fragment present.
        if (Subject.Has_Fragment(FCk_Fragment_TESTONLY_HandleMarker) == false)
        { Subject.Add_Fragment(FCk_Fragment_TESTONLY_HandleMarker(), ECk_Replication::DoesNotReplicate); }

        if (utils_net::Get_HasAuthority(Subject))
        {
            auto Payload = FCk_Fragment_DynamicTest_DynHandlePayload();
            Payload.Value = 5151;
            Payload.TheHandle = Subject;
            Subject.Add_Fragment(Payload, ECk_Replication::Replicates);
            FinishSuccess();
            return;
        }

        // Client: bind BEFORE the replicated fragment arrives, then poll for the callback.
        Subject.BindTo_OnRepNotify(FCk_Fragment_DynamicTest_DynHandlePayload,
            FCk_DynamicFragment_OnRepNotify(this, n"OnRepNotify"));
        WaitOneFrame(n"OnPoll");
    }

    UFUNCTION()
    private void OnRepNotify(FCk_Handle InHandle, FCk_DynamicFragment_RepNotifyInfo InInfo)
    {
        _NotifyFired  = true;
        _ReportedType = InInfo.ChangedType;
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        if (_NotifyFired)
        {
            Assert_True(_ReportedType == FCk_Fragment_DynamicTest_DynHandlePayload,
                "OnRepNotify should report the changed type as FCk_Fragment_DynamicTest_DynHandlePayload");

            auto Subject = Get_SubjectEntity();
            Assert_True(ck::IsValid(Subject) && Subject.Has_Fragment(FCk_Fragment_DynamicTest_DynHandlePayload),
                "the replicated dynamic fragment should exist on the client when OnRepNotify fires");

            const auto& Data = Subject.Get_Fragment(FCk_Fragment_DynamicTest_DynHandlePayload);
            Assert_Equals_Int(Data.Value, 5151,
                "the value must be readable (and correct) by the time OnRepNotify fires");

            // Use the dynamic handle's VALIDATED IsValid() (the method) — it checks the handle's
            // RequiredFragments, unlike ck::IsValid() which only checks entity validity. This is the
            // path where a dynamic handle behaves differently from a raw FCk_Handle.
            Assert_True(Data.TheHandle.IsValid(),
                "the dynamic handle's validated IsValid() should be true on the client (target carries Ck_Fragment_TESTONLY_HandleMarker)");
            Assert_True(Data.TheHandle == Subject,
                "the dynamic handle should resolve to the CLIENT's subject entity");

            FinishSuccess();
            return;
        }

        if (_PollCount > kPollBudget)
        { FinishFailure("client OnRepNotify never fired for the dynamic-handle replicated dynamic fragment"); return; }

        WaitOneFrame(n"OnPoll");
    }
}
