// Language=angelscript

//============================================================================
// CK DYNAMIC — NET AUTOMATION TEST: RAW-HANDLE PROPERTY IN A REPLICATED DYN FRAGMENT
//============================================================================
//
// CONTROL case for the dynamic-handle repro. A replicated dynamic fragment whose
// payload carries a RAW FCk_Handle (pointed at the subject entity itself). The
// client binds OnRepNotify before the server authors, then asserts:
//   (1) OnRepNotify fired,
//   (2) it reported the correct changed type,
//   (3) the carried FCk_Handle resolves to the CLIENT's subject entity.
//
// Per the bug report, a raw FCk_Handle is expected to PASS — this test pins that
// baseline so the dynamic-handle variant's failure is unambiguously about the
// handle TYPE, not about handles-in-replicated-dynamic-fragments in general.
//
// Surface: Ck.Dynamic.Net.AS_DynamicFragment_RawHandleReplicates
//============================================================================

class UCk_AutoTest_Net_DynamicFragment_RawHandleReplicates : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 10.0f;

    private bool          _NotifyFired = false;
    private UScriptStruct _ReportedType;

    private int _PollCount = 0;
    private const int kPollBudget = 400;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject entity not found"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            auto Payload = FCk_Fragment_DynamicTest_RawHandlePayload();
            Payload.Value = 4242;
            Payload.TheHandle = Subject;
            Subject.Add_Fragment(Payload, ECk_Replication::Replicates);
            FinishSuccess();
            return;
        }

        // Client: bind BEFORE the replicated fragment arrives, then poll for the callback.
        Subject.BindTo_OnRepNotify(FCk_Fragment_DynamicTest_RawHandlePayload,
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
            Assert_True(_ReportedType == FCk_Fragment_DynamicTest_RawHandlePayload,
                "OnRepNotify should report the changed type as FCk_Fragment_DynamicTest_RawHandlePayload");

            auto Subject = Get_SubjectEntity();
            Assert_True(ck::IsValid(Subject) && Subject.Has_Fragment(FCk_Fragment_DynamicTest_RawHandlePayload),
                "the replicated dynamic fragment should exist on the client when OnRepNotify fires");

            const auto& Data = Subject.Get_Fragment(FCk_Fragment_DynamicTest_RawHandlePayload);
            Assert_Equals_Int(Data.Value, 4242,
                "the value must be readable (and correct) by the time OnRepNotify fires");

            Assert_True(ck::IsValid(Data.TheHandle),
                "the raw FCk_Handle carried by the replicated dynamic fragment should resolve valid on the client");
            Assert_True(Data.TheHandle == Subject,
                "the raw FCk_Handle should resolve to the CLIENT's subject entity");

            FinishSuccess();
            return;
        }

        if (_PollCount > kPollBudget)
        { FinishFailure("client OnRepNotify never fired for the raw-handle replicated dynamic fragment"); return; }

        WaitOneFrame(n"OnPoll");
    }
}
