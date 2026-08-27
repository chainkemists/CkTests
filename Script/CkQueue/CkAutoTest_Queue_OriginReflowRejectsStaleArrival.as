// Language=angelscript

class UCk_AutoTest_Queue_OriginReflowRejectsStaleArrival : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle       _FailedFront;
    private FCk_Handle       _LaterMember;
    private int32            _PreReflowAssignmentRevision = 0;
    private int32            _FailedFrontAssignmentRevision = 0;
    private int32            _LaterAssignmentRevision = 0;
    private int32            _StaleCompletionCount = 0;
    private int32            _LaterReachedCompletionCount = 0;
    private int32            _SlotReachedEvents = 0;
    private ECk_Request_OperationResult _StaleResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _LaterReachedResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform(FVector(200.0f, 0.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
        _Queue = CreateQueue(_Owner);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));
        _FailedFront = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _LaterMember = utils_entity_lifetime::Request_CreateEntity(InHandle);

        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join an initially reserved front and a later viable member", n"Step_RequestJoins");
        Add_Step_WaitUntil("reserve-on-formation assigns the initial front", n"Check_InitialFrontAssignment");
        Add_Step("move the Queue owner target to force a fresh reservation revision", n"Step_RequestOwnerTransformReflow");
        Add_Step_WaitUntil("owner-target reflow publishes a newer front reservation", n"Check_ReflowedFrontAssignment");
        Add_Step("report the pre-owner-reflow reservation as reached", n"Step_ReportPreReflowStaleArrival");
        Add_Step_WaitUntil("pre-owner-reflow arrival is ignored without changing the current reservation", n"Check_PreReflowStaleArrivalIgnored");
        Add_Step("report movement failure for the reserved front", n"Step_ReportFrontFailure");
        Add_Step_WaitUntil("failed front yields rank zero to the later viable member", n"Check_FailurePromotesLaterMember");
        Add_Step("report the failed front's stale old arrival", n"Step_ReportStaleFailedFrontArrival");
        Add_Step_WaitUntil("stale failed-front arrival is ignored", n"Check_StaleArrivalIgnored");
        Add_Step("report the promoted member reaching the front", n"Step_ReportPromotedMemberReached");
        Add_Step_WaitUntil("promoted member reaches the queue front", n"Check_PromotedMemberReached");
        Add_Step("assert failure handoff and revision safety", n"Step_AssertFailureHandoff");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue == _Queue && InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached)
        { _SlotReachedEvents += 1; }
    }

    UFUNCTION()
    private void OnStaleCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _StaleCompletionCount += 1;
        _StaleResult = InResult;
    }

    UFUNCTION()
    private void OnLaterReachedCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LaterReachedCompletionCount += 1;
        _LaterReachedResult = InResult;
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
        _Queue.Request_Join(FCk_Request_Queue_Join(_FailedFront));
        _Queue.Request_Join(FCk_Request_Queue_Join(_LaterMember));
    }

    UFUNCTION()
    private void Check_InitialFrontAssignment(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot FailedFront;
        FCk_Queue_MemberSnapshot Later;
        const bool HasFailedFront = _Queue.TryGet_MemberSnapshot(_FailedFront, FailedFront);
        const bool HasLater = _Queue.TryGet_MemberSnapshot(_LaterMember, Later);
        if (HasFailedFront) { _PreReflowAssignmentRevision = FailedFront.Get_AssignmentRevision(); }
        auto Result = OutResult;
        Result.Set(HasFailedFront && HasLater && _PreReflowAssignmentRevision > 0
            && FailedFront.Get_Rank() == 0
            && (FailedFront.Get_State() == ECk_Queue_MemberState::Assigned
                || FailedFront.Get_State() == ECk_Queue_MemberState::MovingToSlot));
    }

    UFUNCTION()
    private void Step_RequestOwnerTransformReflow(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_transform::Request_SetLocation(_Owner.As_Transform(), FVector(360.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void Check_ReflowedFrontAssignment(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot FailedFront;
        const bool HasFailedFront = _Queue.TryGet_MemberSnapshot(_FailedFront, FailedFront);
        if (HasFailedFront) { _FailedFrontAssignmentRevision = FailedFront.Get_AssignmentRevision(); }
        auto Result = OutResult;
        Result.Set(HasFailedFront && _FailedFrontAssignmentRevision > _PreReflowAssignmentRevision
            && FailedFront.Get_Rank() == 0
            && (FailedFront.Get_State() == ECk_Queue_MemberState::Assigned
                || FailedFront.Get_State() == ECk_Queue_MemberState::MovingToSlot));
    }

    UFUNCTION()
    private void Step_ReportPreReflowStaleArrival(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_ReportMovementOutcome(
            FCk_Request_Queue_ReportMovementOutcome(
                _FailedFront, _PreReflowAssignmentRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnStaleCompleted"));
    }

    UFUNCTION()
    private void Check_PreReflowStaleArrivalIgnored(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot FailedFront;
        const bool HasFailedFront = _Queue.TryGet_MemberSnapshot(_FailedFront, FailedFront);
        auto Result = OutResult;
        Result.Set(_StaleCompletionCount == 1 && HasFailedFront
            && FailedFront.Get_AssignmentRevision() == _FailedFrontAssignmentRevision
            && (FailedFront.Get_State() == ECk_Queue_MemberState::Assigned
                || FailedFront.Get_State() == ECk_Queue_MemberState::MovingToSlot)
            && _SlotReachedEvents == 0);
    }

    UFUNCTION()
    private void Step_ReportFrontFailure(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_ReportMovementOutcome(
            FCk_Request_Queue_ReportMovementOutcome(
                _FailedFront, _FailedFrontAssignmentRevision, ECk_Queue_MovementOutcome::Failed));
    }

    UFUNCTION()
    private void Check_FailurePromotesLaterMember(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot FailedFront;
        FCk_Queue_MemberSnapshot Later;
        const bool HasFailedFront = _Queue.TryGet_MemberSnapshot(_FailedFront, FailedFront);
        const bool HasLater = _Queue.TryGet_MemberSnapshot(_LaterMember, Later);
        if (HasLater) { _LaterAssignmentRevision = Later.Get_AssignmentRevision(); }
        auto Result = OutResult;
        Result.Set(HasFailedFront && HasLater
            && FailedFront.Get_State() == ECk_Queue_MemberState::WaitingForNavigationChange
            && FailedFront.Get_AssignmentRevision() == 0
            && Later.Get_Rank() == 0 && _LaterAssignmentRevision > _FailedFrontAssignmentRevision
            && (Later.Get_State() == ECk_Queue_MemberState::Assigned
                || Later.Get_State() == ECk_Queue_MemberState::MovingToSlot));
    }

    UFUNCTION()
    private void Step_ReportStaleFailedFrontArrival(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_ReportMovementOutcome(
            FCk_Request_Queue_ReportMovementOutcome(
                _FailedFront, _FailedFrontAssignmentRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnStaleCompleted"));
    }

    UFUNCTION()
    private void Check_StaleArrivalIgnored(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot FailedFront;
        FCk_Queue_MemberSnapshot Later;
        const bool HasFailedFront = _Queue.TryGet_MemberSnapshot(_FailedFront, FailedFront);
        const bool HasLater = _Queue.TryGet_MemberSnapshot(_LaterMember, Later);
        auto Result = OutResult;
        Result.Set(_StaleCompletionCount == 2 && HasFailedFront && HasLater
            && FailedFront.Get_State() == ECk_Queue_MemberState::WaitingForNavigationChange
            && FailedFront.Get_AssignmentRevision() == 0
            && Later.Get_Rank() == 0 && Later.Get_AssignmentRevision() == _LaterAssignmentRevision
            && _SlotReachedEvents == 0);
    }

    UFUNCTION()
    private void Step_ReportPromotedMemberReached(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_ReportMovementOutcome(
            FCk_Request_Queue_ReportMovementOutcome(
                _LaterMember, _LaterAssignmentRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnLaterReachedCompleted"));
    }

    UFUNCTION()
    private void Check_PromotedMemberReached(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Later;
        const bool HasLater = _Queue.TryGet_MemberSnapshot(_LaterMember, Later);
        auto Result = OutResult;
        Result.Set(_LaterReachedCompletionCount == 1 && HasLater
            && Later.Get_State() == ECk_Queue_MemberState::AtFront && _SlotReachedEvents == 1);
    }

    UFUNCTION()
    private void Step_AssertFailureHandoff(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_StaleResult == ECk_Request_OperationResult::Succeeded,
            "both pre-owner-reflow and failed-reservation stale arrivals drain as revision-safe no-ops");
        Assert_Equals_Int(_StaleCompletionCount, 2,
            "the pre-owner-reflow and failed-reservation stale arrivals each complete exactly once");
        Assert_True(_LaterReachedResult == ECk_Request_OperationResult::Succeeded,
            "the later viable member may report reaching its promoted front reservation");
        Assert_Equals_Int(_SlotReachedEvents, 1,
            "only the promoted member reaches the front after the initial reservation fails");
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle& InOwner)
    {
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ReserveOnFormation);
        return utils_queue::Add(InOwner, Params);
    }
}
