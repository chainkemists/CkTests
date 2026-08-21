// Language=angelscript

class UCk_AutoTest_Queue_OriginReflowRejectsStaleArrival : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle       _Member;
    private int32            _OldAssignmentRevision = 0;
    private int32            _NewAssignmentRevision = 0;
    private int32            _SlotReachedEvents = 0;
    private int32            _StaleCompletionCount = 0;
    private int32            _FreshCompletionCount = 0;
    private ECk_Request_OperationResult _StaleResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _FreshResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Queue = CreateQueue(_Owner, FTransform(FVector(200.0f, 0.0f, 0.0f)));
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));
        _Member = utils_entity_lifetime::Request_CreateEntity(InHandle);

        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join one member", n"Step_RequestJoin");
        Add_Step_WaitUntil("initial formation assigns a revision", n"Check_InitialAssignment");
        Add_Step("change the origin transform", n"Step_RequestOriginReflow");
        Add_Step_WaitUntil("origin reflow publishes a newer assignment", n"Check_ReflowedAssignment");
        Add_Step("report the old assignment as reached", n"Step_ReportStaleReached");
        Add_Step_WaitUntil("stale arrival is processed without changing queue state", n"Check_StaleArrivalIgnored");
        Add_Step("report the current assignment as reached", n"Step_ReportFreshReached");
        Add_Step_WaitUntil("current arrival reaches the front", n"Check_FreshArrivalApplied");
        Add_Step("assert revision-safe arrival reporting", n"Step_AssertRevisionSafety");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue == _Queue && InEvent.Get_Member().Get_Member() == _Member
            && InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached)
        { _SlotReachedEvents += 1; }
    }

    UFUNCTION()
    private void OnStaleCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _StaleCompletionCount += 1;
        _StaleResult = InResult;
    }

    UFUNCTION()
    private void OnFreshCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _FreshCompletionCount += 1;
        _FreshResult = InResult;
    }

    UFUNCTION()
    private void Check_QueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue) && _Queue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_RequestJoin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Join(FCk_Request_Queue_Join(_Member));
    }

    UFUNCTION()
    private void Check_InitialAssignment(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(_Member, Snapshot);
        auto Result = OutResult;
        Result.Set(HasSnapshot && Snapshot.Get_AssignmentRevision() > 0
            && Snapshot.Get_State() == ECk_Queue_MemberState::Assigned);
    }

    UFUNCTION()
    private void Step_RequestOriginReflow(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        Assert_True(_Queue.TryGet_MemberSnapshot(_Member, Snapshot),
            "member has an initial assigned snapshot before reflow");
        _OldAssignmentRevision = Snapshot.Get_AssignmentRevision();

        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform(FVector(360.0f, 0.0f, 0.0f))));
        _Queue.Request_SetOrigins(FCk_Request_Queue_SetOrigins(Origins));
    }

    UFUNCTION()
    private void Check_ReflowedAssignment(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(_Member, Snapshot);
        auto Result = OutResult;
        Result.Set(HasSnapshot && Snapshot.Get_AssignmentRevision() > _OldAssignmentRevision
            && Snapshot.Get_State() == ECk_Queue_MemberState::Assigned);
    }

    UFUNCTION()
    private void Step_ReportStaleReached(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        Assert_True(_Queue.TryGet_MemberSnapshot(_Member, Snapshot),
            "member remains present after origin reflow");
        _NewAssignmentRevision = Snapshot.Get_AssignmentRevision();
        _Queue.Request_ReportMovementOutcome(
            FCk_Request_Queue_ReportMovementOutcome(
                _Member, _OldAssignmentRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnStaleCompleted"));
    }

    UFUNCTION()
    private void Check_StaleArrivalIgnored(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(_Member, Snapshot);
        auto Result = OutResult;
        Result.Set(_StaleCompletionCount == 1 && HasSnapshot
            && Snapshot.Get_AssignmentRevision() == _NewAssignmentRevision
            && Snapshot.Get_State() == ECk_Queue_MemberState::Assigned
            && _SlotReachedEvents == 0);
    }

    UFUNCTION()
    private void Step_ReportFreshReached(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_ReportMovementOutcome(
            FCk_Request_Queue_ReportMovementOutcome(
                _Member, _NewAssignmentRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnFreshCompleted"));
    }

    UFUNCTION()
    private void Check_FreshArrivalApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(_Member, Snapshot);
        auto Result = OutResult;
        Result.Set(_FreshCompletionCount == 1 && HasSnapshot
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && _SlotReachedEvents == 1);
    }

    UFUNCTION()
    private void Step_AssertRevisionSafety(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_StaleResult == ECk_Request_OperationResult::Succeeded,
            "stale outcome drains as an idempotent no-op rather than failing the caller");
        Assert_True(_FreshResult == ECk_Request_OperationResult::Succeeded,
            "current outcome succeeds after the reflowed assignment is published");
        Assert_Equals_Int(_SlotReachedEvents, 1,
            "only the current assignment revision may mark the member arrived");
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle& InOwner, FTransform InOriginTransform)
    {
        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(InOriginTransform));
        return utils_queue::Add(InOwner, FCk_Fragment_Queue_ParamsData(Origins));
    }
}
