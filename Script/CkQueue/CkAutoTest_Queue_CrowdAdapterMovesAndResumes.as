// Language=angelscript

class UCk_AutoTest_Queue_CrowdAdapterMovesAndResumes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                 _QueueOwner;
    private FCk_Handle_CrowdAgent      _Agent;
    private FCk_Handle                 _AgentEntity;
    private FCk_Handle_Queue           _Queue;
    private FVector                    _Spawn;
    private int32                      _InitialAssignmentRevision = 0;
    private int32                      _InitialEpisode = 0;
    private int32                      _InitialCorrelation = 0;
    private int32                      _PostOverrideEpisode = 0;
    private int32                      _PostOverrideCorrelation = 0;
    private int32                      _ResumedAssignmentRevision = 0;
    private int32                      _ResumedEpisode = 0;
    private int32                      _ResumedCorrelation = 0;
    private int32                      _JoinCompletions = 0;
    private int32                      _SuppressCompletions = 0;
    private int32                      _ResumeCompletions = 0;
    private int32                      _SlotReachedEvents = 0;
    private int32                      _MemberDestroyedEvents = 0;
    private ECk_Request_OperationResult _JoinResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _SuppressResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _ResumeResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        Add_Step_WaitUntil("spawn and queue target are navigable", n"Check_NavigationReady");
        Add_Step("compose an isolated queue and CrowdAgent", n"Step_ComposeQueueAndAgent");
        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join through the Crowd queue adapter", n"Step_RequestJoin");
        Add_Step_WaitUntil("adapter owns the initial Crowd move episode", n"Check_InitialMoveIssued");
        Add_Step("replace the owned episode with an external Crowd MoveTo", n"Step_RequestExternalMoveOverride");
        Add_Step_WaitUntil("adapter reclaims its unchanged queue assignment", n"Check_AdapterReclaimedMove");
        Add_Step("suppress movement while the agent is en route", n"Step_RequestSuppression");
        Add_Step_WaitUntil("suppression stops the adapter-owned move", n"Check_SuppressedAndIdle");
        Add_Step("resume movement with an origin reflow", n"Step_RequestResumeAndReflow");
        Add_Step_WaitUntil("adapter owns a fresh reflowed move episode", n"Check_ResumedMoveIssued");
        Add_Step_WaitUntil("the resumed Crowd move reaches the queue front", n"Check_ResumedArrival");
        Add_Step("destroy the CrowdAgent without leaving", n"Step_DestroyAgent");
        Add_Step_WaitUntil("queue reconciles the destroyed CrowdAgent", n"Check_DestroyedAgentReconciled");
        Add_Step("assert the complete adapter lifecycle", n"Step_AssertAdapterLifecycle");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnJoinCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _JoinCompletions += 1;
        _JoinResult = InResult;
    }

    UFUNCTION()
    private void OnSuppressCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _SuppressCompletions += 1;
        _SuppressResult = InResult;
    }

    UFUNCTION()
    private void OnResumeCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _ResumeCompletions += 1;
        _ResumeResult = InResult;
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue != _Queue || InEvent.Get_Member().Get_Member() != FCk_Handle(_Agent))
        { return; }
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached)
        { _SlotReachedEvents += 1; }
        else if (InEvent.Get_Reason() == ECk_Queue_EventReason::MemberDestroyed)
        { _MemberDestroyedEvents += 1; }
    }

    UFUNCTION()
    private void Check_NavigationReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FVector SpawnOnMesh;
        FVector TargetOnMesh;
        auto Context = InHandle;
        const bool SpawnIsNavigable = utils_nav::Try_ProjectOntoNavmesh(
            Context, FVector(-400.0f, 0.0f, 0.0f), 100.0f, SpawnOnMesh, 300.0f);
        const bool TargetIsNavigable = utils_nav::Try_ProjectOntoNavmesh(
            Context, FVector(600.0f, 0.0f, 0.0f), 100.0f, TargetOnMesh, 300.0f);
        if (SpawnIsNavigable) { _Spawn = SpawnOnMesh; }
        auto Result = OutResult;
        Result.Set(SpawnIsNavigable && TargetIsNavigable);
    }

    UFUNCTION()
    private void Step_ComposeQueueAndAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _QueueOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_QueueOwner,
            FTransform(FRotator::ZeroRotator, _Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform(FVector(1000.0f, 0.0f, 0.0f))));
        auto QueueParams = FCk_Fragment_Queue_ParamsData(Origins);
        QueueParams.Set_SlotSpacingUu(120.0f);
        _Queue = utils_queue::Add(_QueueOwner, QueueParams);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(FRotator::ZeroRotator, _Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        AgentParams.Set_MaxSpeed(150.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, AgentParams);
        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);
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
        _Agent.Request_JoinQueue(_Queue,
            FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
    }

    UFUNCTION()
    private void Check_InitialMoveIssued(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        const auto Episode = _Agent.Get_ActiveMoveEpisode();
        const auto Correlation = _Agent.Get_ActiveMoveCorrelationId();
        if (HasSnapshot && Snapshot.Get_AssignmentRevision() > 0 && Episode > 0 && Correlation > 0)
        {
            _InitialAssignmentRevision = Snapshot.Get_AssignmentRevision();
            _InitialEpisode = Episode;
            _InitialCorrelation = Correlation;
        }
        auto Result = OutResult;
        Result.Set(_JoinCompletions == 1 && _JoinResult == ECk_Request_OperationResult::Succeeded
            && HasSnapshot && Snapshot.Get_AssignmentRevision() > 0 && Episode > 0 && Correlation > 0);
    }

    UFUNCTION()
    private void Step_RequestSuppression(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_SetMovementSuppressed(
            FCk_Request_Queue_SetMovementSuppressed(FCk_Handle(_Agent), ECk_EnableDisable::Enable),
            FCk_Delegate_Request_OnCompleted(this, n"OnSuppressCompleted"));
    }

    UFUNCTION()
    private void Step_RequestExternalMoveOverride(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Request = FCk_Request_CrowdAgent_MoveTo(_Spawn + FVector(0.0f, 300.0f, 0.0f));
        Request.Set_CorrelationId(777);
        _Agent.Request_MoveTo(Request);
    }

    UFUNCTION()
    private void Check_AdapterReclaimedMove(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        const auto Episode = _Agent.Get_ActiveMoveEpisode();
        const auto Correlation = _Agent.Get_ActiveMoveCorrelationId();
        const bool QueueGoalIsActive = HasSnapshot && _Agent.Get_ActiveGoal().Equals(
            Snapshot.Get_TargetWorldTransform().GetLocation(),
            1.0f);
        if (HasSnapshot && Snapshot.Get_AssignmentRevision() == _InitialAssignmentRevision
            && Episode > _InitialEpisode && Correlation > 0 && Correlation != 777
            && Correlation != _InitialCorrelation && QueueGoalIsActive)
        {
            _PostOverrideEpisode = Episode;
            _PostOverrideCorrelation = Correlation;
        }

        auto Result = OutResult;
        Result.Set(_PostOverrideEpisode > _InitialEpisode
            && _PostOverrideCorrelation > 0
            && QueueGoalIsActive);
    }

    UFUNCTION()
    private void Check_SuppressedAndIdle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        auto Result = OutResult;
        Result.Set(_SuppressCompletions == 1 && _SuppressResult == ECk_Request_OperationResult::Succeeded
            && HasSnapshot && Snapshot.Get_MovementSuppressed()
            && _Agent.Get_MovementState() == ECk_CrowdAgent_MovementState::Idle);
    }

    UFUNCTION()
    private void Step_RequestResumeAndReflow(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_SetMovementSuppressed(
            FCk_Request_Queue_SetMovementSuppressed(FCk_Handle(_Agent), ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnResumeCompleted"));
        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform(FVector(120.0f, 0.0f, 0.0f))));
        _Queue.Request_SetOrigins(FCk_Request_Queue_SetOrigins(Origins));
    }

    UFUNCTION()
    private void Check_ResumedMoveIssued(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        const auto Episode = _Agent.Get_ActiveMoveEpisode();
        const auto Correlation = _Agent.Get_ActiveMoveCorrelationId();
        if (HasSnapshot && Snapshot.Get_AssignmentRevision() > _InitialAssignmentRevision
            && Episode > _PostOverrideEpisode && Correlation > 0
            && Correlation != _PostOverrideCorrelation)
        {
            _ResumedAssignmentRevision = Snapshot.Get_AssignmentRevision();
            _ResumedEpisode = Episode;
            _ResumedCorrelation = Correlation;
        }
        auto Result = OutResult;
        Result.Set(_ResumeCompletions == 1 && _ResumeResult == ECk_Request_OperationResult::Succeeded
            && HasSnapshot && Snapshot.Get_AssignmentRevision() > _InitialAssignmentRevision
            && Snapshot.Get_MovementSuppressed() == false && Episode > _PostOverrideEpisode
            && Correlation > 0 && Correlation != _PostOverrideCorrelation);
    }

    UFUNCTION()
    private void Check_ResumedArrival(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        auto Result = OutResult;
        Result.Set(HasSnapshot && Snapshot.Get_AssignmentRevision() == _ResumedAssignmentRevision
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && _SlotReachedEvents == 1);
    }

    UFUNCTION()
    private void Step_DestroyAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_AgentEntity);
    }

    UFUNCTION()
    private void Check_DestroyedAgentReconciled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Agent) && _Queue.Get_MemberCount() == 0
            && _MemberDestroyedEvents == 1);
    }

    UFUNCTION()
    private void Step_AssertAdapterLifecycle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_InitialAssignmentRevision > 0 && _ResumedAssignmentRevision > _InitialAssignmentRevision,
            "origin reflow gives the adapter a strictly newer queue assignment revision");
        Assert_True(_InitialEpisode > 0 && _ResumedEpisode > _InitialEpisode,
            "each observed queue assignment owns a strictly newer Crowd move episode");
        Assert_True(_PostOverrideEpisode > _InitialEpisode
            && _PostOverrideCorrelation != _InitialCorrelation,
            "adapter reclaims an unchanged assignment after an external Crowd move replaces its episode");
        Assert_True(_InitialCorrelation > 0 && _ResumedCorrelation > 0
            && _InitialCorrelation != _ResumedCorrelation,
            "resumed queue assignment owns a distinct nonzero Crowd correlation");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 0,
            "destroyed CrowdAgent is reconciled out of queue membership without Leave");
        Assert_Equals_Int(_MemberDestroyedEvents, 1,
            "destroyed CrowdAgent emits exactly one planner-visible MemberDestroyed event");
    }
}
