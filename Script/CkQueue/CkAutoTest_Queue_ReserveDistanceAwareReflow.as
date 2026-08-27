// Language=angelscript

class UCk_AutoTest_Queue_ReserveDistanceAwareReflow : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle       _EarlyFar;
    private FCk_Handle       _LateNear;
    private FCk_Handle       _TicketOwner;
    private FCk_Handle_Queue _TicketQueue;
    private FCk_Handle       _TicketEarlyFar;
    private FCk_Handle       _TicketLateNear;
    private FCk_Handle       _TransformlessOwner;
    private FCk_Handle_Queue _TransformlessQueue;
    private FCk_Handle       _TransformlessEarly;
    private FCk_Handle       _TransformlessLateNear;
    private FCk_Handle       _TieOwner;
    private FCk_Handle_Queue _TieQueue;
    private FCk_Handle       _TieEarly;
    private FCk_Handle       _TieLate;
    private FCk_Handle       _ClaimFirstOwner;
    private FCk_Handle_Queue _ClaimFirstQueue;
    private FCk_Handle       _ClaimFirstMover;
    private FCk_Handle       _DestroyOwner;
    private FCk_Handle_Queue _DestroyQueue;
    private FCk_Handle       _DestroyMover;
    private FCk_Handle       _PhaseSpreadDisabledOwner;
    private FCk_Handle_Queue _PhaseSpreadDisabledQueue;
    private int32            _InitialRevision = 0;
    private int32            _SwappedRevision = 0;
    private int32            _StableRevision = 0;
    private int32            _ArrivedFrontRevision = 0;
    private int32            _ReservedSlotReachedCount = 0;
    private int32            _ClaimFirstSlotReachedCount = 0;
    private int32            _DestroySlotReachedCount = 0;
    private bool             _DuplicateOutcomeCompleted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Queue = CreateQueue(_Owner, ECk_Queue_ReserveAssignmentPolicy::DistanceThenTicket);
        _Queue.BindTo_OnQueueMemberStateChanged(FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberEvent"));

        _EarlyFar = CreateMover(InHandle, FVector(-1000.0f, 0.0f, 0.0f));
        _LateNear = CreateMover(InHandle, FVector(100.0f, 0.0f, 0.0f));

        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);

        Add_Step_WaitUntil("distance-aware queue setup completes", n"Check_QueueReady");
        Add_Step("verify phase-spread configuration defaults and rejection", n"Step_VerifyPhaseSpreadConfiguration");
        Add_Step_WaitUntil("disabled phase spreading composes a ready queue", n"Check_PhaseSpreadDisabledQueueReady");
        Add_Step("join far ticket one before near ticket two", n"Step_RequestDistanceJoins");
        Add_Step_WaitUntil("near later ticket receives rank zero", n"Check_NearLaterWinsInitialReservation");
        Add_Step("move ticket one closer than ticket two", n"Step_MoveEarlyTicketCloser");
        Add_Step_WaitUntil("distance refresh swaps the two reservations", n"Check_AssignmentsSwapAfterMoverTransformChange");
        Add_Step_WaitUntil("unchanged distance refresh has no revision churn", n"Check_UnchangedRefreshRetainsAssignments");
        Add_Step("create a fresh queue with an exact distance tie", n"Step_CreateExactTieQueue");
        Add_Step_WaitUntil("ticket order breaks an exact distance tie", n"Check_TicketBreaksExactDistanceTie");
        Add_Step("move the reserved front inside its claim radius without reporting an outcome", n"Step_MoveFrontIntoClaimRadius");
        Add_Step_WaitUntil("queue reconciliation detects the physically arrived front", n"Check_FrontArrived");
        Add_Step("report the already reconciled arrival again", n"Step_ReportDuplicateArrival");
        Add_Step_WaitUntil("duplicate arrival report drains without another SlotReached", n"Check_DuplicateArrivalDrained");
        Add_Step("move the later ticket directly onto the occupied front", n"Step_MoveLaterTicketOntoFront");
        Add_Step_WaitUntil("arrived front remains pinned despite a nearer follower", n"Check_ArrivedFrontRemainsPinned");
        Add_Step("create a default queue with a transformless early join", n"Step_CreateTransformlessQueue");
        Add_Step_WaitUntil("near transform-bearing later join receives rank zero", n"Check_TransformlessEarlyJoinDoesNotBlockNearMover");
        Add_Step("create a ticket-order compatibility queue", n"Step_CreateTicketOrderQueue");
        Add_Step_WaitUntil("legacy ticket ordering keeps the far early ticket at rank zero", n"Check_TicketOrderCompatibility");
        Add_Step("create a claim-first mover already inside the offered slot", n"Step_CreateClaimFirstQueue");
        Add_Step_WaitUntil("claim-first proximity reconciles the slot without an outcome report", n"Check_ClaimFirstReconcilesProximity");
        Add_Step("create a reserved mover for the destruction boundary", n"Step_CreateDestroyedArrivalQueue");
        Add_Step_WaitUntil("reserved mover receives its assignment before destruction", n"Check_DestroyMoverAssigned");
        Add_Step("destroy the reserved mover as it enters its claim radius", n"Step_DestroyReservedArrival");
        Add_Step_WaitUntil("destroyed arrival is removed without SlotReached", n"Check_DestroyedArrivalRemoved");
        Add_Step("assert distance-aware reservation contracts", n"Step_AssertContracts");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberEvent(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InEvent.Get_Reason() != ECk_Queue_EventReason::SlotReached) { return; }
        if (InQueue == _Queue && InEvent.Get_Member().Get_Member() == _EarlyFar)
        { _ReservedSlotReachedCount++; }
        else if (InQueue == _ClaimFirstQueue && InEvent.Get_Member().Get_Member() == _ClaimFirstMover)
        { _ClaimFirstSlotReachedCount++; }
        else if (InQueue == _DestroyQueue && InEvent.Get_Member().Get_Member() == _DestroyMover)
        { _DestroySlotReachedCount++; }
    }

    UFUNCTION()
    private void Check_QueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue) && _Queue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_VerifyPhaseSpreadConfiguration(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto DefaultParams = FCk_Fragment_Queue_ParamsData();
        Assert_True(DefaultParams.Get_ReserveAssignmentRefreshPhaseSpread() == ECk_EnableDisable::Enable,
            "reserve assignment refresh phase spreading defaults to enabled");

        _PhaseSpreadDisabledOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_PhaseSpreadDisabledOwner,
            FTransform(FVector(0.0f, 1000.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
        auto DisabledParams = FCk_Fragment_Queue_ParamsData();
        DisabledParams.Set_LayoutAlgorithm(ECk_Queue_LayoutAlgorithm::Linear);
        DisabledParams.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ReserveOnFormation);
        DisabledParams.Set_ReserveAssignmentPolicy(ECk_Queue_ReserveAssignmentPolicy::DistanceThenTicket);
        DisabledParams.Set_ReserveAssignmentRefreshSeconds(0.25f);
        DisabledParams.Set_ReserveAssignmentRefreshPhaseSpread(ECk_EnableDisable::Disable);
        Assert_True(DisabledParams.Get_ReserveAssignmentRefreshPhaseSpread() == ECk_EnableDisable::Disable,
            "phase-spread disable setter preserves the requested public configuration");
        _PhaseSpreadDisabledQueue = utils_queue::Add(_PhaseSpreadDisabledOwner, DisabledParams);
        Assert_True(ck::IsValid(_PhaseSpreadDisabledQueue),
            "disabled phase spreading is accepted as a valid Queue configuration");

        auto InvalidOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(InvalidOwner,
            FTransform(FVector(0.0f, 2000.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
        auto InvalidParams = FCk_Fragment_Queue_ParamsData();
        InvalidParams.Set_ReserveAssignmentRefreshPhaseSpread(ECk_EnableDisable(255));
        const auto InvalidQueue = utils_queue::Add(InvalidOwner, InvalidParams);
        Assert_True(ck::Is_NOT_Valid(InvalidQueue),
            "an invalid phase-spread enum rejects Queue composition");
        Assert_True(utils_queue::Has_Any(InvalidOwner) == false,
            "invalid phase-spread composition leaves no partial Queue on its owner");
    }

    UFUNCTION()
    private void Check_PhaseSpreadDisabledQueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_PhaseSpreadDisabledQueue)
            && _PhaseSpreadDisabledQueue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_RequestDistanceJoins(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Early = FCk_Request_Queue_Join(_EarlyFar);
        Early.Set_Mover(_EarlyFar);
        _Queue.Request_Join(Early);
        auto Late = FCk_Request_Queue_Join(_LateNear);
        Late.Set_Mover(_LateNear);
        _Queue.Request_Join(Late);
    }

    UFUNCTION()
    private void Check_NearLaterWinsInitialReservation(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Early;
        FCk_Queue_MemberSnapshot Late;
        const bool HasEarly = _Queue.TryGet_MemberSnapshot(_EarlyFar, Early);
        const bool HasLate = _Queue.TryGet_MemberSnapshot(_LateNear, Late);
        if (HasLate) { _InitialRevision = Late.Get_AssignmentRevision(); }
        auto Result = OutResult;
        Result.Set(HasEarly && HasLate && Early.Get_Ticket() == 1 && Late.Get_Ticket() == 2
            && Early.Get_Rank() == 1 && Late.Get_Rank() == 0
            && Early.Get_AssignmentRevision() > 0 && _InitialRevision > 0);
    }

    UFUNCTION()
    private void Step_MoveEarlyTicketCloser(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_transform::Request_SetLocation(_EarlyFar.As_Transform(), FVector(120.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
        utils_transform::Request_SetLocation(_LateNear.As_Transform(), FVector(-900.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void Check_AssignmentsSwapAfterMoverTransformChange(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Early;
        FCk_Queue_MemberSnapshot Late;
        const bool HasEarly = _Queue.TryGet_MemberSnapshot(_EarlyFar, Early);
        const bool HasLate = _Queue.TryGet_MemberSnapshot(_LateNear, Late);
        if (HasEarly && HasLate && Early.Get_Rank() == 0 && Late.Get_Rank() == 1
            && Early.Get_AssignmentRevision() > _InitialRevision && Late.Get_AssignmentRevision() > _InitialRevision)
        { _SwappedRevision = _Queue.Get_Revision(); }
        auto Result = OutResult;
        Result.Set(_SwappedRevision > _InitialRevision);
    }

    UFUNCTION()
    private void Check_UnchangedRefreshRetainsAssignments(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Early;
        FCk_Queue_MemberSnapshot Late;
        const bool HasEarly = _Queue.TryGet_MemberSnapshot(_EarlyFar, Early);
        const bool HasLate = _Queue.TryGet_MemberSnapshot(_LateNear, Late);
        const bool Stable = HasEarly && HasLate && Early.Get_Rank() == 0 && Late.Get_Rank() == 1
            && _Queue.Get_Revision() == _SwappedRevision;
        if (Stable) { _StableRevision = _Queue.Get_Revision(); }
        auto Result = OutResult;
        Result.Set(Stable);
    }

    UFUNCTION()
    private void Step_CreateExactTieQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TieOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_TieOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _TieQueue = CreateQueue(_TieOwner, ECk_Queue_ReserveAssignmentPolicy::DistanceThenTicket);
        _TieEarly = CreateMover(InHandle, FVector(100.0f, 100.0f, 0.0f));
        _TieLate = CreateMover(InHandle, FVector(100.0f, -100.0f, 0.0f));
        auto Early = FCk_Request_Queue_Join(_TieEarly);
        Early.Set_Mover(_TieEarly);
        _TieQueue.Request_Join(Early);
        auto Late = FCk_Request_Queue_Join(_TieLate);
        Late.Set_Mover(_TieLate);
        _TieQueue.Request_Join(Late);
    }

    UFUNCTION()
    private void Check_TicketBreaksExactDistanceTie(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Early;
        FCk_Queue_MemberSnapshot Late;
        const bool HasEarly = _TieQueue.TryGet_MemberSnapshot(_TieEarly, Early);
        const bool HasLate = _TieQueue.TryGet_MemberSnapshot(_TieLate, Late);
        auto Result = OutResult;
        Result.Set(ck::IsValid(_TieQueue) && _TieQueue.Get_State() == ECk_Queue_State::Ready
            && HasEarly && HasLate && Early.Get_Ticket() == 1 && Late.Get_Ticket() == 2
            && Early.Get_Rank() == 0 && Late.Get_Rank() == 1);
    }

    UFUNCTION()
    private void Step_MoveFrontIntoClaimRadius(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Early;
        Assert_True(_Queue.TryGet_MemberSnapshot(_EarlyFar, Early), "ticket-one snapshot exists before geometric arrival reconciliation");
        _ArrivedFrontRevision = Early.Get_AssignmentRevision();
        utils_transform::Request_SetLocation(
            _EarlyFar.As_Transform(),
            Early.Get_TargetWorldTransform().GetLocation(),
            ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void Check_FrontArrived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Early;
        const bool HasEarly = _Queue.TryGet_MemberSnapshot(_EarlyFar, Early);
        auto Result = OutResult;
        Result.Set(HasEarly && Early.Get_State() == ECk_Queue_MemberState::AtFront
            && Early.Get_Rank() == 0 && Early.Get_AssignmentRevision() == _ArrivedFrontRevision
            && _ReservedSlotReachedCount == 1);
    }

    UFUNCTION()
    private void Step_ReportDuplicateArrival(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_ReportMovementOutcome(
            FCk_Request_Queue_ReportMovementOutcome(
                _EarlyFar, _ArrivedFrontRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnDuplicateOutcomeCompleted"));
    }

    UFUNCTION()
    private void OnDuplicateOutcomeCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _DuplicateOutcomeCompleted = true;
    }

    UFUNCTION()
    private void Check_DuplicateArrivalDrained(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_DuplicateOutcomeCompleted && _ReservedSlotReachedCount == 1);
    }

    UFUNCTION()
    private void Step_MoveLaterTicketOntoFront(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_transform::Request_SetLocation(_LateNear.As_Transform(), FVector(200.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void Check_ArrivedFrontRemainsPinned(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Early;
        FCk_Queue_MemberSnapshot Late;
        const bool HasEarly = _Queue.TryGet_MemberSnapshot(_EarlyFar, Early);
        const bool HasLate = _Queue.TryGet_MemberSnapshot(_LateNear, Late);
        auto Result = OutResult;
        Result.Set(HasEarly && HasLate && Early.Get_State() == ECk_Queue_MemberState::AtFront
            && Early.Get_Rank() == 0 && Early.Get_AssignmentRevision() == _ArrivedFrontRevision
            && Late.Get_Rank() == 1);
    }

    UFUNCTION()
    private void Step_CreateTransformlessQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TransformlessOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_TransformlessOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _TransformlessQueue = CreateQueue(_TransformlessOwner, ECk_Queue_ReserveAssignmentPolicy::DistanceThenTicket);
        _TransformlessEarly = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _TransformlessLateNear = CreateMover(InHandle, FVector(210.0f, -250.0f, 0.0f));
        _TransformlessQueue.Request_Join(FCk_Request_Queue_Join(_TransformlessEarly));
        auto Late = FCk_Request_Queue_Join(_TransformlessLateNear);
        Late.Set_Mover(_TransformlessLateNear);
        _TransformlessQueue.Request_Join(Late);
    }

    UFUNCTION()
    private void Check_TransformlessEarlyJoinDoesNotBlockNearMover(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Early;
        FCk_Queue_MemberSnapshot Late;
        const bool HasEarly = _TransformlessQueue.TryGet_MemberSnapshot(_TransformlessEarly, Early);
        const bool HasLate = _TransformlessQueue.TryGet_MemberSnapshot(_TransformlessLateNear, Late);
        auto Result = OutResult;
        Result.Set(ck::IsValid(_TransformlessQueue) && _TransformlessQueue.Get_State() == ECk_Queue_State::Ready
            && HasEarly && HasLate && Early.Get_Ticket() == 1 && Late.Get_Ticket() == 2
            && Late.Get_Rank() == 0 && Late.Get_AssignmentRevision() > 0
            && Early.Get_Rank() == 1 && Early.Get_AssignmentRevision() > 0);
    }

    UFUNCTION()
    private void Step_CreateTicketOrderQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TicketOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_TicketOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _TicketQueue = CreateQueue(_TicketOwner, ECk_Queue_ReserveAssignmentPolicy::TicketOrder);
        _TicketEarlyFar = CreateMover(InHandle, FVector(-1000.0f, 250.0f, 0.0f));
        _TicketLateNear = CreateMover(InHandle, FVector(210.0f, 250.0f, 0.0f));
        auto Early = FCk_Request_Queue_Join(_TicketEarlyFar);
        Early.Set_Mover(_TicketEarlyFar);
        _TicketQueue.Request_Join(Early);
        auto Late = FCk_Request_Queue_Join(_TicketLateNear);
        Late.Set_Mover(_TicketLateNear);
        _TicketQueue.Request_Join(Late);
    }

    UFUNCTION()
    private void Check_TicketOrderCompatibility(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Early;
        FCk_Queue_MemberSnapshot Late;
        const bool HasEarly = _TicketQueue.TryGet_MemberSnapshot(_TicketEarlyFar, Early);
        const bool HasLate = _TicketQueue.TryGet_MemberSnapshot(_TicketLateNear, Late);
        auto Result = OutResult;
        Result.Set(ck::IsValid(_TicketQueue) && _TicketQueue.Get_State() == ECk_Queue_State::Ready
            && HasEarly && HasLate && Early.Get_Ticket() == 1 && Late.Get_Ticket() == 2
            && Early.Get_Rank() == 0 && Late.Get_Rank() == 1);
    }

    UFUNCTION()
    private void Step_CreateClaimFirstQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ClaimFirstOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_ClaimFirstOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _ClaimFirstQueue = CreateClaimFirstQueue(_ClaimFirstOwner);
        _ClaimFirstQueue.BindTo_OnQueueMemberStateChanged(FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberEvent"));
        _ClaimFirstMover = CreateMover(InHandle, FVector(200.0f, 0.0f, 0.0f));
        auto Join = FCk_Request_Queue_Join(_ClaimFirstMover);
        Join.Set_Mover(_ClaimFirstMover);
        _ClaimFirstQueue.Request_Join(Join);
    }

    UFUNCTION()
    private void Check_ClaimFirstReconcilesProximity(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Mover;
        const bool HasMover = _ClaimFirstQueue.TryGet_MemberSnapshot(_ClaimFirstMover, Mover);
        auto Result = OutResult;
        Result.Set(HasMover && _ClaimFirstQueue.Get_State() == ECk_Queue_State::Ready
            && Mover.Get_Rank() == 0
            && Mover.Get_State() == ECk_Queue_MemberState::AtFront
            && _ClaimFirstSlotReachedCount == 1);
    }

    UFUNCTION()
    private void Step_CreateDestroyedArrivalQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _DestroyOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_DestroyOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _DestroyQueue = CreateQueue(_DestroyOwner, ECk_Queue_ReserveAssignmentPolicy::DistanceThenTicket);
        _DestroyQueue.BindTo_OnQueueMemberStateChanged(FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberEvent"));
        _DestroyMover = CreateMover(InHandle, FVector(-1000.0f, 0.0f, 0.0f));
        auto Join = FCk_Request_Queue_Join(_DestroyMover);
        Join.Set_Mover(_DestroyMover);
        _DestroyQueue.Request_Join(Join);
    }

    UFUNCTION()
    private void Check_DestroyMoverAssigned(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Mover;
        const bool HasMover = _DestroyQueue.TryGet_MemberSnapshot(_DestroyMover, Mover);
        auto Result = OutResult;
        Result.Set(HasMover && Mover.Get_AssignmentRevision() > 0);
    }

    UFUNCTION()
    private void Step_DestroyReservedArrival(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Mover;
        Assert_True(_DestroyQueue.TryGet_MemberSnapshot(_DestroyMover, Mover),
            "reserved mover snapshot exists at the destruction boundary");
        utils_transform::Request_SetLocation(
            _DestroyMover.As_Transform(),
            Mover.Get_TargetWorldTransform().GetLocation(),
            ECk_LocalWorld::World);
        utils_entity_lifetime::Request_DestroyEntity(_DestroyMover);
    }

    UFUNCTION()
    private void Check_DestroyedArrivalRemoved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Mover;
        const bool HasMover = _DestroyQueue.TryGet_MemberSnapshot(_DestroyMover, Mover);
        auto Result = OutResult;
        Result.Set(HasMover == false && _DestroySlotReachedCount == 0);
    }

    UFUNCTION()
    private void Step_AssertContracts(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_InitialRevision > 0 && _SwappedRevision > _InitialRevision,
            "the default-enabled phase spread still allows zero-refresh distance reflow to publish a new reservation revision");
        Assert_Equals_Int(_StableRevision, _SwappedRevision,
            "a distance refresh with unchanged mover transforms does not churn queue revisions");
        Assert_True(_ArrivedFrontRevision > 0,
            "queue-owned reconciliation detects physical arrival and preserves its assignment revision without an outcome report");
        Assert_Equals_Int(_ReservedSlotReachedCount, 1,
            "queue-owned reconciliation and a later duplicate report publish SlotReached exactly once");
        Assert_Equals_Int(_ClaimFirstSlotReachedCount, 1,
            "claim-first queues reconcile physical proximity exactly once without requiring an outcome report");
        Assert_Equals_Int(_DestroySlotReachedCount, 0,
            "a member entering destruction cannot be promoted while queue reconciliation removes it");
    }

    private FCk_Handle CreateMover(FCk_Handle InHandle, FVector InLocation)
    {
        auto Mover = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Mover, FTransform(FRotator::ZeroRotator, InLocation, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        return Mover;
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle InOwner, ECk_Queue_ReserveAssignmentPolicy InPolicy)
    {
        utils_transform::Request_SetLocation(InOwner.As_Transform(), FVector(200.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_LayoutAlgorithm(ECk_Queue_LayoutAlgorithm::Linear);
        Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ReserveOnFormation);
        Params.Set_ReserveAssignmentPolicy(InPolicy);
        Params.Set_ReserveAssignmentRefreshSeconds(0.0f);
        Params.Set_ReserveAssignmentHysteresisUu(0.0f);
        return utils_queue::Add(InOwner, Params);
    }

    private FCk_Handle_Queue CreateClaimFirstQueue(FCk_Handle InOwner)
    {
        utils_transform::Request_SetLocation(InOwner.As_Transform(), FVector(200.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_LayoutAlgorithm(ECk_Queue_LayoutAlgorithm::Linear);
        Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ClaimFirstAvailableOnReach);
        return utils_queue::Add(InOwner, Params);
    }
}

class ACk_AutoTest_Queue_ReserveDistanceAwareReflow_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Queue_ReserveDistanceAwareReflow;
    default _TimeoutSeconds = 30.0f;

    // Invalid phase-spread values must still diagnose production callers; this test owns that rejection.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("parameters are invalid");
        return Out;
    }
}
