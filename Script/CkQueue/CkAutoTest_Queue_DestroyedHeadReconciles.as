// Language=angelscript

class UCk_AutoTest_Queue_DestroyedHeadReconciles : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle       _Head;
    private FCk_Handle       _Survivor;
    private FCk_Handle       _MoverQueueOwner;
    private FCk_Handle_Queue _MoverQueue;
    private FCk_Handle       _MoverSemanticHead;
    private FCk_Handle       _DestroyedMover;
    private FCk_Handle       _FreshMover;
    private FCk_Handle       _LaterViable;
    private int32            _MemberDestroyedEvents = 0;
    private int64            _MoverSemanticTicket = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Queue = CreateQueue(_Owner);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));

        _Head = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Survivor = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join a head and survivor", n"Step_RequestJoins");
        Add_Step_WaitUntil("both members are admitted", n"Check_BothMembersPresent");
        Add_Step("destroy the head without requesting leave", n"Step_DestroyHead");
        Add_Step_WaitUntil("reconcile removes the destroyed head", n"Check_HeadReconciled");
        Add_Step("assert one destruction event and survivor promotion", n"Step_AssertReconciled");
        Add_Step("compose a separate claim-policy queue for optional-mover recovery", n"Step_ComposeOptionalMoverQueue");
        Add_Step_WaitUntil("optional-mover queue setup completes before admission", n"Check_OptionalMoverQueueSetup");
        Add_Step("create optional-mover semantic and mover entities", n"Step_CreateOptionalMoverEntities");
        Add_Step_WaitUntil("optional-mover entities complete deferred creation", n"Check_OptionalMoverEntitiesReady");
        Add_Step("request optional-mover joins after every entity is valid", n"Step_RequestOptionalMoverJoins");
        Add_Step_WaitUntil("optional-mover joins publish both semantic members", n"Check_OptionalMoverJoinsAdmitted");
        Add_Step("assert optional-mover admission identity before any reservation offer", n"Step_AssertOptionalMoverAdmission");
        Add_Step_WaitUntil("optional-mover queue assigns its semantic head", n"Check_OptionalMoverQueueReady");
        Add_Step("destroy only the optional mover", n"Step_DestroyOptionalMover");
        Add_Step_WaitUntil("destroyed mover yields rank zero to the later viable member", n"Check_DestroyedMoverYielded");
        Add_Step("refresh the semantic member with a fresh mover", n"Step_RequestFreshMover");
        Add_Step_WaitUntil("fresh mover rejoin restores a live assignment without ticket churn", n"Check_FreshMoverRestored");
        Add_Step("assert destroyed-mover recovery preserves semantic membership", n"Step_AssertFreshMoverRecovery");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue == _Queue && InEvent.Get_Reason() == ECk_Queue_EventReason::MemberDestroyed
            && InEvent.Get_Member().Get_Member() == _Head)
        { _MemberDestroyedEvents += 1; }
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
        _Queue.Request_Join(FCk_Request_Queue_Join(_Head));
        _Queue.Request_Join(FCk_Request_Queue_Join(_Survivor));
    }

    UFUNCTION()
    private void Check_BothMembersPresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Queue.Get_MemberCount() == 2);
    }

    UFUNCTION()
    private void Step_DestroyHead(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_Head);
    }

    UFUNCTION()
    private void Check_HeadReconciled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Survivor;
        const bool HasSurvivor = _Queue.TryGet_MemberSnapshot(_Survivor, Survivor);
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Head) && HasSurvivor && Survivor.Get_Rank() == 0
            && _Queue.Get_IsMember(_Head) == false && _MemberDestroyedEvents == 1);
    }

    UFUNCTION()
    private void Step_AssertReconciled(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Queue.Get_MemberCount(), 1, "destroyed head is removed without an explicit leave");
        Assert_Equals_Int(_MemberDestroyedEvents, 1, "destroyed head produces exactly one MemberDestroyed event");
        const auto Members = _Queue.Get_Members();
        Assert_True(Members[0].Get_Member() == _Survivor && Members[0].Get_Rank() == 0,
            "survivor becomes rank-zero front");
    }

    UFUNCTION()
    private void Step_ComposeOptionalMoverQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _MoverQueueOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_MoverQueueOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _MoverQueue = CreateClaimQueue(_MoverQueueOwner);
    }

    UFUNCTION()
    private void Check_OptionalMoverQueueSetup(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_MoverQueue) && _MoverQueue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_CreateOptionalMoverEntities(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _MoverSemanticHead = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _DestroyedMover = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _FreshMover = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _LaterViable = utils_entity_lifetime::Request_CreateEntity(InHandle);
    }

    UFUNCTION()
    private void Check_OptionalMoverEntitiesReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_MoverSemanticHead) && ck::IsValid(_DestroyedMover)
            && ck::IsValid(_FreshMover) && ck::IsValid(_LaterViable));
    }

    UFUNCTION()
    private void Step_RequestOptionalMoverJoins(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto HeadJoin = FCk_Request_Queue_Join(_MoverSemanticHead);
        HeadJoin.Set_Mover(_DestroyedMover);
        _MoverQueue.Request_Join(HeadJoin);
        auto LaterJoin = FCk_Request_Queue_Join(_LaterViable);
        LaterJoin.Set_Mover(_LaterViable);
        _MoverQueue.Request_Join(LaterJoin);
    }

    UFUNCTION()
    private void Check_OptionalMoverJoinsAdmitted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot SemanticHead;
        FCk_Queue_MemberSnapshot Later;
        const bool HasSemanticHead = _MoverQueue.TryGet_MemberSnapshot(_MoverSemanticHead, SemanticHead);
        const bool HasLater = _MoverQueue.TryGet_MemberSnapshot(_LaterViable, Later);
        auto Result = OutResult;
        Result.Set(_MoverQueue.Get_MemberCount() == 2 && HasSemanticHead && HasLater);
    }

    UFUNCTION()
    private void Step_AssertOptionalMoverAdmission(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot SemanticHead;
        FCk_Queue_MemberSnapshot Later;
        Assert_True(_MoverQueue.TryGet_MemberSnapshot(_MoverSemanticHead, SemanticHead),
            "optional-mover semantic head is admitted before reservation offering");
        Assert_True(_MoverQueue.TryGet_MemberSnapshot(_LaterViable, Later),
            "later viable member is admitted before reservation offering");
        Assert_True(SemanticHead.Get_Ticket() < Later.Get_Ticket(),
            "semantic head keeps the earlier admission ticket");
        Assert_True(SemanticHead.Get_Mover() == _DestroyedMover,
            "semantic head retains its distinct optional mover at admission");
        Assert_True(Later.Get_Mover() == _LaterViable,
            "later viable member uses its own valid mover at admission");
    }

    UFUNCTION()
    private void Check_OptionalMoverQueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot SemanticHead;
        FCk_Queue_MemberSnapshot Later;
        const bool HasSemanticHead = _MoverQueue.TryGet_MemberSnapshot(_MoverSemanticHead, SemanticHead);
        const bool HasLater = _MoverQueue.TryGet_MemberSnapshot(_LaterViable, Later);
        if (HasSemanticHead) { _MoverSemanticTicket = SemanticHead.Get_Ticket(); }
        auto Result = OutResult;
        Result.Set(ck::IsValid(_MoverQueue) && HasSemanticHead
            && _MoverQueue.Get_MemberCount() == 2 && _MoverSemanticTicket > 0
            && SemanticHead.Get_Mover() == _DestroyedMover && SemanticHead.Get_Rank() == 0
            && SemanticHead.Get_AssignmentRevision() > 0
            && SemanticHead.Get_State() == ECk_Queue_MemberState::MovingToSlot);
    }

    UFUNCTION()
    private void Step_DestroyOptionalMover(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_DestroyedMover);
    }

    UFUNCTION()
    private void Check_DestroyedMoverYielded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot SemanticHead;
        FCk_Queue_MemberSnapshot Later;
        const bool HasSemanticHead = _MoverQueue.TryGet_MemberSnapshot(_MoverSemanticHead, SemanticHead);
        const bool HasLater = _MoverQueue.TryGet_MemberSnapshot(_LaterViable, Later);
        auto Result = OutResult;
        Result.Set(HasSemanticHead && HasLater && _MoverQueue.Get_MemberCount() == 2
            && SemanticHead.Get_State() == ECk_Queue_MemberState::WaitingForMover
            && SemanticHead.Get_AssignmentRevision() == 0
            && Later.Get_Rank() == 0 && Later.Get_AssignmentRevision() > 0);
    }

    UFUNCTION()
    private void Step_RequestFreshMover(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Rejoin = FCk_Request_Queue_Join(_MoverSemanticHead);
        Rejoin.Set_Mover(_FreshMover);
        _MoverQueue.Request_Join(Rejoin);
    }

    UFUNCTION()
    private void Check_FreshMoverRestored(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot SemanticHead;
        const bool HasSemanticHead = _MoverQueue.TryGet_MemberSnapshot(_MoverSemanticHead, SemanticHead);
        auto Result = OutResult;
        Result.Set(HasSemanticHead && SemanticHead.Get_Mover() == _FreshMover
            && SemanticHead.Get_Ticket() == _MoverSemanticTicket
            && SemanticHead.Get_AssignmentRevision() > 0
            && (SemanticHead.Get_State() == ECk_Queue_MemberState::Assigned
                || SemanticHead.Get_State() == ECk_Queue_MemberState::MovingToSlot));
    }

    UFUNCTION()
    private void Step_AssertFreshMoverRecovery(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot SemanticHead;
        Assert_True(_MoverQueue.TryGet_MemberSnapshot(_MoverSemanticHead, SemanticHead),
            "semantic member survives optional mover destruction and rejoin");
        Assert_True(SemanticHead.Get_Ticket() == _MoverSemanticTicket,
            "fresh mover rejoin restores movement without minting a new ticket");
        Assert_True(SemanticHead.Get_Mover() == _FreshMover && SemanticHead.Get_AssignmentRevision() > 0,
            "fresh mover rejoin restores a real current reservation");
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle& InOwner)
    {
        return utils_queue::Add(InOwner, FCk_Fragment_Queue_ParamsData());
    }

    private FCk_Handle_Queue CreateClaimQueue(FCk_Handle& InOwner)
    {
        utils_transform::Request_SetLocation(InOwner.As_Transform(), FVector(200.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ClaimFirstAvailableOnReach);
        return utils_queue::Add(InOwner, Params);
    }
}
