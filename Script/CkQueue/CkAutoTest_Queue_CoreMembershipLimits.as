// Language=angelscript

class UCk_AutoTest_Queue_CoreMembershipLimits : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle       _MemberA;
    private FCk_Handle       _MemberB;
    private FCk_Handle       _MemberC;
    private FCk_Handle       _MemberD;
    private FCk_Handle       _RefreshedMover;
    private int32            _JoinDCompletionCount = 0;
    private ECk_Request_OperationResult _InitialJoinDResult = ECk_Request_OperationResult::Succeeded;
    private ECk_Request_OperationResult _RetryJoinDResult = ECk_Request_OperationResult::Failed;
    private int64            _TicketB = 0;
    private int64            _TicketC = 0;
    private int64            _TicketD = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform::Identity));
        auto Params = FCk_Fragment_Queue_ParamsData(Origins);
        Params.Set_SoftLimit(2);
        Params.Set_HardLimit(3);
        _Queue = utils_queue::Add(_Owner, Params);

        _MemberA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _MemberB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _MemberC = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _MemberD = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _RefreshedMover = utils_entity_lifetime::Request_CreateEntity(InHandle);

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join through the soft limit and contest the hard limit", n"Step_RequestJoins");
        Add_Step_WaitUntil("all join completions settle", n"Check_JoinsSettled");
        Add_Step("assert FIFO tickets and hard-limit refusal", n"Step_AssertInitialMembership");
        Add_Step("leave A, refresh B's mover, and suppress B", n"Step_RequestMutationBatch");
        Add_Step_WaitUntil("capacity opens without re-admitting the rejected member", n"Check_MutationBatchSettled");
        Add_Step("assert terminal rejection, compaction, mover refresh, and suppression", n"Step_AssertFinalMembership");
        Add_Step("explicitly retry the previously rejected member", n"Step_RequestExplicitRetry");
        Add_Step_WaitUntil("explicit retry is admitted into opened capacity", n"Check_ExplicitRetrySettled");
        Add_Step("assert planner-controlled retry receives a fresh ticket", n"Step_AssertExplicitRetry");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_QueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue) && _Queue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_RequestJoins(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Join(FCk_Request_Queue_Join(_MemberA));
        _Queue.Request_Join(FCk_Request_Queue_Join(_MemberB));
        _Queue.Request_Join(FCk_Request_Queue_Join(_MemberC));
        _Queue.Request_Join(FCk_Request_Queue_Join(_MemberD),
            FCk_Delegate_Request_OnCompleted(this, n"OnJoinDCompleted"));
    }

    UFUNCTION()
    private void OnJoinDCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _JoinDCompletionCount += 1;
        if (_JoinDCompletionCount == 1) { _InitialJoinDResult = InResult; }
        else { _RetryJoinDResult = InResult; }
    }

    UFUNCTION()
    private void Check_JoinsSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_JoinDCompletionCount == 1 && _Queue.Get_MemberCount() == 3);
    }

    UFUNCTION()
    private void Step_AssertInitialMembership(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Members = _Queue.Get_Members();
        Assert_Equals_Int(Members.Num(), 3, "hard limit admits exactly A, B, and C");
        Assert_True(Members[0].Get_Member() == _MemberA && Members[0].Get_Rank() == 0,
            "A is the FIFO front at rank zero");
        Assert_True(Members[1].Get_Member() == _MemberB && Members[1].Get_Rank() == 1,
            "B is second at rank one");
        Assert_True(Members[2].Get_Member() == _MemberC && Members[2].Get_Rank() == 2,
            "C is third at rank two");
        Assert_True(Members[0].Get_Ticket() < Members[1].Get_Ticket()
            && Members[1].Get_Ticket() < Members[2].Get_Ticket(),
            "FIFO admissions receive strictly increasing tickets");
        Assert_True(_Queue.Get_Pressure().Get_IsSoftLimited(),
            "soft limit reports pressure without refusing C");
        Assert_Equals_Int(_JoinDCompletionCount, 1, "hard-limit loser completes exactly once");
        Assert_True(_InitialJoinDResult == ECk_Request_OperationResult::Failed,
            "hard-limit loser receives explicit Failed completion");
        Assert_False(_Queue.Get_IsMember(_MemberD), "hard-limit loser never becomes a member");
        _TicketB = Members[1].Get_Ticket();
        _TicketC = Members[2].Get_Ticket();
    }

    UFUNCTION()
    private void Step_RequestMutationBatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Leave(FCk_Request_Queue_Leave(_MemberA));

        auto Rejoin = FCk_Request_Queue_Join(_MemberB);
        Rejoin.Set_Mover(_RefreshedMover);
        _Queue.Request_Join(Rejoin);

        _Queue.Request_SetMovementSuppressed(
            FCk_Request_Queue_SetMovementSuppressed(_MemberB, ECk_EnableDisable::Enable));
    }

    UFUNCTION()
    private void Check_MutationBatchSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasB = _Queue.TryGet_MemberSnapshot(_MemberB, Snapshot);
        auto Result = OutResult;
        Result.Set(HasB && _Queue.Get_MemberCount() == 2
            && Snapshot.Get_Mover() == _RefreshedMover
            && Snapshot.Get_MovementSuppressed()
            && _JoinDCompletionCount == 1
            && _Queue.Get_IsMember(_MemberD) == false);
    }

    UFUNCTION()
    private void Step_AssertFinalMembership(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Members = _Queue.Get_Members();
        Assert_Equals_Int(Members.Num(), 2, "leaving A compacts the queue");
        Assert_True(Members[0].Get_Member() == _MemberB && Members[0].Get_Rank() == 0,
            "B compacts to rank zero");
        Assert_True(Members[1].Get_Member() == _MemberC && Members[1].Get_Rank() == 1,
            "C compacts to rank one");
        Assert_True(Members[0].Get_Ticket() == _TicketB && Members[1].Get_Ticket() == _TicketC,
            "rejoining B refreshes only its mover, not either stable ticket");
        Assert_True(Members[0].Get_Mover() == _RefreshedMover,
            "idempotent rejoin adopts B's refreshed mover");
        Assert_True(Members[0].Get_MovementSuppressed(),
            "member-scoped suppression retains B's queue membership");
        Assert_False(Members[1].Get_MovementSuppressed(),
            "suppression does not leak to C");
        Assert_Equals_Int(_JoinDCompletionCount, 1,
            "opening capacity does not silently retry a hard-limit rejection");
        Assert_False(_Queue.Get_IsMember(_MemberD),
            "the rejected member remains outside the queue until its planner retries admission");
    }

    UFUNCTION()
    private void Step_RequestExplicitRetry(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Join(FCk_Request_Queue_Join(_MemberD),
            FCk_Delegate_Request_OnCompleted(this, n"OnJoinDCompleted"));
    }

    UFUNCTION()
    private void Check_ExplicitRetrySettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasD = _Queue.TryGet_MemberSnapshot(_MemberD, Snapshot);
        if (HasD) { _TicketD = Snapshot.Get_Ticket(); }
        auto Result = OutResult;
        Result.Set(_JoinDCompletionCount == 2
            && _RetryJoinDResult == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_MemberCount() == 3 && HasD);
    }

    UFUNCTION()
    private void Step_AssertExplicitRetry(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_RetryJoinDResult == ECk_Request_OperationResult::Succeeded,
            "a planner's explicit retry is admitted after capacity opens");
        Assert_True(_TicketD > _TicketC,
            "a previously rejected member receives a fresh monotonic ticket only when explicitly admitted");
        Assert_True(_Queue.Get_IsMember(_MemberD),
            "explicit retry publishes D as a real queue member");
    }
}
