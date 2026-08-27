// Language=angelscript

// ClaimFirst must reconcile transform proximity itself. This deliberately never reports a movement outcome.
class UCk_AutoTest_Queue_ClaimFirstTransformProximityReconciles : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private TArray<FCk_Handle> _Members;
    private FTransform       _InitialTarget;
    private FTransform       _ReopenedTarget;
    private int32            _InitialRevision = 0;
    private int32            _ReopenedRevision = 0;
    private int32            _SlotReachedEvents = 0;
    private int32            _AdvanceCompletions = 0;
    private ECk_Request_OperationResult _FirstAdvanceResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _SecondAdvanceResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Queue = CreateQueue(_Owner);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));

        for (int32 Index = 0; Index < 3; ++Index)
        {
            auto Member = utils_entity_lifetime::Request_CreateEntity(InHandle);
            utils_transform::Add(Member,
                FTransform(FVector(-900.0f, float(Index - 1) * 160.0f, 0.0f)),
                ECk_Replication::DoesNotReplicate);
            _Members.Add(Member);
        }

        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);

        Add_Step_WaitUntil("ClaimFirst queue setup completes", n"Check_QueueReady", 1200);
        Add_Step("join three transform-backed ClaimFirst contenders", n"Step_RequestJoins");
        Add_Step_WaitUntil("all contenders receive the shared provisional front offer", n"Check_InitialSharedOffers", 1200);
        Add_Step("place one contender inside the claim radius without reporting movement", n"Step_MoveFirstContenderIntoClaimRadius");
        Add_Step_WaitUntil("queue reconciliation claims exactly one front and retargets losers", n"Check_FirstTransformClaimed");
        Add_Step("advance the queue-owned first transform claim", n"Step_RequestFirstAdvance");
        Add_Step_WaitUntil("first advance succeeds and republishes provisional front offers", n"Check_FirstAdvanceAndReopenedOffers", 1200);
        Add_Step("place the next contender inside the reopened claim radius without reporting movement", n"Step_MoveSecondContenderIntoClaimRadius");
        Add_Step_WaitUntil("queue reconciliation claims the reopened front exactly once", n"Check_SecondTransformClaimed");
        Add_Step("advance the queue-owned second transform claim", n"Step_RequestSecondAdvance");
        Add_Step_WaitUntil("second advance succeeds", n"Check_SecondAdvanceSucceeded");
        Add_Step("assert ClaimFirst transform-proximity reconciliation lifecycle", n"Step_AssertLifecycle");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue == _Queue && InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached)
        { _SlotReachedEvents += 1; }
    }

    UFUNCTION()
    private void OnAdvanceCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _AdvanceCompletions += 1;
        if (_AdvanceCompletions == 1) { _FirstAdvanceResult = InResult; }
        else if (_AdvanceCompletions == 2) { _SecondAdvanceResult = InResult; }
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
        for (const auto& Member : _Members)
        {
            auto Join = FCk_Request_Queue_Join(Member);
            Join.Set_Mover(Member);
            _Queue.Request_Join(Join);
        }
    }

    UFUNCTION()
    private void Check_InitialSharedOffers(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        int32 SharedOfferCount = 0;
        bool SharedTarget = true;
        for (const auto& Member : _Queue.Get_Members())
        {
            if (Member.Get_State() != ECk_Queue_MemberState::MovingToSlot || Member.Get_Rank() != 0)
            { continue; }
            if (_InitialRevision == 0)
            {
                _InitialRevision = Member.Get_AssignmentRevision();
                _InitialTarget = Member.Get_TargetWorldTransform();
            }
            SharedOfferCount += 1;
            SharedTarget = SharedTarget && Member.Get_AssignmentRevision() == _InitialRevision
                && Member.Get_TargetWorldTransform().Equals(_InitialTarget);
        }
        auto Result = OutResult;
        Result.Set(_Queue.Get_MemberCount() == 3 && SharedOfferCount == 3 && SharedTarget
            && _InitialRevision > 0);
    }

    UFUNCTION()
    private void Step_MoveFirstContenderIntoClaimRadius(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_transform::Request_SetLocation(_Members[0], _InitialTarget.GetLocation(), ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void Check_FirstTransformClaimed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Winner;
        FCk_Queue_MemberSnapshot FirstLoser;
        FCk_Queue_MemberSnapshot SecondLoser;
        const bool HasWinner = _Queue.TryGet_MemberSnapshot(_Members[0], Winner);
        const bool HasFirstLoser = _Queue.TryGet_MemberSnapshot(_Members[1], FirstLoser);
        const bool HasSecondLoser = _Queue.TryGet_MemberSnapshot(_Members[2], SecondLoser);
        auto Result = OutResult;
        Result.Set(HasWinner && HasFirstLoser && HasSecondLoser
            && Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Winner.Get_AssignmentRevision() == _InitialRevision
            && FirstLoser.Get_State() == ECk_Queue_MemberState::MovingToSlot && FirstLoser.Get_Rank() == 1
            && SecondLoser.Get_State() == ECk_Queue_MemberState::MovingToSlot && SecondLoser.Get_Rank() == 1
            && FirstLoser.Get_AssignmentRevision() > _InitialRevision
            && SecondLoser.Get_AssignmentRevision() > _InitialRevision
            && FirstLoser.Get_AssignmentRevision() == SecondLoser.Get_AssignmentRevision()
            && FirstLoser.Get_TargetWorldTransform().Equals(SecondLoser.Get_TargetWorldTransform())
            && _SlotReachedEvents == 1);
    }

    UFUNCTION()
    private void Step_RequestFirstAdvance(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Advance(FCk_Request_Queue_Advance(),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvanceCompleted"));
    }

    UFUNCTION()
    private void Check_FirstAdvanceAndReopenedOffers(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        int32 SharedOfferCount = 0;
        bool SharedTarget = true;
        for (const auto& Member : _Queue.Get_Members())
        {
            if (Member.Get_State() != ECk_Queue_MemberState::MovingToSlot || Member.Get_Rank() != 0)
            { continue; }
            if (_ReopenedRevision == 0)
            {
                _ReopenedRevision = Member.Get_AssignmentRevision();
                _ReopenedTarget = Member.Get_TargetWorldTransform();
            }
            SharedOfferCount += 1;
            SharedTarget = SharedTarget && Member.Get_AssignmentRevision() == _ReopenedRevision
                && Member.Get_TargetWorldTransform().Equals(_ReopenedTarget);
        }
        auto Result = OutResult;
        Result.Set(_AdvanceCompletions == 1 && _FirstAdvanceResult == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_MemberCount() == 2 && _Queue.Get_IsMember(_Members[0]) == false
            && SharedOfferCount == 2 && SharedTarget && _ReopenedRevision > _InitialRevision
            && _SlotReachedEvents == 1);
    }

    UFUNCTION()
    private void Step_MoveSecondContenderIntoClaimRadius(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_transform::Request_SetLocation(_Members[1], _ReopenedTarget.GetLocation(), ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void Check_SecondTransformClaimed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Winner;
        FCk_Queue_MemberSnapshot Loser;
        const bool HasWinner = _Queue.TryGet_MemberSnapshot(_Members[1], Winner);
        const bool HasLoser = _Queue.TryGet_MemberSnapshot(_Members[2], Loser);
        auto Result = OutResult;
        Result.Set(HasWinner && HasLoser
            && Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Winner.Get_AssignmentRevision() == _ReopenedRevision
            && Loser.Get_State() == ECk_Queue_MemberState::MovingToSlot && Loser.Get_Rank() == 1
            && Loser.Get_AssignmentRevision() > _ReopenedRevision
            && _SlotReachedEvents == 2);
    }

    UFUNCTION()
    private void Step_RequestSecondAdvance(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Advance(FCk_Request_Queue_Advance(),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvanceCompleted"));
    }

    UFUNCTION()
    private void Check_SecondAdvanceSucceeded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_AdvanceCompletions == 2 && _SecondAdvanceResult == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_MemberCount() == 1 && _Queue.Get_IsMember(_Members[1]) == false
            && _SlotReachedEvents == 2);
    }

    UFUNCTION()
    private void Step_AssertLifecycle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_SlotReachedEvents, 2,
            "two transform-only proximity claims each emit exactly one SlotReached event");
        Assert_True(_FirstAdvanceResult == ECk_Request_OperationResult::Succeeded
            && _SecondAdvanceResult == ECk_Request_OperationResult::Succeeded,
            "both queue-owned transform claims become advanceable fronts without movement outcome reports");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 1,
            "two successful advances remove exactly the two transform-proximity winners");
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle InOwner)
    {
        utils_transform::Request_SetLocation(InOwner.As_Transform(), FVector(200.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_LayoutAlgorithm(ECk_Queue_LayoutAlgorithm::Linear);
        Params.Set_SlotSpacingUu(120.0f);
        Params.Set_SlotClaimRadiusUu(30.0f);
        Params.Set_SlotSettleRadiusUu(10.0f);
        Params.Set_SlotReacquireRadiusUu(20.0f);
        Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ClaimFirstAvailableOnReach);
        Params.Set_HardLimit(3);
        Params.Set_SoftLimit(3);
        return utils_queue::Add(InOwner, Params);
    }
}
