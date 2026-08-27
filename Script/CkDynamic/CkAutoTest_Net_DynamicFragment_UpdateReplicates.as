// Language=angelscript

//============================================================================
// CK DYNAMIC - NET AUTOMATION TEST: REPLICATED DYNAMIC FRAGMENT UPDATE
//============================================================================
//
// Server adds a replicated dynamic fragment (Value=111), lets it settle, then
// mutates it in-place via Get_Fragment and calls Request_MarkReplicationDirty
// (Value=222). The client polls until it observes the UPDATED value, proving
// the host-driven re-replication path (MarkReplicationDirty -> server Replicate
// processor -> SetFragmentData_Runtime -> client OnChange) works.
//
// Surface: Ck.Dynamic.Net.AS_DynamicFragment_UpdateReplicates
//============================================================================

class UCk_AutoTest_Net_DynamicFragment_UpdateReplicates : UCk_AutoTest_NetBase
{
    default _TimeoutSeconds = 10.0f;

    private int _ServerFrame = 0;
    private const int kServerUpdateFrame = 20;

    private int _PollCount = 0;
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
            auto Payload = FCk_Fragment_DynamicTest_Payload();
            Payload.Value = 111;
            Payload.Label = "initial";
            Subject.Add_Fragment(Payload, ECk_Replication::Replicates);
            WaitOneFrame(n"OnServerTick");
            return;
        }

        WaitOneFrame(n"OnClientPoll");
    }

    // Wait a handful of frames so the initial value fully replicates (exercising the
    // OnAdd path on the client) before mutating, so the update goes through OnChange.
    UFUNCTION()
    private void OnServerTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ServerFrame++;
        if (_ServerFrame < kServerUpdateFrame)
        { WaitOneFrame(n"OnServerTick"); return; }

        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("server lost the subject entity"); return; }

        auto& Data = Subject.Get_Fragment(FCk_Fragment_DynamicTest_Payload);
        Data.Value = 222;
        Subject.Request_MarkReplicationDirty(FCk_Fragment_DynamicTest_Payload);

        FinishSuccess();
    }

    UFUNCTION()
    private void OnClientPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        auto Subject = Get_SubjectEntity();
        if (ck::IsValid(Subject) && Subject.Has_Fragment(FCk_Fragment_DynamicTest_Payload))
        {
            const auto& Data = Subject.Get_Fragment(FCk_Fragment_DynamicTest_Payload);
            if (Data.Value == 222)
            {
                FinishSuccess();
                return;
            }
        }

        if (_PollCount > kPollBudget)
        { FinishFailure("client never received the updated dynamic fragment value (222)"); return; }

        WaitOneFrame(n"OnClientPoll");
    }
}
