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
    private int32                      _ContinuousReflowAssignmentRevision = 0;
    private int32                      _ContinuousReflowEpisode = 0;
    private int32                      _ContinuousReflowCorrelation = 0;
    private int32                      _NavigationReflowAssignmentRevision = 0;
    private int32                      _NavigationReflowEpisode = 0;
    private int32                      _NavigationReflowCorrelation = 0;
    private int32                      _PostOverrideEpisode = 0;
    private int32                      _PostOverrideCorrelation = 0;
    private int32                      _ResumedAssignmentRevision = 0;
    private int32                      _ResumedEpisode = 0;
    private int32                      _ResumedCorrelation = 0;
    private int32                      _ClaimedAssignmentRevision = 0;
    private int32                      _ClaimedFollowerAssignmentRevision = 0;
    private int32                      _ClaimedQueueRevision = 0;
    private int32                      _ClaimedSlotReachedEvents = 0;
    private int32                      _ClaimedFollowerSlotReachedEvents = 0;
    private int32                      _ClaimedPrimaryEpisode = 0;
    private int32                      _ClaimedPrimaryCorrelation = 0;
    private int32                      _ClaimedFollowerEpisode = 0;
    private int32                      _ClaimedFollowerCorrelation = 0;
    private int32                      _ReacquireEpisodeBeforeDisplacement = 0;
    private int32                      _ExternalDisplacementEpisode = 0;
    private int32                      _ReacquiredEpisode = 0;
    private int32                      _ReacquiredCorrelation = 0;
    private bool                       _ExternalDisplacementEpisodeObserved = false;
    private bool                       _WasDisplacedBeyondReacquireRadius = false;
    private bool                       _ReacquirePreservedSingleArrival = false;
    private bool                       _ContinuousReflowSampling = false;
    private bool                       _ContinuousReflowHardStopObserved = false;
    private bool                       _NavigationReflowSampling = false;
    private bool                       _NavigationReflowHardStopObserved = false;
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
    private FVector                    _DisplacedLocation;
    private FVector                    _NavigationReflowTarget;
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
        Add_Step_WaitUntil("initial adapter-owned movement reaches meaningful forward speed", n"Check_InitialMoveCruising");
        Add_Step("reflow the live queue assignment along the active movement direction", n"Step_RequestContinuousReflow");
        Add_Step_WaitUntil("live queue reflow retargets without a physical hard stop", n"Check_ContinuousReflowRetargeted");
        Add_Step_WaitUntil("changed-owner-target queue movement remains fast before nav reflow", n"Check_NavigationReflowCruising");
        Add_Step("rebuild navigation while the live queue slot target stays unchanged", n"Step_RequestNavigationReflow");
        Add_Step_WaitUntil("navigation change republishes the live assignment without a physical hard stop", n"Check_NavigationReflowRetargeted");
        Add_Step("replace the owned episode with an external Crowd MoveTo", n"Step_RequestExternalMoveOverride");
        Add_Step_WaitUntil("adapter reclaims its unchanged queue assignment", n"Check_AdapterReclaimedMove");
        Add_Step("suppress movement while the agent is en route", n"Step_RequestSuppression");
        Add_Step_WaitUntil("suppression stops the adapter-owned move", n"Check_SuppressedAndIdle");
        Add_Step("resume movement with an owner-target reflow", n"Step_RequestResumeAndReflow");
        Add_Step_WaitUntil("adapter owns a fresh reflowed move episode", n"Check_ResumedMoveIssued");
        Add_Step_WaitUntil("claimed front member continues closing to its settle radius", n"Check_ClaimedMoveStillClosing");
        Add_Step_WaitUntil("claimed front member physically settles at its slot", n"Check_ClaimedAgentSettled");
        Add_Step_WaitUntil("the resumed Crowd moves claim their queue slots", n"Check_ResumedArrival");
        Add_Step("rebuild navigation after both members claim their reservations", n"Step_RequestClaimedNavigationRebuild");
        Add_Step_WaitUntil("queue revalidates claimed members without restarting their movement", n"Check_ClaimedNavigationRevalidated");
        Add_Step("move the settled claimed member beyond its reacquire radius from an external episode", n"Step_DisplaceSettledAgent");
        Add_Step_WaitUntil("adapter reacquires the displaced claimed member with a fresh move", n"Check_DisplacedAgentReacquired");
        Add_Step_WaitUntil("reacquired claimed member settles without another SlotReached", n"Check_ReacquiredAgentSettled");
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
            FTransform(FRotator::ZeroRotator, FVector(1000.0f, 0.0f, 0.0f), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_transform::Add(_SecondQueueOwner,
            FTransform(FRotator::ZeroRotator, FVector(400.0f, -250.0f, 0.0f), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto QueueParams = FCk_Fragment_Queue_ParamsData();
        QueueParams.Set_SlotSpacingUu(120.0f);
        QueueParams.Set_SlotClaimRadiusUu(80.0f);
        QueueParams.Set_SlotSettleRadiusUu(10.0f);
        QueueParams.Set_SlotReacquireRadiusUu(30.0f);
        _Queue = utils_queue::Add(_QueueOwner, QueueParams);
        _SecondQueue = utils_queue::Add(_SecondQueueOwner,
            FCk_Fragment_Queue_ParamsData());
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

    private float Get_CurrentSpeed(FCk_Handle_CrowdAgent InAgent)
    {
        FCk_Handle Generic = InAgent;
        return float(utils_velocity::Get_CurrentVelocity(utils_velocity::DoCastChecked(Generic)).Size());
    }

    UFUNCTION()
    private void Check_InitialMoveCruising(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Handle Generic = _Agent;
        const auto CurrentVelocity = utils_velocity::Get_CurrentVelocity(utils_velocity::DoCastChecked(Generic));
        auto Result = OutResult;
        Result.Set(CurrentVelocity.X > 120.0f && Get_CurrentSpeed(_Agent) > 120.0f);
    }

    UFUNCTION()
    private void Step_RequestContinuousReflow(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(Get_CurrentSpeed(_Agent) > 120.0f,
            "normal queue reflow begins while the primary adapter owns meaningful physical speed");
        _ContinuousReflowSampling = true;
        _ContinuousReflowHardStopObserved = false;
        utils_transform::Request_SetLocation(_QueueOwner.As_Transform(), FVector(880.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void Check_ContinuousReflowRetargeted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        if (_ContinuousReflowSampling && Get_CurrentSpeed(_Agent) <= 5.0f)
        { _ContinuousReflowHardStopObserved = true; }

        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        const auto Episode = _Agent.Get_ActiveMoveEpisode();
        const auto Correlation = _Agent.Get_ActiveMoveCorrelationId();
        const bool ReflowedWithoutHardStop = HasSnapshot
            && Snapshot.Get_AssignmentRevision() > _InitialAssignmentRevision
            && Episode > _InitialEpisode
            && Correlation > 0
            && Correlation != _InitialCorrelation
            && _Agent.Get_ActiveGoal().Equals(Snapshot.Get_TargetWorldTransform().GetLocation(), 1.0f)
            && _ContinuousReflowHardStopObserved == false;
        if (ReflowedWithoutHardStop)
        {
            _ContinuousReflowAssignmentRevision = Snapshot.Get_AssignmentRevision();
            _ContinuousReflowEpisode = Episode;
            _ContinuousReflowCorrelation = Correlation;
            _ContinuousReflowSampling = false;
        }
        auto Result = OutResult;
        Result.Set(ReflowedWithoutHardStop);
    }

    UFUNCTION()
    private void Check_NavigationReflowCruising(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        auto Result = OutResult;
        Result.Set(HasSnapshot
            && Snapshot.Get_AssignmentRevision() == _ContinuousReflowAssignmentRevision
            && _Agent.Get_ActiveMoveEpisode() == _ContinuousReflowEpisode
            && _Agent.Get_ActiveMoveCorrelationId() == _ContinuousReflowCorrelation
            && Get_CurrentSpeed(_Agent) > 120.0f);
    }

    UFUNCTION()
    private void Step_RequestNavigationReflow(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        Assert_True(_Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot),
            "navigation reflow captures the live primary queue assignment");
        Assert_True(Snapshot.Get_AssignmentRevision() == _ContinuousReflowAssignmentRevision
            && _Agent.Get_ActiveMoveEpisode() == _ContinuousReflowEpisode
            && _Agent.Get_ActiveMoveCorrelationId() == _ContinuousReflowCorrelation,
            "navigation reflow begins from the captured changed-owner-target assignment and Crowd episode");
        Assert_True(Get_CurrentSpeed(_Agent) > 120.0f,
            "navigation reflow begins while the primary adapter owns meaningful physical speed");
        _NavigationReflowTarget = Snapshot.Get_TargetWorldTransform().GetLocation();
        _NavigationReflowSampling = true;
        _NavigationReflowHardStopObserved = false;
        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);
    }

    UFUNCTION()
    private void Check_NavigationReflowRetargeted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        if (_NavigationReflowSampling && Get_CurrentSpeed(_Agent) <= 5.0f)
        { _NavigationReflowHardStopObserved = true; }

        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        const auto Episode = _Agent.Get_ActiveMoveEpisode();
        const auto Correlation = _Agent.Get_ActiveMoveCorrelationId();
        const bool ReflowedWithoutHardStop = HasSnapshot
            && Snapshot.Get_AssignmentRevision() > _ContinuousReflowAssignmentRevision
            && Snapshot.Get_TargetWorldTransform().GetLocation().Equals(_NavigationReflowTarget, 1.0f)
            && Episode > _ContinuousReflowEpisode
            && Correlation > 0
            && Correlation != _ContinuousReflowCorrelation
            && _Agent.Get_ActiveGoal().Equals(_NavigationReflowTarget, 1.0f)
            && _NavigationReflowHardStopObserved == false;
        if (ReflowedWithoutHardStop)
        {
            _NavigationReflowAssignmentRevision = Snapshot.Get_AssignmentRevision();
            _NavigationReflowEpisode = Episode;
            _NavigationReflowCorrelation = Correlation;
            _NavigationReflowSampling = false;
        }
        auto Result = OutResult;
        Result.Set(ReflowedWithoutHardStop);
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
        if (HasSnapshot && Snapshot.Get_AssignmentRevision() == _NavigationReflowAssignmentRevision
            && Episode > _NavigationReflowEpisode && Correlation > 0 && Correlation != 777
            && Correlation != _NavigationReflowCorrelation && QueueGoalIsActive)
        {
            _PostOverrideEpisode = Episode;
            _PostOverrideCorrelation = Correlation;
        }

        auto Result = OutResult;
        Result.Set(_PostOverrideEpisode > _NavigationReflowEpisode
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
        utils_transform::Request_SetLocation(_QueueOwner.As_Transform(), FVector(120.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
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
            && FollowerSnapshot.Get_Rank() == 1
            && FollowerSnapshot.Get_State() == ECk_Queue_MemberState::AtSlot;
        const bool BothAssignmentsAreClaimed = HasSnapshot
            && Snapshot.Get_AssignmentRevision() == _ResumedAssignmentRevision
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && _SlotReachedEvents == 1 && FollowerAtSlot && _FollowerSlotReachedEvents == 1;
        if (BothAssignmentsAreClaimed)
        {
            _ClaimedQueueRevision = _Queue.Get_Revision();
            _ClaimedAssignmentRevision = Snapshot.Get_AssignmentRevision();
            _ClaimedFollowerAssignmentRevision = FollowerSnapshot.Get_AssignmentRevision();
            _ClaimedSlotReachedEvents = _SlotReachedEvents;
            _ClaimedFollowerSlotReachedEvents = _FollowerSlotReachedEvents;
            _ClaimedPrimaryEpisode = _Agent.Get_ActiveMoveEpisode();
            _ClaimedPrimaryCorrelation = _Agent.Get_ActiveMoveCorrelationId();
            _ClaimedFollowerEpisode = _Follower.Get_ActiveMoveEpisode();
            _ClaimedFollowerCorrelation = _Follower.Get_ActiveMoveCorrelationId();
        }
        Result.Set(BothAssignmentsAreClaimed);
    }

    UFUNCTION()
    private void Step_RequestClaimedNavigationRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);
    }

    UFUNCTION()
    private void Check_ClaimedNavigationRevalidated(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Primary;
        FCk_Queue_MemberSnapshot Follower;
        const bool HasPrimary = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Primary);
        const bool HasFollower = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Follower), Follower);
        const bool RevalidatedWithoutRestart = HasPrimary && HasFollower
            && _Queue.Get_Revision() > _ClaimedQueueRevision
            && Primary.Get_State() == ECk_Queue_MemberState::AtFront
            && Follower.Get_State() == ECk_Queue_MemberState::AtSlot
            && Primary.Get_AssignmentRevision() == _ClaimedAssignmentRevision
            && Follower.Get_AssignmentRevision() == _ClaimedFollowerAssignmentRevision
            && _Agent.Get_ActiveMoveEpisode() == _ClaimedPrimaryEpisode
            && _Agent.Get_ActiveMoveCorrelationId() == _ClaimedPrimaryCorrelation
            && _Follower.Get_ActiveMoveEpisode() == _ClaimedFollowerEpisode
            && _Follower.Get_ActiveMoveCorrelationId() == _ClaimedFollowerCorrelation
            && _SlotReachedEvents == _ClaimedSlotReachedEvents
            && _FollowerSlotReachedEvents == _ClaimedFollowerSlotReachedEvents;
        if (RevalidatedWithoutRestart)
        { _ClaimedQueueRevision = _Queue.Get_Revision(); }
        auto Result = OutResult;
        Result.Set(RevalidatedWithoutRestart);
    }

    UFUNCTION()
    private void Check_ClaimedMoveStillClosing(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        const auto SlotLocation = HasSnapshot ? Snapshot.Get_TargetWorldTransform().GetLocation() : FVector::ZeroVector;
        const auto AgentLocation = utils_transform::Get_EntityCurrentLocation(_Agent.As_Transform());
        const auto DistanceToSlot = float((AgentLocation - SlotLocation).Size());
        const bool IsStillClosing = DistanceToSlot > _Queue.Get_SlotSettleRadiusUu()
            || _Agent.Get_MovementState() != ECk_CrowdAgent_MovementState::Idle;
        const bool ClaimedBeforeSettled = HasSnapshot
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && _SlotReachedEvents == 1
            && IsStillClosing;
        if (ClaimedBeforeSettled)
        {
            _ClaimedAssignmentRevision = Snapshot.Get_AssignmentRevision();
            _ClaimedSlotReachedEvents = _SlotReachedEvents;
            _CapturedQueueSlot = SlotLocation;
        }
        auto Result = OutResult;
        Result.Set(ClaimedBeforeSettled);
    }

    UFUNCTION()
    private void Check_ClaimedAgentSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        const auto SlotLocation = HasSnapshot ? Snapshot.Get_TargetWorldTransform().GetLocation() : FVector::ZeroVector;
        const auto AgentLocation = utils_transform::Get_EntityCurrentLocation(_Agent.As_Transform());
        auto Result = OutResult;
        Result.Set(HasSnapshot
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && Snapshot.Get_AssignmentRevision() == _ClaimedAssignmentRevision
            && _SlotReachedEvents == _ClaimedSlotReachedEvents
            && float((AgentLocation - SlotLocation).Size()) <= _Queue.Get_SlotSettleRadiusUu());
    }

    UFUNCTION()
    private void Step_DisplaceSettledAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FVector ProjectedLocation;
        const bool IsNavigable = utils_nav::Try_ProjectOntoNavmesh(
            InHandle, _CapturedQueueSlot + FVector(0.0f, 180.0f, 0.0f), 100.0f, ProjectedLocation, 300.0f);
        Assert_True(IsNavigable, "settled front member displacement target projects onto navigable ground");
        Assert_True(float((ProjectedLocation - _CapturedQueueSlot).Size()) > _Queue.Get_SlotReacquireRadiusUu(),
            "settled front member is displaced beyond its queue reacquire radius");
        _DisplacedLocation = ProjectedLocation;
        _ReacquireEpisodeBeforeDisplacement = _Agent.Get_ActiveMoveEpisode();
        auto ExternalMove = FCk_Request_CrowdAgent_MoveTo(_DisplacedLocation);
        ExternalMove.Set_CorrelationId(707)
            .Set_ForceRepath(true)
            .Set_ArrivalRadiusOverrideMode(ECk_Override::Override)
            .Set_ArrivalRadiusOverrideValue(5.0f);
        _Agent.Request_MoveTo(ExternalMove);
    }

    UFUNCTION()
    private void Check_DisplacedAgentReacquired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        const auto Episode = _Agent.Get_ActiveMoveEpisode();
        const auto Correlation = _Agent.Get_ActiveMoveCorrelationId();
        const auto AgentLocation = utils_transform::Get_EntityCurrentLocation(_Agent.As_Transform());
        if (Correlation == 707 && Episode > _ReacquireEpisodeBeforeDisplacement)
        {
            _ExternalDisplacementEpisodeObserved = true;
            _ExternalDisplacementEpisode = Episode;
        }
        const bool WasDisplaced = float((AgentLocation - _CapturedQueueSlot).Size()) > _Queue.Get_SlotReacquireRadiusUu();
        if (WasDisplaced) { _WasDisplacedBeyondReacquireRadius = true; }
        const bool Reacquired = HasSnapshot
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && Snapshot.Get_AssignmentRevision() == _ClaimedAssignmentRevision
            && _Queue.Get_Revision() == _ClaimedQueueRevision
            && _SlotReachedEvents == _ClaimedSlotReachedEvents
            && _ExternalDisplacementEpisodeObserved
            && Episode > _ExternalDisplacementEpisode
            && Correlation > 0
            && Correlation != 707;
        if (Reacquired)
        {
            _ReacquiredEpisode = Episode;
            _ReacquiredCorrelation = Correlation;
        }
        auto Result = OutResult;
        Result.Set(_WasDisplacedBeyondReacquireRadius && Reacquired);
    }

    UFUNCTION()
    private void Check_ReacquiredAgentSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        const auto SlotLocation = HasSnapshot ? Snapshot.Get_TargetWorldTransform().GetLocation() : FVector::ZeroVector;
        const auto AgentLocation = utils_transform::Get_EntityCurrentLocation(_Agent.As_Transform());
        const auto DistanceToSlot = float((AgentLocation - SlotLocation).Size());
        const bool ReacquiredAndSettled = HasSnapshot
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && Snapshot.Get_AssignmentRevision() == _ClaimedAssignmentRevision
            && _Queue.Get_Revision() == _ClaimedQueueRevision
            && _SlotReachedEvents == _ClaimedSlotReachedEvents
            && _ReacquiredEpisode > _ReacquireEpisodeBeforeDisplacement
            && _ReacquiredCorrelation > 0
            && DistanceToSlot <= _Queue.Get_SlotSettleRadiusUu();
        if (ReacquiredAndSettled)
        { _ReacquirePreservedSingleArrival = true; }
        auto Result = OutResult;
        Result.Set(ReacquiredAndSettled);
    }

    UFUNCTION()
    private void Step_RequestAdvance(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        Assert_True(_Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot),
            "arrived agent remains a queue member immediately before service advance");
        _CapturedQueueSlot = Snapshot.Get_TargetWorldTransform().GetLocation();
        _Queue.Request_Advance(FCk_Request_Queue_Advance(),
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
            && Snapshot.Get_Rank() == 0
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
            && Snapshot.Get_Rank() == 0
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
            "owner-target reflow gives the adapter a strictly newer Queue assignment revision");
        Assert_True(_InitialEpisode > 0 && _ResumedEpisode > _InitialEpisode,
            "each observed queue assignment owns a strictly newer Crowd move episode");
        Assert_True(_ContinuousReflowAssignmentRevision > _InitialAssignmentRevision
            && _ContinuousReflowEpisode > _InitialEpisode
            && _ContinuousReflowCorrelation != _InitialCorrelation
            && _ContinuousReflowHardStopObserved == false,
            "normal queue assignment reflow keeps the primary agent physically moving through its new correlation");
        Assert_True(_NavigationReflowAssignmentRevision > _ContinuousReflowAssignmentRevision
            && _NavigationReflowEpisode > _ContinuousReflowEpisode
            && _NavigationReflowCorrelation != _ContinuousReflowCorrelation
            && _NavigationReflowHardStopObserved == false,
            "navigation revalidation republishes the unchanged live slot through a fresh moving Crowd episode");
        Assert_True(_PostOverrideEpisode > _NavigationReflowEpisode
            && _PostOverrideCorrelation != _NavigationReflowCorrelation,
            "adapter reclaims an unchanged assignment after an external Crowd move replaces its episode");
        Assert_True(_InitialCorrelation > 0 && _ResumedCorrelation > 0
            && _InitialCorrelation != _ResumedCorrelation,
            "resumed queue assignment owns a distinct nonzero Crowd correlation");
        Assert_True(_ClaimedAssignmentRevision == _ResumedAssignmentRevision
            && _ClaimedQueueRevision > 0 && _ClaimedSlotReachedEvents == 1,
            "claim at 80uu preserves the queue assignment and emits exactly one SlotReached before physical settling");
        Assert_True(_WasDisplacedBeyondReacquireRadius
            && _ExternalDisplacementEpisodeObserved
            && _ExternalDisplacementEpisode > _ReacquireEpisodeBeforeDisplacement
            && _ReacquiredEpisode > _ReacquireEpisodeBeforeDisplacement
            && _ReacquiredCorrelation > 0
            && _ReacquirePreservedSingleArrival,
            "a claimed member displaced beyond 30uu reacquires with a fresh move without a second SlotReached");
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
