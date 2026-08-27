// Language=angelscript

class UCk_AutoTest_Queue_ReentrantRequestsSurviveDrain : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle       _First;
    private FCk_Handle       _Next;
    private int32            _SlotReachedEvents = 0;
    private int32            _AdvancedEvents = 0;
    private int32            _EarlyAdvanceCompletions = 0;
    private int32            _AdvanceCompletions = 0;
    private int32            _SuppressCompletions = 0;
    private ECk_Request_OperationResult _EarlyAdvanceResult = ECk_Request_OperationResult::Succeeded;
    private ECk_Request_OperationResult _AdvanceResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _SuppressResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Queue = CreateQueue(_Owner);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));

        _First = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Next = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join two members", n"Step_RequestJoins");
        Add_Step_WaitUntil("both members are admitted", n"Check_BothMembersPresent");
        Add_Step("request advance before the front reports arrival", n"Step_RequestEarlyAdvance");
        Add_Step_WaitUntil("early advance fails without removing the unarrived front", n"Check_EarlyAdvanceRejected");
        Add_Step("report the first slot reached", n"Step_ReportFirstReached");
        Add_Step_WaitUntil("reentrant advance and suppression settle", n"Check_ReentrantRequestsSettled");
        Add_Step("assert each reentrant request landed once", n"Step_AssertReentrantResult");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue != _Queue) { return; }

        const auto Member = InEvent.Get_Member().Get_Member();
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached && Member == _First)
        {
            _SlotReachedEvents += 1;
            _Queue.Request_Advance(FCk_Request_Queue_Advance(),
                FCk_Delegate_Request_OnCompleted(this, n"OnAdvanceCompleted"));
        }
        else if (InEvent.Get_Reason() == ECk_Queue_EventReason::Advanced && Member == _First)
        {
            _AdvancedEvents += 1;
            _Queue.Request_SetMovementSuppressed(
                FCk_Request_Queue_SetMovementSuppressed(_Next, ECk_EnableDisable::Enable),
                FCk_Delegate_Request_OnCompleted(this, n"OnSuppressCompleted"));
        }
    }

    UFUNCTION()
    private void OnAdvanceCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _AdvanceCompletions += 1;
        _AdvanceResult = InResult;
    }

    UFUNCTION()
    private void OnEarlyAdvanceCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _EarlyAdvanceCompletions += 1;
        _EarlyAdvanceResult = InResult;
    }

    UFUNCTION()
    private void OnSuppressCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _SuppressCompletions += 1;
        _SuppressResult = InResult;
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
        _Queue.Request_Join(FCk_Request_Queue_Join(_First));
        _Queue.Request_Join(FCk_Request_Queue_Join(_Next));
    }

    UFUNCTION()
    private void Check_BothMembersPresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot First;
        const bool HasFirst = _Queue.TryGet_MemberSnapshot(_First, First);
        auto Result = OutResult;
        Result.Set(_Queue.Get_MemberCount() == 2 && HasFirst
            && First.Get_AssignmentRevision() > 0
            && First.Get_State() == ECk_Queue_MemberState::Assigned);
    }

    UFUNCTION()
    private void Step_ReportFirstReached(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot First;
        Assert_True(_Queue.TryGet_MemberSnapshot(_First, First), "first member snapshot exists before reporting arrival");
        _Queue.Request_ReportMovementOutcome(
            FCk_Request_Queue_ReportMovementOutcome(
                _First, First.Get_AssignmentRevision(), ECk_Queue_MovementOutcome::Reached));
    }

    UFUNCTION()
    private void Step_RequestEarlyAdvance(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Advance(FCk_Request_Queue_Advance(),
            FCk_Delegate_Request_OnCompleted(this, n"OnEarlyAdvanceCompleted"));
    }

    UFUNCTION()
    private void Check_EarlyAdvanceRejected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot First;
        const bool HasFirst = _Queue.TryGet_MemberSnapshot(_First, First);
        auto Result = OutResult;
        Result.Set(_EarlyAdvanceCompletions == 1
            && _EarlyAdvanceResult == ECk_Request_OperationResult::Failed
            && _Queue.Get_MemberCount() == 2 && HasFirst
            && First.Get_State() == ECk_Queue_MemberState::Assigned);
    }

    UFUNCTION()
    private void Check_ReentrantRequestsSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Next;
        const bool HasNext = _Queue.TryGet_MemberSnapshot(_Next, Next);
        auto Result = OutResult;
        Result.Set(_SlotReachedEvents == 1 && _AdvancedEvents == 1
            && _AdvanceCompletions == 1 && _SuppressCompletions == 1
            && _AdvanceResult == ECk_Request_OperationResult::Succeeded
            && _SuppressResult == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_MemberCount() == 1 && HasNext && Next.Get_Rank() == 0
            && Next.Get_MovementSuppressed());
    }

    UFUNCTION()
    private void Step_AssertReentrantResult(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_SlotReachedEvents, 1, "first member reached its slot exactly once");
        Assert_Equals_Int(_EarlyAdvanceCompletions, 1, "advance before AtFront completes exactly once");
        Assert_True(_EarlyAdvanceResult == ECk_Request_OperationResult::Failed,
            "advance before AtFront is rejected without serving or removing the front");
        Assert_Equals_Int(_AdvancedEvents, 1, "next member advanced exactly once");
        Assert_Equals_Int(_AdvanceCompletions, 1, "SlotReached callback's advance completes exactly once");
        Assert_Equals_Int(_SuppressCompletions, 1, "Advanced callback's suppression completes exactly once");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 1, "advance removes only the served front member");
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle& InOwner)
    {
        utils_transform::Request_SetLocation(InOwner.As_Transform(), FVector(200.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
        return utils_queue::Add(InOwner, FCk_Fragment_Queue_ParamsData());
    }
}
