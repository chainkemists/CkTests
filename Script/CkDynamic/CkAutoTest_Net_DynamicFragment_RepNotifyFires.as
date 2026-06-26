// Language=angelscript

//============================================================================
// CK DYNAMIC — NET AUTOMATION TEST: OnRepNotify CALLBACK FIRES ON CLIENT
//============================================================================
//
// Pins the BindTo_OnRepNotify contract specifically (the data-arrival tests
// only poll Get_Fragment). The client binds OnRepNotify BEFORE the server
// authors the fragment, then asserts the bound delegate actually fired, that
// it reported the correct changed UScriptStruct, and that the value is
// readable by the time the notify lands.
//
// Surface: Ck.Dynamic.Net.AS_DynamicFragment_RepNotifyFires
//============================================================================

class UCk_AutoTest_Net_DynamicFragment_RepNotifyFires : UCk_AutoTest_NetBase
{
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
            auto Payload = FCk_Fragment_DynamicTest_Payload();
            Payload.Value = 909;
            Payload.Label = "notify";
            Subject.Add_Fragment(Payload, ECk_Replication::Replicates);
            FinishSuccess();
            return;
        }

        // Client: bind BEFORE the replicated fragment arrives so the normal broadcast
        // (not an in-flight replay) invokes the delegate, then poll for the callback.
        Subject.BindTo_OnRepNotify(FCk_Fragment_DynamicTest_Payload,
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
            Assert_True(_ReportedType == FCk_Fragment_DynamicTest_Payload,
                "OnRepNotify should report the changed type as FCk_Fragment_DynamicTest_Payload");

            auto Subject = Get_SubjectEntity();
            Assert_True(ck::IsValid(Subject) && Subject.Has_Fragment(FCk_Fragment_DynamicTest_Payload),
                "the replicated dynamic fragment should exist on the client when OnRepNotify fires");

            const auto& Data = Subject.Get_Fragment(FCk_Fragment_DynamicTest_Payload);
            Assert_Equals_Int(Data.Value, 909,
                "the value must be readable (and correct) by the time OnRepNotify fires");

            FinishSuccess();
            return;
        }

        if (_PollCount > kPollBudget)
        { FinishFailure("client OnRepNotify never fired for the replicated dynamic fragment"); return; }

        WaitOneFrame(n"OnPoll");
    }
}
