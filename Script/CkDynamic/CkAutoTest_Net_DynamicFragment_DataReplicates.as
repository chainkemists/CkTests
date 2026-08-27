// Language=angelscript

//============================================================================
// CK DYNAMIC - NET AUTOMATION TEST: REPLICATED DYNAMIC FRAGMENT DATA ARRIVES
//============================================================================
//
// Server adds a dynamic fragment with ECk_Replication::Replicates on the
// NetSubject and stamps a known value. The client polls until the fragment
// exists on its replicated subject and Get_Fragment observes the server's
// value - proving the runtime push (SetFragmentData_Runtime) + fallback
// handler + SyncReplication processor pipeline round-trips the payload.
//
// Surface: Ck.Dynamic.Net.AS_DynamicFragment_DataReplicates
//============================================================================

class UCk_AutoTest_Net_DynamicFragment_DataReplicates : UCk_AutoTest_NetBase
{
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
            Payload.Value = 777;
            Payload.Label = "replicated";
            Subject.Add_Fragment(Payload, ECk_Replication::Replicates);
            FinishSuccess();
            return;
        }

        WaitOneFrame(n"OnPoll");
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        auto Subject = Get_SubjectEntity();
        if (ck::IsValid(Subject) && Subject.Has_Fragment(FCk_Fragment_DynamicTest_Payload))
        {
            const auto& Data = Subject.Get_Fragment(FCk_Fragment_DynamicTest_Payload);
            if (Data.Value == 777)
            {
                Assert_Equals_String(Data.Label, "replicated",
                    "replicated dynamic fragment label should match the server's value");
                FinishSuccess();
                return;
            }
        }

        if (_PollCount > kPollBudget)
        { FinishFailure("client never received the replicated dynamic fragment value"); return; }

        WaitOneFrame(n"OnPoll");
    }
}
