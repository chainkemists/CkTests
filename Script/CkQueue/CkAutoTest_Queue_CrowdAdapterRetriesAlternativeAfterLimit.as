// Language=angelscript

class UCk_AutoTest_Queue_CrowdAdapterRetriesAlternativeAfterLimit : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _OwnerA;
    private FCk_Handle _OwnerB;
    private FCk_Handle_Queue _QueueA;
    private FCk_Handle_Queue _QueueB;
    private FCk_Handle _ExistingMember;
    private FCk_Handle _AgentEntity;
    private FCk_Handle_CrowdAgent _Agent;
    private FVector _Spawn;
    private int32 _RejectedCompletions = 0;
    private int32 _FallbackCompletions = 0;
    private int32 _HardLimitEvents = 0;
    private ECk_Request_OperationResult _RejectedResult = ECk_Request_OperationResult::Succeeded;
    private ECk_Request_OperationResult _FallbackResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Context = InHandle;
        utils_transform::Add(Context, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(Context);

        Add_Step_WaitUntil("agent spawn is navigable", n"Check_NavigationReady");
        Add_Step("compose a full queue, a fallback queue, and one CrowdAgent", n"Step_Compose");
        Add_Step_WaitUntil("both queues finish setup", n"Check_QueuesReady");
        Add_Step("fill the first queue", n"Step_FillFirstQueue");
        Add_Step_WaitUntil("first queue reaches its hard limit", n"Check_FirstQueueFull");
        Add_Step("request the full queue through the Crowd adapter", n"Step_RequestRejectedJoin");
        Add_Step_WaitUntil("rejection callback joins the fallback queue", n"Check_FallbackJoined");
        Add_Step("assert planner-visible rejection and immediate alternative", n"Step_AssertFallbackContract");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnQueueAEvent(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue == _QueueA
            && InEvent.Get_Reason() == ECk_Queue_EventReason::HardLimitReached
            && InEvent.Get_Member().Get_Member() == FCk_Handle(_Agent))
        { _HardLimitEvents += 1; }
    }

    UFUNCTION()
    private void OnRejectedCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RejectedCompletions += 1;
        _RejectedResult = InResult;
        if (InResult == ECk_Request_OperationResult::Failed)
        {
            _Agent.Request_JoinQueue(
                _QueueB,
                FCk_Delegate_Request_OnCompleted(this, n"OnFallbackCompleted"));
        }
    }

    UFUNCTION()
    private void OnFallbackCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _FallbackCompletions += 1;
        _FallbackResult = InResult;
    }

    UFUNCTION()
    private void Check_NavigationReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FVector Projected;
        auto Context = InHandle;
        const bool Projects = utils_nav::Try_ProjectOntoNavmesh(
            Context,
            FVector(-400.0f, 0.0f, 0.0f),
            100.0f,
            Projected,
            300.0f);
        if (Projects) { _Spawn = Projected; }
        auto Result = OutResult;
        Result.Set(Projects);
    }

    UFUNCTION()
    private void Step_Compose(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _OwnerA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _OwnerB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_OwnerA, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        utils_transform::Add(_OwnerB, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _QueueA = CreateQueue(_OwnerA, FVector(200.0f, 0.0f, 0.0f), 1);
        _QueueB = CreateQueue(_OwnerB, FVector(500.0f, 0.0f, 0.0f), 2);
        _QueueA.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnQueueAEvent"));

        _ExistingMember = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto AgentTransform = utils_transform::Add(
            _AgentEntity,
            FTransform(FRotator::ZeroRotator, _Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _Agent = utils_crowd_agent::Add(
            AgentTransform,
            FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f));
        utils_velocity::Add(
            _AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(
            _AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);
    }

    UFUNCTION()
    private void Check_QueuesReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_QueueA) && ck::IsValid(_QueueB)
            && _QueueA.Get_State() == ECk_Queue_State::Ready
            && _QueueB.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_FillFirstQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _QueueA.Request_Join(FCk_Request_Queue_Join(_ExistingMember));
    }

    UFUNCTION()
    private void Check_FirstQueueFull(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_QueueA.Get_MemberCount() == 1 && _QueueA.Get_Pressure().Get_IsHardLimited());
    }

    UFUNCTION()
    private void Step_RequestRejectedJoin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Agent.Request_JoinQueue(
            _QueueA,
            FCk_Delegate_Request_OnCompleted(this, n"OnRejectedCompleted"));
    }

    UFUNCTION()
    private void Check_FallbackJoined(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_RejectedCompletions == 1 && _FallbackCompletions == 1
            && _HardLimitEvents == 1
            && _QueueA.Get_IsMember(FCk_Handle(_Agent)) == false
            && _QueueB.Get_IsMember(FCk_Handle(_Agent)));
    }

    UFUNCTION()
    private void Step_AssertFallbackContract(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_RejectedResult == ECk_Request_OperationResult::Failed,
            "full queue reports a planner-visible Failed completion");
        Assert_True(_FallbackResult == ECk_Request_OperationResult::Succeeded,
            "the rejection callback can immediately request a different queue");
        Assert_Equals_Int(_RejectedCompletions, 1, "rejected join completes exactly once");
        Assert_Equals_Int(_FallbackCompletions, 1, "fallback join completes exactly once");
        Assert_Equals_Int(_HardLimitEvents, 1, "hard rejection emits exactly one semantic event");
        Assert_False(_QueueA.Get_IsMember(FCk_Handle(_Agent)),
            "rejected adapter join creates no partial membership in the full queue");
        Assert_True(_QueueB.Get_IsMember(FCk_Handle(_Agent)),
            "the same CrowdAgent is admitted to the fallback queue");
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle& InOwner, FVector InOrigin, int32 InHardLimit)
    {
        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform(InOrigin)));
        auto Params = FCk_Fragment_Queue_ParamsData(Origins);
        Params.Set_SoftLimit(InHardLimit);
        Params.Set_HardLimit(InHardLimit);
        return utils_queue::Add(InOwner, Params);
    }
}
