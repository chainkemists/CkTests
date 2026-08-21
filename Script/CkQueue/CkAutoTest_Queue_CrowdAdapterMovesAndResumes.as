// Language=angelscript

class UCk_AutoTest_Queue_CrowdAdapterMovesAndResumes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                 _QueueOwner;
    private FCk_Handle                 _SecondQueueOwner;
    private FCk_Handle_CrowdAgent      _Agent;
    private FCk_Handle_CrowdAgent      _Follower;
    private FCk_Handle                 _AgentEntity;
    private FCk_Handle                 _FollowerEntity;
    private FCk_Handle_Queue           _Queue;
    private FCk_Handle_Queue           _SecondQueue;
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
    private int32                      _FollowerJoinCompletions = 0;
    private int32                      _FollowerLeaveCompletions = 0;
    private int32                      _SecondJoinCompletions = 0;
    private int32                      _SecondLeaveCompletions = 0;
    private int32                      _SuppressCompletions = 0;
    private int32                      _ResumeCompletions = 0;
    private int32                      _SlotReachedEvents = 0;
    private int32                      _ServingAdvancedEvents = 0;
    private int32                      _MemberDestroyedEvents = 0;
    private int32                      _FollowerSlotReachedEvents = 0;
    private int32                      _NavigationRetryExhaustedEvents = 0;
    private int32                      _AdvanceCompletions = 0;
    private int32                      _ExitEpisodeBeforeRequest = 0;
    private FVector                    _CapturedQueueSlot;
    private FVector                    _ExitGoal;
    private bool                       _ExitReachedCleanly = false;
    private ECk_Request_OperationResult _JoinResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _FollowerJoinResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _FollowerLeaveResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _SecondJoinResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _SecondLeaveResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _SuppressResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _ResumeResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _AdvanceResult = ECk_Request_OperationResult::Failed;

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
        Add_Step("advance the arrived member out of the queue", n"Step_RequestAdvance");
        Add_Step_WaitUntil("advance succeeds and removes the served member", n"Check_AdvancedOutOfQueue");
        Add_Step_WaitUntil("the rank-one adapter reflows after service advance", n"Check_FollowerReflowed");
        Add_Step("join the served adapter to a distinct queue", n"Step_RequestJoinSecondQueue");
        Add_Step_WaitUntil("external removal releases the adapter for the distinct queue", n"Check_JoinedSecondQueue");
        Add_Step("leave the distinct queue through the adapter", n"Step_RequestLeaveSecondQueue");
        Add_Step_WaitUntil("explicit adapter leave removes the distinct membership", n"Check_LeftSecondQueue");
        Add_Step("issue a consumer-owned forced exit MoveTo", n"Step_RequestExitMove");
        // This is real Crowd navigation, not a request-drain condition. Give the 400uu lateral
        // clearance move an explicit frame budget while continuing to poll the full outcome contract.
        Add_Step_WaitUntil("served CrowdAgent cleanly clears the queue slot", n"Check_ServedAgentExited", 1200);
        Add_Step_WaitUntil("reflowed follower reaches the newly opened front", n"Check_FollowerReachedFront", 1200);
        Add_Step("leave the follower through its adapter", n"Step_RequestFollowerLeave");
        Add_Step_WaitUntil("follower leave clears the primary queue", n"Check_FollowerLeft");
        Add_Step("rejoin the exited agent before existing destruction coverage", n"Step_RejoinAfterExit");
        Add_Step_WaitUntil("rejoined agent is again represented by the queue", n"Check_RejoinedAfterExit");
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
    private void OnFollowerJoinCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _FollowerJoinCompletions += 1;
        _FollowerJoinResult = InResult;
    }

    UFUNCTION()
    private void OnFollowerLeaveCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _FollowerLeaveCompletions += 1;
        _FollowerLeaveResult = InResult;
    }

    UFUNCTION()
    private void OnSuppressCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _SuppressCompletions += 1;
        _SuppressResult = InResult;
    }

    UFUNCTION()
    private void OnSecondJoinCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _SecondJoinCompletions += 1;
        _SecondJoinResult = InResult;
    }

    UFUNCTION()
    private void OnSecondLeaveCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _SecondLeaveCompletions += 1;
        _SecondLeaveResult = InResult;
    }

    UFUNCTION()
    private void OnResumeCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _ResumeCompletions += 1;
        _ResumeResult = InResult;
    }

    UFUNCTION()
    private void OnAdvanceCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _AdvanceCompletions += 1;
        _AdvanceResult = InResult;
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue != _Queue)
        { return; }
        if (InEvent.Get_Member().Get_Member() == FCk_Handle(_Follower)
            && InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached)
        { _FollowerSlotReachedEvents += 1; }
        if (InEvent.Get_Member().Get_Member() != FCk_Handle(_Agent))
        { return; }
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached)
        { _SlotReachedEvents += 1; }
        else if (InEvent.Get_Reason() == ECk_Queue_EventReason::Advanced
            && InEvent.Get_Member().Get_State() == ECk_Queue_MemberState::Serving)
        { _ServingAdvancedEvents += 1; }
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
        _SecondQueueOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_QueueOwner,
            FTransform(FRotator::ZeroRotator, _Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_transform::Add(_SecondQueueOwner,
            FTransform(FRotator::ZeroRotator, _Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform(FVector(1000.0f, 0.0f, 0.0f))));
        auto QueueParams = FCk_Fragment_Queue_ParamsData(Origins);
        QueueParams.Set_SlotSpacingUu(120.0f);
        _Queue = utils_queue::Add(_QueueOwner, QueueParams);
        auto SecondOrigins = TArray<FCk_Queue_Origin>();
        SecondOrigins.Add(FCk_Queue_Origin(FTransform(FVector(400.0f, -250.0f, 0.0f))));
        _SecondQueue = utils_queue::Add(_SecondQueueOwner,
            FCk_Fragment_Queue_ParamsData(SecondOrigins));
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));
        _Queue.BindTo_OnQueueFormationStateChanged(
            FCk_Delegate_Queue_OnFormationStateChanged(this, n"OnFormationStateChanged"));

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(FRotator::ZeroRotator, _Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        AgentParams.Set_MaxSpeed(600.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, AgentParams);
        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);

        _FollowerEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto FollowerTransform = utils_transform::Add(_FollowerEntity,
            FTransform(FRotator::ZeroRotator, _Spawn + FVector(0.0f, 100.0f, 0.0f), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _Follower = utils_crowd_agent::Add(FollowerTransform, AgentParams);
        utils_velocity::Add(_FollowerEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_FollowerEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_FollowerEntity);
    }

    UFUNCTION()
    private void Check_QueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue) && _Queue.Get_State() == ECk_Queue_State::Ready
            && ck::IsValid(_SecondQueue) && _SecondQueue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_RequestJoin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Agent.Request_JoinQueue(_Queue,
            FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
        _Follower.Request_JoinQueue(_Queue,
            FCk_Delegate_Request_OnCompleted(this, n"OnFollowerJoinCompleted"));
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
            && _FollowerJoinCompletions == 1 && _FollowerJoinResult == ECk_Request_OperationResult::Succeeded
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
        FCk_Queue_MemberSnapshot FollowerSnapshot;
        const bool FollowerAtSlot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Follower), FollowerSnapshot)
            && FollowerSnapshot.Get_OriginIndex() == 0 && FollowerSnapshot.Get_Rank() == 1
            && FollowerSnapshot.Get_State() == ECk_Queue_MemberState::AtSlot;
        Result.Set(HasSnapshot && Snapshot.Get_AssignmentRevision() == _ResumedAssignmentRevision
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && _SlotReachedEvents == 1 && FollowerAtSlot && _FollowerSlotReachedEvents == 1);
    }

    UFUNCTION()
    private void Step_RequestAdvance(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        Assert_True(_Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot),
            "arrived agent remains a queue member immediately before service advance");
        _CapturedQueueSlot = Snapshot.Get_TargetWorldTransform().GetLocation();
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(0),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvanceCompleted"));
    }

    UFUNCTION()
    private void Check_AdvancedOutOfQueue(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_AdvanceCompletions == 1 && _AdvanceResult == ECk_Request_OperationResult::Succeeded
            && _ServingAdvancedEvents == 1 && _Queue.Get_IsMember(FCk_Handle(_Agent)) == false);
    }

    UFUNCTION()
    private void Check_FollowerReflowed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        auto Result = OutResult;
        Result.Set(_Queue.TryGet_MemberSnapshot(FCk_Handle(_Follower), Snapshot)
            && Snapshot.Get_OriginIndex() == 0 && Snapshot.Get_Rank() == 0
            && Snapshot.Get_AssignmentRevision() > 0
            && _Queue.Get_State() == ECk_Queue_State::Ready
            && _NavigationRetryExhaustedEvents == 0);
    }

    UFUNCTION()
    private void OnFormationStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        if (InQueue == _Queue && InState.Get_Reason() == ECk_Queue_EventReason::NavigationRetryExhausted)
        { _NavigationRetryExhaustedEvents += 1; }
    }

    UFUNCTION()
    private void Step_RequestJoinSecondQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Agent.Request_JoinQueue(_SecondQueue,
            FCk_Delegate_Request_OnCompleted(this, n"OnSecondJoinCompleted"));
    }

    UFUNCTION()
    private void Check_JoinedSecondQueue(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_SecondJoinCompletions == 1
            && _SecondJoinResult == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_IsMember(FCk_Handle(_Agent)) == false
            && _SecondQueue.Get_IsMember(FCk_Handle(_Agent)));
    }

    UFUNCTION()
    private void Step_RequestLeaveSecondQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Agent.Request_LeaveQueue(
            FCk_Delegate_Request_OnCompleted(this, n"OnSecondLeaveCompleted"));
    }

    UFUNCTION()
    private void Check_LeftSecondQueue(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_SecondLeaveCompletions == 1
            && _SecondLeaveResult == ECk_Request_OperationResult::Succeeded
            && _SecondQueue.Get_IsMember(FCk_Handle(_Agent)) == false);
    }

    UFUNCTION()
    private void Step_RequestExitMove(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ExitGoal = _CapturedQueueSlot + FVector(0.0f, 400.0f, 0.0f);
        _ExitEpisodeBeforeRequest = _Agent.Get_ActiveMoveEpisode();
        auto ExitRequest = FCk_Request_CrowdAgent_MoveTo(_ExitGoal);
        ExitRequest.Set_CorrelationId(909);
        ExitRequest.Set_ForceRepath(true);
        _Agent.Request_MoveTo(ExitRequest);
    }

    UFUNCTION()
    private void Check_ServedAgentExited(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto CurrentPosition = utils_transform::Get_EntityCurrentLocation(_Agent.As_Transform());
        const bool ExitedCleanly = _Queue.Get_IsMember(FCk_Handle(_Agent)) == false
            && _Agent.Get_ActiveGoal().Equals(_ExitGoal, 1.0f)
            && _Agent.Get_HasReachedActiveGoal()
            && _Agent.Get_IsGoalFailedHold() == false
            && _Agent.Get_ActiveMoveCorrelationId() == 909
            && _Agent.Get_ActiveMoveEpisode() > _ExitEpisodeBeforeRequest
            && float((CurrentPosition - _CapturedQueueSlot).Size()) > 300.0f;
        if (ExitedCleanly) { _ExitReachedCleanly = true; }
        auto Result = OutResult;
        Result.Set(ExitedCleanly);
    }

    UFUNCTION()
    private void Check_FollowerReachedFront(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        auto Result = OutResult;
        Result.Set(_Queue.TryGet_MemberSnapshot(FCk_Handle(_Follower), Snapshot)
            && Snapshot.Get_OriginIndex() == 0 && Snapshot.Get_Rank() == 0
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && _FollowerSlotReachedEvents >= 2 && _NavigationRetryExhaustedEvents == 0);
    }

    UFUNCTION()
    private void Step_RequestFollowerLeave(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Follower.Request_LeaveQueue(
            FCk_Delegate_Request_OnCompleted(this, n"OnFollowerLeaveCompleted"));
    }

    UFUNCTION()
    private void Check_FollowerLeft(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_FollowerLeaveCompletions == 1
            && _FollowerLeaveResult == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_IsMember(FCk_Handle(_Follower)) == false);
    }

    UFUNCTION()
    private void Step_RejoinAfterExit(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Agent.Request_JoinQueue(_Queue, FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
    }

    UFUNCTION()
    private void Check_RejoinedAfterExit(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Queue.Get_IsMember(FCk_Handle(_Agent)) && _JoinCompletions == 2
            && _JoinResult == ECk_Request_OperationResult::Succeeded);
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
            && _SecondQueue.Get_MemberCount() == 0
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
        Assert_True(_AdvanceResult == ECk_Request_OperationResult::Succeeded && _ServingAdvancedEvents == 1,
            "arrived adapter member advances exactly once before consumer-owned exit");
        Assert_True(_FollowerJoinResult == ECk_Request_OperationResult::Succeeded
            && _FollowerSlotReachedEvents >= 2 && _NavigationRetryExhaustedEvents == 0,
            "rank-one adapter member reflows to and reaches front after service advance without exhausting navigation");
        Assert_True(_SecondJoinCompletions == 1 && _SecondJoinResult == ECk_Request_OperationResult::Succeeded,
            "an adapter member advanced out of one queue can join a distinct valid queue");
        Assert_True(_SecondLeaveCompletions == 1 && _SecondLeaveResult == ECk_Request_OperationResult::Succeeded,
            "explicit adapter leave remains available after the external service advance");
        Assert_True(_ExitReachedCleanly,
            "served agent reaches its consumer-owned exit instead of failing held near the queue");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 0,
            "destroyed CrowdAgent is reconciled out of queue membership without Leave");
        Assert_Equals_Int(_MemberDestroyedEvents, 1,
            "destroyed CrowdAgent emits exactly one planner-visible MemberDestroyed event");
    }
}
