// Language=angelscript

class UCk_AutoTest_Queue_OwnerDestroyInvalidatesMembers : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle       _FallbackOwner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle_Queue _FallbackQueue;
    private FCk_Handle       _CrowdEntity;
    private FCk_Handle_CrowdAgent _CrowdAgent;
    private FVector                _Spawn;
    private FVector                _QueueTarget;
    private FCk_Handle       _MemberA;
    private FCk_Handle       _MemberB;
    private int32            _OwnerDestroyedMemberEvents = 0;
    private int32            _InvalidationEvents = 0;
    private int32            _CrowdAssignmentRevision = 0;
    private int32            _CrowdSlotReachedEvents = 0;
    private int32            _FallbackJoinCompletions = 0;
    private ECk_Request_OperationResult _FallbackJoinResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        Add_Step_WaitUntil("spawn and queue target project onto navmesh", n"Check_NavigationReady");
        Add_Step("compose projected queue owners and Crowd member", n"Step_ComposeQueueAndMembers");
        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join a Crowd adapter and one survivor member", n"Step_RequestJoins");
        Add_Step_WaitUntil("Crowd adapter owns an assigned queue move", n"Check_CrowdAssignmentIssued");
        Add_Step("teleport Crowd into its claim radius and destroy the queue owner", n"Step_MoveCrowdToAssignedTargetAndDestroyOwner");
        Add_Step_WaitUntil("owner teardown invalidates the queue and both members", n"Check_OwnerTeardownSettled");
        Add_Step("join the surviving CrowdAgent to a fallback queue", n"Step_RequestFallbackJoin");
        Add_Step_WaitUntil("surviving CrowdAgent joins the fallback without an old Queue outcome", n"Check_FallbackJoined");
        Add_Step("assert owner teardown events are exactly once", n"Step_AssertOwnerTeardown");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_NavigationReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FVector SpawnOnMesh;
        FVector TargetOnMesh;
        const bool SpawnIsNavigable = utils_nav::Try_ProjectOntoNavmesh(
            InHandle, FVector(-400.0f, 0.0f, 0.0f), 100.0f, SpawnOnMesh, 300.0f);
        const bool TargetIsNavigable = utils_nav::Try_ProjectOntoNavmesh(
            InHandle, FVector(600.0f, 0.0f, 0.0f), 100.0f, TargetOnMesh, 300.0f);
        if (SpawnIsNavigable && TargetIsNavigable)
        {
            _Spawn = SpawnOnMesh;
            _QueueTarget = TargetOnMesh;
        }
        auto Result = OutResult;
        Result.Set(SpawnIsNavigable && TargetIsNavigable);
    }

    UFUNCTION()
    private void Step_ComposeQueueAndMembers(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _FallbackOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner,
            FTransform(FRotator::ZeroRotator, _QueueTarget, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_transform::Add(_FallbackOwner,
            FTransform(FRotator::ZeroRotator, _QueueTarget, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _Queue = CreateQueue(_Owner);
        _FallbackQueue = CreateQueue(_FallbackOwner);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));
        _Queue.BindTo_OnQueueInvalidated(
            FCk_Delegate_Queue_OnInvalidated(this, n"OnQueueInvalidated"));

        _CrowdEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto CrowdTransform = utils_transform::Add(_CrowdEntity,
            FTransform(FRotator::ZeroRotator, _Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _CrowdAgent = utils_crowd_agent::Add(CrowdTransform,
            FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f));
        utils_velocity::Add(_CrowdEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_CrowdEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_CrowdEntity);
        _MemberA = FCk_Handle(_CrowdAgent);
        _MemberB = utils_entity_lifetime::Request_CreateEntity(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        const auto Member = InEvent.Get_Member().Get_Member();
        if (InQueue == _Queue && InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached
            && Member == FCk_Handle(_CrowdAgent))
        { _CrowdSlotReachedEvents += 1; }
        if (InQueue == _Queue && InEvent.Get_Reason() == ECk_Queue_EventReason::OwnerDestroyed
            && (Member == _MemberA || Member == _MemberB))
        { _OwnerDestroyedMemberEvents += 1; }
    }

    UFUNCTION()
    private void OnQueueInvalidated(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        if (InQueue == _Queue && InState.Get_Reason() == ECk_Queue_EventReason::OwnerDestroyed)
        { _InvalidationEvents += 1; }
    }

    UFUNCTION()
    private void Check_QueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue) && _Queue.Get_State() == ECk_Queue_State::Ready
            && ck::IsValid(_FallbackQueue) && _FallbackQueue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_RequestJoins(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CrowdAgent.Request_JoinQueue(_Queue);
        _Queue.Request_Join(FCk_Request_Queue_Join(_MemberB));
    }

    UFUNCTION()
    private void Check_CrowdAssignmentIssued(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_CrowdAgent), Snapshot);
        if (HasSnapshot && Snapshot.Get_AssignmentRevision() > 0 && _CrowdAgent.Get_ActiveMoveCorrelationId() > 0)
        { _CrowdAssignmentRevision = Snapshot.Get_AssignmentRevision(); }
        auto Result = OutResult;
        Result.Set(_CrowdAssignmentRevision > 0 && _CrowdAgent.Get_ActiveMoveCorrelationId() > 0);
    }

    UFUNCTION()
    private void Step_MoveCrowdToAssignedTargetAndDestroyOwner(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        Assert_True(_Queue.TryGet_MemberSnapshot(FCk_Handle(_CrowdAgent), Snapshot)
            && Snapshot.Get_AssignmentRevision() == _CrowdAssignmentRevision,
            "Crowd teardown reproducer retains the issued queue assignment before owner destruction");
        utils_transform::Request_SetLocation(_CrowdEntity, Snapshot.Get_TargetWorldTransform().GetLocation());
        utils_entity_lifetime::Request_DestroyEntity(_Owner);
    }

    UFUNCTION()
    private void OnFallbackJoinCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _FallbackJoinCompletions += 1;
        _FallbackJoinResult = InResult;
    }

    UFUNCTION()
    private void Check_OwnerTeardownSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Owner) && ck::Is_NOT_Valid(_Queue)
            && _OwnerDestroyedMemberEvents == 2 && _InvalidationEvents == 1
            && _CrowdSlotReachedEvents == 0 && ck::IsValid(_CrowdAgent));
    }

    UFUNCTION()
    private void Step_RequestFallbackJoin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CrowdAgent.Request_JoinQueue(_FallbackQueue,
            FCk_Delegate_Request_OnCompleted(this, n"OnFallbackJoinCompleted"));
    }

    UFUNCTION()
    private void Check_FallbackJoined(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_FallbackJoinCompletions == 1
            && _FallbackJoinResult == ECk_Request_OperationResult::Succeeded
            && _FallbackQueue.Get_IsMember(FCk_Handle(_CrowdAgent))
            && _CrowdSlotReachedEvents == 0);
    }

    UFUNCTION()
    private void Step_AssertOwnerTeardown(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_OwnerDestroyedMemberEvents, 2,
            "each queued member receives one OwnerDestroyed terminal event");
        Assert_Equals_Int(_InvalidationEvents, 1,
            "queue invalidation fires once for owner teardown");
        Assert_True(_CrowdAssignmentRevision > 0,
            "Crowd teardown starts only after the adapter owns a real positive assignment revision");
        Assert_Equals_Int(_CrowdSlotReachedEvents, 0,
            "a destroying queue receives no Crowd adapter SlotReached outcome");
        Assert_True(ck::IsValid(_CrowdAgent) && _FallbackQueue.Get_IsMember(FCk_Handle(_CrowdAgent)),
            "the surviving CrowdAgent can join a fallback queue without a stale adapter wedge");
        Assert_True(ck::Is_NOT_Valid(_Queue), "queue handle is invalid after its separate owner is destroyed");
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle& InOwner)
    {
        return utils_queue::Add(InOwner, FCk_Fragment_Queue_ParamsData());
    }
}
