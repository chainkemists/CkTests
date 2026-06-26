// Language=angelscript

//============================================================================
// CK DYNAMIC — NET AUTOMATION TEST: DYNAMIC HANDLE, ASSERTED INSIDE OnRepNotify
//============================================================================
//
// Notify-DRIVEN variant of DynHandleReplicates. The poll-based tests read the handle
// in a timer loop that retries until it resolves — which would MASK a handle that is
// blank AT notify time but re-resolves a few frames later. The real consumer
// (StoreDriver's Reconcile_Subordinates) reads the handle INSIDE the OnRepNotify
// callback, so this test does the same: it asserts the handle resolves at the exact
// moment the callback fires. The timer here is only a "notify never fired" backstop.
//
// Self-target (handle -> subject). Expected to pass (subject is always mapped); it's
// the control for the DriverCarrierOnNotify separate-entity case.
//
// Surface: Ck.Dynamic.Net.AS_DynamicFragment_DynHandleOnNotify
//============================================================================

class UCk_AutoTest_Net_DynamicFragment_DynHandleOnNotify : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 10.0f;

    private int _PollCount = 0;
    private const int kPollBudget = 600;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        if (Subject.Has_Fragment(FCk_Fragment_TESTONLY_HandleMarker) == false)
        { Subject.Add_Fragment(FCk_Fragment_TESTONLY_HandleMarker(), ECk_Replication::DoesNotReplicate); }

        if (utils_net::Get_HasAuthority(Subject))
        {
            auto Payload = FCk_Fragment_DynamicTest_DynHandlePayload();
            Payload.Value = 909;
            Payload.TheHandle = Subject;
            Subject.Add_Fragment(Payload, ECk_Replication::Replicates);
            FinishSuccess();
            return;
        }

        Subject.BindTo_OnRepNotify(FCk_Fragment_DynamicTest_DynHandlePayload,
            FCk_DynamicFragment_OnRepNotify(this, n"OnRepNotify"));
        WaitOneFrame(n"OnTimeoutTick");
    }

    // The assertion happens HERE, at notify time — not in a retry loop.
    UFUNCTION()
    private void OnRepNotify(FCk_Handle InHandle, FCk_DynamicFragment_RepNotifyInfo InInfo)
    {
        if (IsFinished()) { return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject) || Subject.Has_Fragment(FCk_Fragment_DynamicTest_DynHandlePayload) == false)
        { FinishFailure("OnRepNotify fired but the dynamic fragment is missing on the client"); return; }

        const auto& Data = Subject.Get_Fragment(FCk_Fragment_DynamicTest_DynHandlePayload);
        Assert_Equals_Int(Data.Value, 909, "value must be readable at OnRepNotify time");
        Assert_True(Data.TheHandle.IsValid(),
            "the dynamic handle must resolve (validated) AT the moment OnRepNotify fires, not eventually");

        FinishSuccess();
    }

    // Backstop only: fail if OnRepNotify never fires within budget.
    UFUNCTION()
    private void OnTimeoutTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;
        if (_PollCount > kPollBudget)
        { FinishFailure("client OnRepNotify never fired (self-target dynamic handle)"); return; }
        WaitOneFrame(n"OnTimeoutTick");
    }
}
