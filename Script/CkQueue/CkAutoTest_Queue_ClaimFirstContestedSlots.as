// Language=angelscript

class UCk_AutoTest_Queue_ClaimFirstContestedSlots : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private TArray<FCk_Handle> _Members;
    private FCk_Handle       _Origin0First;
    private FCk_Handle       _Origin0Second;
    private FCk_Handle       _Origin1First;
    private FCk_Handle       _Origin1Second;
    private FTransform       _Origin0InitialTarget;
    private FTransform       _Origin1InitialTarget;
    private int32            _Origin0InitialRevision = 0;
    private int32            _Origin1InitialRevision = 0;
    private int32            _Origin0WinnerCompletions = 0;
    private int32            _Origin0LoserCompletions = 0;
    private int32            _Origin1WinnerCompletions = 0;
    private int32            _Origin1LoserCompletions = 0;
    private int32            _Origin0SlotReachedEvents = 0;
    private int32            _Origin1SlotReachedEvents = 0;
    private ECk_Request_OperationResult _Origin0WinnerResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _Origin0LoserResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _Origin1WinnerResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _Origin1LoserResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Queue = CreateQueue(_Owner);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));
        for (auto Index = 0; Index < 4; ++Index)
        { _Members.Add(utils_entity_lifetime::Request_CreateEntity(InHandle)); }

        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join four contenders across two origins", n"Step_RequestJoins");
        Add_Step_WaitUntil("all contenders receive their origin's provisional target", n"Check_InitialContestedAssignments");
        Add_Step("report origin zero's second contender before its first contender in one drain", n"Step_ReportOrigin0ContestedReach");
        Add_Step_WaitUntil("both origin zero contested reports complete", n"Check_Origin0ReportsCompleted");
        Add_Step("assert origin zero keeps the first reached contender and retargets its loser", n"Step_AssertOrigin0Claim");
        Add_Step("report origin one's first contender before its second contender in one drain", n"Step_ReportOrigin1ContestedReach");
        Add_Step_WaitUntil("origin one independently keeps its first reached contender and retargets its loser", n"Check_Origin1Claim");
        Add_Step("assert first-come claims, stale no-ops, and independent origins", n"Step_AssertClaims");
        Add_Step("leave the origin-zero provisional loser", n"Step_RequestOrigin0LoserLeave");
        Add_Step_WaitUntil("leaving a provisional loser preserves both claimed winners", n"Check_Origin0LoserLeft");
        Add_Step("assert explicit loser leave does not disturb claimed winners", n"Step_AssertOrigin0LoserLeft");
        Add_Step("destroy the origin-one provisional loser without leaving", n"Step_DestroyOrigin1Loser");
        Add_Step_WaitUntil("reconciliation removes the destroyed provisional loser without disturbing claimed winners", n"Check_Origin1LoserDestroyed");
        Add_Step("assert destroyed loser reconciliation preserves claimed winners", n"Step_AssertOrigin1LoserDestroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue != _Queue || InEvent.Get_Reason() != ECk_Queue_EventReason::SlotReached) { return; }
        const auto Member = InEvent.Get_Member();
        if (Member.Get_OriginIndex() == 0) { _Origin0SlotReachedEvents += 1; }
        if (Member.Get_OriginIndex() == 1) { _Origin1SlotReachedEvents += 1; }
    }

    UFUNCTION()
    private void OnOrigin0WinnerCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Origin0WinnerCompletions += 1;
        _Origin0WinnerResult = InResult;
    }

    UFUNCTION()
    private void OnOrigin0LoserCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Origin0LoserCompletions += 1;
        _Origin0LoserResult = InResult;
    }

    UFUNCTION()
    private void OnOrigin1WinnerCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Origin1WinnerCompletions += 1;
        _Origin1WinnerResult = InResult;
    }

    UFUNCTION()
    private void OnOrigin1LoserCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Origin1LoserCompletions += 1;
        _Origin1LoserResult = InResult;
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
        { _Queue.Request_Join(FCk_Request_Queue_Join(Member)); }
    }

    UFUNCTION()
    private void Check_InitialContestedAssignments(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Origin0Count = 0;
        auto Origin1Count = 0;
        auto Origin0Matches = true;
        auto Origin1Matches = true;
        for (const auto& Member : _Queue.Get_Members())
        {
            if (Member.Get_State() != ECk_Queue_MemberState::MovingToSlot || Member.Get_Rank() != 0)
            { continue; }
            if (Member.Get_OriginIndex() == 0)
            {
                Origin0Count += 1;
                if (ck::Is_NOT_Valid(_Origin0First))
                {
                    _Origin0First = Member.Get_Member();
                    _Origin0InitialRevision = Member.Get_AssignmentRevision();
                    _Origin0InitialTarget = Member.Get_TargetWorldTransform();
                }
                else
                {
                    _Origin0Second = Member.Get_Member();
                    Origin0Matches = Member.Get_AssignmentRevision() == _Origin0InitialRevision
                        && Member.Get_TargetWorldTransform().Equals(_Origin0InitialTarget);
                }
            }
            else if (Member.Get_OriginIndex() == 1)
            {
                Origin1Count += 1;
                if (ck::Is_NOT_Valid(_Origin1First))
                {
                    _Origin1First = Member.Get_Member();
                    _Origin1InitialRevision = Member.Get_AssignmentRevision();
                    _Origin1InitialTarget = Member.Get_TargetWorldTransform();
                }
                else
                {
                    _Origin1Second = Member.Get_Member();
                    Origin1Matches = Member.Get_AssignmentRevision() == _Origin1InitialRevision
                        && Member.Get_TargetWorldTransform().Equals(_Origin1InitialTarget);
                }
            }
        }
        auto Result = OutResult;
        Result.Set(_Queue.Get_MemberCount() == 4
            && Origin0Count == 2 && Origin1Count == 2 && Origin0Matches && Origin1Matches
            && _Origin0InitialRevision > 0 && _Origin1InitialRevision > 0
            && _Origin0InitialTarget.Equals(_Origin1InitialTarget) == false
            && ck::IsValid(_Origin0Second) && ck::IsValid(_Origin1Second));
    }

    UFUNCTION()
    private void Step_ReportOrigin0ContestedReach(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_ReportMovementOutcome(FCk_Request_Queue_ReportMovementOutcome(
            _Origin0Second, _Origin0InitialRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnOrigin0WinnerCompleted"));
        _Queue.Request_ReportMovementOutcome(FCk_Request_Queue_ReportMovementOutcome(
            _Origin0First, _Origin0InitialRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnOrigin0LoserCompleted"));
    }

    UFUNCTION()
    private void Check_Origin0ReportsCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Origin0WinnerCompletions == 1 && _Origin0LoserCompletions == 1);
    }

    UFUNCTION()
    private void Step_AssertOrigin0Claim(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin0Winner;
        FCk_Queue_MemberSnapshot Origin0Loser;
        FCk_Queue_MemberSnapshot Origin1First;
        FCk_Queue_MemberSnapshot Origin1Second;
        const bool HasOrigin0Winner = _Queue.TryGet_MemberSnapshot(_Origin0Second, Origin0Winner);
        const bool HasOrigin0Loser = _Queue.TryGet_MemberSnapshot(_Origin0First, Origin0Loser);
        const bool HasOrigin1First = _Queue.TryGet_MemberSnapshot(_Origin1First, Origin1First);
        const bool HasOrigin1Second = _Queue.TryGet_MemberSnapshot(_Origin1Second, Origin1Second);
        Assert_True(HasOrigin0Winner && HasOrigin0Loser && HasOrigin1First && HasOrigin1Second,
            "all origin-zero and untouched origin-one contender snapshots remain queryable");
        Assert_True(Origin0Winner.Get_State() == ECk_Queue_MemberState::AtFront,
            "the first processed origin-zero arrival owns the front slot");
        Assert_Equals_Int(Origin0Winner.Get_AssignmentRevision(), _Origin0InitialRevision,
            "the origin-zero winner retains the provisional assignment revision it reached");
        Assert_True(Origin0Loser.Get_State() == ECk_Queue_MemberState::MovingToSlot && Origin0Loser.Get_Rank() == 1,
            "the origin-zero loser is retargeted to the next free rank");
        Assert_True(Origin0Loser.Get_AssignmentRevision() > _Origin0InitialRevision,
            "the origin-zero loser receives a newer assignment revision");
        Assert_True(Origin0Loser.Get_TargetWorldTransform().Equals(_Origin0InitialTarget) == false,
            "the origin-zero loser's target changes only after the winner claims rank zero");
        Assert_True(Origin1First.Get_State() == ECk_Queue_MemberState::MovingToSlot && Origin1First.Get_Rank() == 0
            && Origin1Second.Get_State() == ECk_Queue_MemberState::MovingToSlot && Origin1Second.Get_Rank() == 0,
            "origin-one contenders remain on their unclaimed rank-zero target");
        Assert_True(Origin1First.Get_AssignmentRevision() == _Origin1InitialRevision
            && Origin1Second.Get_AssignmentRevision() == _Origin1InitialRevision,
            "an origin-zero claim does not refresh untouched origin-one assignment revisions");
        Assert_True(Origin1First.Get_TargetWorldTransform().Equals(_Origin1InitialTarget)
            && Origin1Second.Get_TargetWorldTransform().Equals(_Origin1InitialTarget),
            "an origin-zero claim does not change untouched origin-one targets");
        Assert_True(_Origin0WinnerResult == ECk_Request_OperationResult::Succeeded
            && _Origin0LoserResult == ECk_Request_OperationResult::Succeeded,
            "winner and stale same-drain loser reports both complete successfully");
        Assert_True(_Origin0SlotReachedEvents == 1 && _Origin1SlotReachedEvents == 0,
            "only the first origin-zero contender emits SlotReached");
    }

    UFUNCTION()
    private void Step_ReportOrigin1ContestedReach(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_ReportMovementOutcome(FCk_Request_Queue_ReportMovementOutcome(
            _Origin1First, _Origin1InitialRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnOrigin1WinnerCompleted"));
        _Queue.Request_ReportMovementOutcome(FCk_Request_Queue_ReportMovementOutcome(
            _Origin1Second, _Origin1InitialRevision, ECk_Queue_MovementOutcome::Reached),
            FCk_Delegate_Request_OnCompleted(this, n"OnOrigin1LoserCompleted"));
    }

    UFUNCTION()
    private void Check_Origin1Claim(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin1Winner;
        FCk_Queue_MemberSnapshot Origin1Loser;
        const bool HasOrigin1Winner = _Queue.TryGet_MemberSnapshot(_Origin1First, Origin1Winner);
        const bool HasOrigin1Loser = _Queue.TryGet_MemberSnapshot(_Origin1Second, Origin1Loser);
        auto Result = OutResult;
        Result.Set(HasOrigin1Winner && HasOrigin1Loser
            && Origin1Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin1Winner.Get_AssignmentRevision() == _Origin1InitialRevision
            && Origin1Loser.Get_State() == ECk_Queue_MemberState::MovingToSlot && Origin1Loser.Get_Rank() == 1
            && Origin1Loser.Get_AssignmentRevision() > _Origin1InitialRevision
            && Origin1Loser.Get_TargetWorldTransform().Equals(_Origin1InitialTarget) == false
            && _Origin1WinnerCompletions == 1 && _Origin1LoserCompletions == 1
            && _Origin1WinnerResult == ECk_Request_OperationResult::Succeeded
            && _Origin1LoserResult == ECk_Request_OperationResult::Succeeded
            && _Origin0SlotReachedEvents == 1 && _Origin1SlotReachedEvents == 1);
    }

    UFUNCTION()
    private void Step_AssertClaims(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Origin0WinnerCompletions, 1, "first origin-zero arrival completes exactly once");
        Assert_Equals_Int(_Origin0LoserCompletions, 1, "stale origin-zero loser arrival completes exactly once as a no-op");
        Assert_Equals_Int(_Origin1WinnerCompletions, 1, "first origin-one arrival completes exactly once");
        Assert_Equals_Int(_Origin1LoserCompletions, 1, "stale origin-one loser arrival completes exactly once as a no-op");
        Assert_Equals_Int(_Origin0SlotReachedEvents, 1, "origin zero emits SlotReached only for its first reported contender");
        Assert_Equals_Int(_Origin1SlotReachedEvents, 1, "origin one emits SlotReached only for its first reported contender");
    }

    UFUNCTION()
    private void Step_RequestOrigin0LoserLeave(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Leave(FCk_Request_Queue_Leave(_Origin0First));
    }

    UFUNCTION()
    private void Check_Origin0LoserLeft(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin0Winner;
        FCk_Queue_MemberSnapshot Origin1Winner;
        const bool HasOrigin0Winner = _Queue.TryGet_MemberSnapshot(_Origin0Second, Origin0Winner);
        const bool HasOrigin1Winner = _Queue.TryGet_MemberSnapshot(_Origin1First, Origin1Winner);
        auto Result = OutResult;
        Result.Set(HasOrigin0Winner && HasOrigin1Winner
            && _Queue.Get_MemberCount() == 3 && _Queue.Get_IsMember(_Origin0First) == false
            && Origin0Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin0Winner.Get_AssignmentRevision() == _Origin0InitialRevision
            && Origin1Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin1Winner.Get_AssignmentRevision() == _Origin1InitialRevision
            && _Origin0SlotReachedEvents == 1 && _Origin1SlotReachedEvents == 1);
    }

    UFUNCTION()
    private void Step_AssertOrigin0LoserLeft(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin0Winner;
        FCk_Queue_MemberSnapshot Origin1Winner;
        Assert_True(_Queue.TryGet_MemberSnapshot(_Origin0Second, Origin0Winner)
            && _Queue.TryGet_MemberSnapshot(_Origin1First, Origin1Winner),
            "both claimed winners remain queryable after the provisional loser leaves");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 3, "explicit loser leave removes exactly one queue member");
        Assert_True(_Queue.Get_IsMember(_Origin0First) == false,
            "explicitly leaving provisional loser no longer belongs to the queue");
        Assert_True(Origin0Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin0Winner.Get_AssignmentRevision() == _Origin0InitialRevision
            && Origin1Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin1Winner.Get_AssignmentRevision() == _Origin1InitialRevision,
            "explicit loser leave preserves both claimed winners and their original revisions");
        Assert_True(_Origin0SlotReachedEvents == 1 && _Origin1SlotReachedEvents == 1,
            "explicit loser leave emits no additional SlotReached event");
    }

    UFUNCTION()
    private void Step_DestroyOrigin1Loser(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_Origin1Second);
    }

    UFUNCTION()
    private void Check_Origin1LoserDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin0Winner;
        FCk_Queue_MemberSnapshot Origin1Winner;
        const bool HasOrigin0Winner = _Queue.TryGet_MemberSnapshot(_Origin0Second, Origin0Winner);
        const bool HasOrigin1Winner = _Queue.TryGet_MemberSnapshot(_Origin1First, Origin1Winner);
        auto Result = OutResult;
        Result.Set(HasOrigin0Winner && HasOrigin1Winner
            && ck::Is_NOT_Valid(_Origin1Second) && _Queue.Get_IsMember(_Origin1Second) == false
            && _Queue.Get_MemberCount() == 2
            && Origin0Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin0Winner.Get_AssignmentRevision() == _Origin0InitialRevision
            && Origin1Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin1Winner.Get_AssignmentRevision() == _Origin1InitialRevision
            && _Origin0SlotReachedEvents == 1 && _Origin1SlotReachedEvents == 1);
    }

    UFUNCTION()
    private void Step_AssertOrigin1LoserDestroyed(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin0Winner;
        FCk_Queue_MemberSnapshot Origin1Winner;
        Assert_True(_Queue.TryGet_MemberSnapshot(_Origin0Second, Origin0Winner)
            && _Queue.TryGet_MemberSnapshot(_Origin1First, Origin1Winner),
            "both claimed winners remain queryable after provisional-loser reconciliation");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 2, "destroyed provisional loser reconciliation removes exactly one queue member");
        Assert_True(ck::Is_NOT_Valid(_Origin1Second) && _Queue.Get_IsMember(_Origin1Second) == false,
            "destroyed provisional loser is invalid and no longer belongs to the queue");
        Assert_True(Origin0Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin0Winner.Get_AssignmentRevision() == _Origin0InitialRevision
            && Origin1Winner.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin1Winner.Get_AssignmentRevision() == _Origin1InitialRevision,
            "destroyed loser reconciliation preserves both claimed winners and their original revisions");
        Assert_True(_Origin0SlotReachedEvents == 1 && _Origin1SlotReachedEvents == 1,
            "destroyed loser reconciliation emits no additional SlotReached event");
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle& InOwner)
    {
        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform(FVector(200.0f, 0.0f, 0.0f))));
        Origins.Add(FCk_Queue_Origin(FTransform(FVector(200.0f, 480.0f, 0.0f))));
        auto Params = FCk_Fragment_Queue_ParamsData(Origins);
        Params.Set_SoftLimit(4);
        Params.Set_HardLimit(4);
        Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ClaimFirstAvailableOnReach);
        return utils_queue::Add(InOwner, Params);
    }
}
