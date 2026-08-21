// Language=angelscript

class UCk_AutoTest_Queue_EightMemberLinearHardLimit : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private TArray<FCk_Handle> _Members;
    private TArray<int64>      _Tickets;
    private TArray<int32>      _Ranks;
    private int32              _JoinCompletionCount = 0;
    private int32              _JoinSuccessCount = 0;
    private int32              _JoinFailureCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner,
            FTransform(FVector(700.0f, 0.0f, 0.0f)),
            ECk_Replication::DoesNotReplicate);

        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform(
            FRotator(0.0f, 180.0f, 0.0f), FVector(140.0f, 0.0f, 0.0f), FVector::OneVector)));
        auto Params = FCk_Fragment_Queue_ParamsData(Origins);
        Params.Set_HardLimit(8);
        Params.Set_LayoutAlgorithm(ECk_Queue_LayoutAlgorithm::Linear);
        Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ReserveOnFormation);
        _Queue = utils_queue::Add(_Owner, Params);

        for (int32 Index = 0; Index < 8; ++Index)
        {
            auto Member = utils_entity_lifetime::Request_CreateEntity(InHandle);
            utils_transform::Add(Member,
                FTransform(FVector(1000.0f + float32(Index) * 100.0f, 0.0f, 0.0f)),
                ECk_Replication::DoesNotReplicate);
            _Members.Add(Member);
        }

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("submit eight transform-bearing member and mover joins together", n"Step_RequestEightJoins");
        Add_Step_WaitUntil("all eight joins complete at the hard limit", n"Check_EightMembersHardLimited");
        Add_Step("capture the settled public member snapshots", n"Step_CaptureSnapshots");
        Add_Step("assert unique FIFO identities without further queue mutation", n"Step_AssertStableSnapshots");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_QueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue) && _Queue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_RequestEightJoins(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (const auto& Member : _Members)
        {
            auto Join = FCk_Request_Queue_Join(Member);
            Join.Set_Mover(Member);
            _Queue.Request_Join(Join, FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
        }
    }

    UFUNCTION()
    private void OnJoinCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _JoinCompletionCount += 1;
        if (InResult == ECk_Request_OperationResult::Succeeded) { _JoinSuccessCount += 1; }
        else { _JoinFailureCount += 1; }
    }

    UFUNCTION()
    private void Check_EightMembersHardLimited(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto Pressure = _Queue.Get_Pressure();
        const auto OriginCounts = Pressure.Get_OriginMemberCounts();
        const bool HasOneFullOrigin = OriginCounts.Num() == 1 && OriginCounts[0] == 8;
        auto Result = OutResult;
        Result.Set(_JoinCompletionCount == 8
            && _JoinSuccessCount == 8
            && _JoinFailureCount == 0
            && _Queue.Get_MemberCount() == 8
            && Pressure.Get_IsHardLimited()
            && HasOneFullOrigin);
    }

    UFUNCTION()
    private void Step_CaptureSnapshots(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Tickets.Empty();
        _Ranks.Empty();
        for (const auto& Member : _Members)
        {
            FCk_Queue_MemberSnapshot Snapshot;
            Assert_True(_Queue.TryGet_MemberSnapshot(Member, Snapshot),
                "every completed join publishes an observable member snapshot");
            _Tickets.Add(Snapshot.Get_Ticket());
            _Ranks.Add(Snapshot.Get_Rank());
        }
    }

    UFUNCTION()
    private void Step_AssertStableSnapshots(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_JoinCompletionCount, 8, "each submitted join completes exactly once");
        Assert_Equals_Int(_JoinSuccessCount, 8, "the hard-limit-sized batch succeeds without a refusal");
        Assert_Equals_Int(_JoinFailureCount, 0, "no member in the hard-limit-sized batch fails admission");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 8, "no mutation changes the full queue membership");
        Assert_True(_Queue.Get_Pressure().Get_IsHardLimited(),
            "pressure remains hard-limited at exactly eight members");

        for (int32 Index = 0; Index < _Members.Num(); ++Index)
        {
            FCk_Queue_MemberSnapshot Snapshot;
            Assert_True(_Queue.TryGet_MemberSnapshot(_Members[Index], Snapshot),
                "each original member remains represented after the complete batch");
            Assert_True(Snapshot.Get_Member() == _Members[Index] && Snapshot.Get_Mover() == _Members[Index],
                "each member retains its distinct transform-bearing mover");
            Assert_True(Snapshot.Get_OriginIndex() == 0 && Snapshot.Get_Rank() == _Ranks[Index],
                "the single origin retains each captured rank without a reflow mutation");
            Assert_True(Snapshot.Get_Ticket() == _Tickets[Index],
                "the settled public snapshot retains its captured ticket without mutation");
            Assert_Equals_Int(_Ranks[Index], Index,
                "rank follows the same-frame join submission order");
            if (Index > 0)
            {
                Assert_True(_Tickets[Index] > _Tickets[Index - 1],
                    "admission tickets increase monotonically with join submission order");
            }

            for (int32 Earlier = 0; Earlier < Index; ++Earlier)
            {
                Assert_True(_Tickets[Earlier] != _Tickets[Index],
                    "every member receives a unique admission ticket");
                Assert_True(_Ranks[Earlier] != _Ranks[Index],
                    "every member receives a unique rank at the single origin");
            }
        }
    }
}
