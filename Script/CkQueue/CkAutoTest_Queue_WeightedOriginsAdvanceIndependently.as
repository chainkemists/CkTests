// Language=angelscript

class UCk_AutoTest_Queue_WeightedOriginsAdvanceIndependently : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private TArray<FCk_Handle> _Members;
    private FCk_Handle       _Origin0Front;
    private FCk_Handle       _Origin1Front;
    private FCk_Handle       _Origin0Next;
    private FCk_Handle       _Origin1Next;
    private FTransform       _Origin1FrontTarget;
    private int32            _FirstClaimEvents = 0;
    private int32            _SecondOfferEvents = 0;
    private int32            _ServingAdvancedEvents = 0;
    private int32            _Origin0ServingAdvancedEvents = 0;
    private int32            _AdvanceCompletions = 0;
    private int32            _Origin0FrontRevision = 0;
    private int32            _Origin1FrontRevision = 0;
    private ECk_Request_OperationResult _Advance0Result = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _Advance0SpamOneResult = ECk_Request_OperationResult::Succeeded;
    private ECk_Request_OperationResult _Advance0SpamTwoResult = ECk_Request_OperationResult::Succeeded;
    private ECk_Request_OperationResult _Advance1Result = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Queue = CreateWeightedQueue(_Owner);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));
        for (auto Index = 0; Index < 6; ++Index)
        { _Members.Add(utils_entity_lifetime::Request_CreateEntity(InHandle)); }

        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join six globally ticketed members", n"Step_RequestJoins");
        Add_Step_WaitUntil("claim-first policy offers one rank-zero reservation per origin", n"Check_InitialOffers");
        Add_Step("assert weighted membership and pending reservations", n"Step_AssertInitialOffers");
        Add_Step("report both offered fronts reached", n"Step_ReportBothFrontsReached");
        Add_Step_WaitUntil("each reached claim unlocks the next rank", n"Check_SecondOffers");
        Add_Step("assert later members were not offered before their origin claim", n"Step_AssertSecondOffers");
        Add_Step("advance origin zero without touching origin one", n"Step_RequestOrigin0Advance");
        Add_Step_WaitUntil("origin zero advance preserves origin one's active claim", n"Check_Origin0AdvancePreservesOrigin1");
        Add_Step("advance origin one after its unchanged claim remains serviceable", n"Step_RequestOrigin1Advance");
        Add_Step_WaitUntil("both independent advances remove only their own served fronts", n"Check_IndependentAdvancesSettled");
        Add_Step("assert independent advance preserves weighted survivor state", n"Step_AssertIndependentAdvances");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue != _Queue) { return; }
        const auto Member = InEvent.Get_Member();
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached
            && (Member.Get_Member() == _Origin0Front || Member.Get_Member() == _Origin1Front))
        { _FirstClaimEvents += 1; }
        if (Member.Get_State() == ECk_Queue_MemberState::MovingToSlot && Member.Get_Rank() == 1)
        { _SecondOfferEvents += 1; }
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::Advanced
            && Member.Get_State() == ECk_Queue_MemberState::Serving)
        {
            _ServingAdvancedEvents += 1;
            if (Member.Get_OriginIndex() == 0) { _Origin0ServingAdvancedEvents += 1; }
        }
    }

    UFUNCTION()
    private void OnAdvance0Completed(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _AdvanceCompletions += 1;
        _Advance0Result = InResult;
    }

    UFUNCTION()
    private void OnAdvance1Completed(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _AdvanceCompletions += 1;
        _Advance1Result = InResult;
    }

    UFUNCTION()
    private void OnAdvance0SpamOneCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _AdvanceCompletions += 1;
        _Advance0SpamOneResult = InResult;
    }

    UFUNCTION()
    private void OnAdvance0SpamTwoCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _AdvanceCompletions += 1;
        _Advance0SpamTwoResult = InResult;
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
    private void Check_InitialOffers(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Origin0Offers = 0;
        auto Origin1Offers = 0;
        auto Pending = 0;
        for (const auto& Member : _Queue.Get_Members())
        {
            if (Member.Get_State() == ECk_Queue_MemberState::MovingToSlot)
            {
                if (Member.Get_OriginIndex() == 0 && Member.Get_Rank() == 0)
                {
                    Origin0Offers += 1;
                    _Origin0Front = Member.Get_Member();
                    _Origin0FrontRevision = Member.Get_AssignmentRevision();
                }
                else if (Member.Get_OriginIndex() == 1 && Member.Get_Rank() == 0)
                {
                    Origin1Offers += 1;
                    _Origin1Front = Member.Get_Member();
                    _Origin1FrontRevision = Member.Get_AssignmentRevision();
                }
            }
            else if (Member.Get_State() == ECk_Queue_MemberState::PendingAdmission)
            { Pending += 1; }
        }
        auto Result = OutResult;
        Result.Set(_Queue.Get_MemberCount() == 6
            && Origin0Offers == 1 && Origin1Offers == 1 && Pending == 4
            && _Origin0FrontRevision > 0 && _Origin1FrontRevision > 0);
    }

    UFUNCTION()
    private void Step_AssertInitialOffers(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (const auto& Member : _Queue.Get_Members())
        {
            Assert_True(Member.Get_Ticket() >= 1 && Member.Get_Ticket() <= 6,
                "claim-first admission retains global monotonic ticket identities");
        }
        const auto Counts = _Queue.Get_Pressure().Get_OriginMemberCounts();
        Assert_Equals_Int(Counts[0], 2,
            "planned weighted distribution assigns two members to origin zero before later offers exist");
        Assert_Equals_Int(Counts[1], 4,
            "planned weighted distribution assigns four members to origin one before later offers exist");
        Assert_Valid(_Origin0Front, "origin zero exposes exactly one offered front");
        Assert_Valid(_Origin1Front, "origin one exposes exactly one offered front");
    }

    UFUNCTION()
    private void Step_ReportBothFrontsReached(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_ReportMovementOutcome(FCk_Request_Queue_ReportMovementOutcome(
            _Origin0Front, _Origin0FrontRevision, ECk_Queue_MovementOutcome::Reached));
        _Queue.Request_ReportMovementOutcome(FCk_Request_Queue_ReportMovementOutcome(
            _Origin1Front, _Origin1FrontRevision, ECk_Queue_MovementOutcome::Reached));
    }

    UFUNCTION()
    private void Check_SecondOffers(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin0Front;
        FCk_Queue_MemberSnapshot Origin1Front;
        const bool HasOrigin0Front = _Queue.TryGet_MemberSnapshot(_Origin0Front, Origin0Front);
        const bool HasOrigin1Front = _Queue.TryGet_MemberSnapshot(_Origin1Front, Origin1Front);
        if (HasOrigin1Front) { _Origin1FrontTarget = Origin1Front.Get_TargetWorldTransform(); }
        auto Origin0SecondOffers = 0;
        auto Origin1SecondOffers = 0;
        auto Pending = 0;
        for (const auto& Member : _Queue.Get_Members())
        {
            if (Member.Get_State() == ECk_Queue_MemberState::MovingToSlot && Member.Get_Rank() == 1)
            {
                if (Member.Get_OriginIndex() == 0)
                {
                    Origin0SecondOffers += 1;
                    _Origin0Next = Member.Get_Member();
                }
                else if (Member.Get_OriginIndex() == 1)
                {
                    Origin1SecondOffers += 1;
                    _Origin1Next = Member.Get_Member();
                }
            }
            else if (Member.Get_State() == ECk_Queue_MemberState::PendingAdmission)
            { Pending += 1; }
        }
        auto Result = OutResult;
        Result.Set(HasOrigin0Front && HasOrigin1Front
            && Origin0Front.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin1Front.Get_State() == ECk_Queue_MemberState::AtFront
            && _FirstClaimEvents == 2
            && Origin0SecondOffers == 1 && Origin1SecondOffers == 1 && Pending == 2);
    }

    UFUNCTION()
    private void Step_AssertSecondOffers(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Valid(_Origin0Next, "origin zero reaches its next rank only after its first claim");
        Assert_Valid(_Origin1Next, "origin one reaches its next rank only after its first claim");
        Assert_Equals_Int(_FirstClaimEvents, 2, "one reached claim is observed independently for each origin");
        Assert_Equals_Int(_SecondOfferEvents, 2,
            "each reached claim emits exactly one newly offered MovingToSlot reservation");
    }

    UFUNCTION()
    private void Step_RequestOrigin0Advance(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(0),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvance0Completed"));
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(0),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvance0SpamOneCompleted"));
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(0),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvance0SpamTwoCompleted"));
    }

    UFUNCTION()
    private void Check_Origin0AdvancePreservesOrigin1(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin1Front;
        const bool HasOrigin1Front = _Queue.TryGet_MemberSnapshot(_Origin1Front, Origin1Front);
        auto Origin0Progressed = false;
        for (const auto& Member : _Queue.Get_Members())
        {
            if (Member.Get_OriginIndex() == 0 && Member.Get_Rank() == 0
                && Member.Get_State() == ECk_Queue_MemberState::MovingToSlot)
            { Origin0Progressed = true; }
        }
        auto Result = OutResult;
        Result.Set(_AdvanceCompletions == 3 && _Advance0Result == ECk_Request_OperationResult::Succeeded
            && _Advance0SpamOneResult == ECk_Request_OperationResult::Failed
            && _Advance0SpamTwoResult == ECk_Request_OperationResult::Failed
            && _ServingAdvancedEvents == 1 && _Origin0ServingAdvancedEvents == 1 && _Queue.Get_MemberCount() == 5
            && _Queue.Get_IsMember(_Origin0Front) == false
            && HasOrigin1Front && Origin1Front.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin1Front.Get_AssignmentRevision() == _Origin1FrontRevision
            && Origin1Front.Get_TargetWorldTransform().Equals(_Origin1FrontTarget)
            && _FirstClaimEvents == 2 && Origin0Progressed);
    }

    UFUNCTION()
    private void Step_RequestOrigin1Advance(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(1),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvance1Completed"));
    }

    UFUNCTION()
    private void Check_IndependentAdvancesSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_AdvanceCompletions == 4 && _ServingAdvancedEvents == 2
            && _Advance0Result == ECk_Request_OperationResult::Succeeded
            && _Advance1Result == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_MemberCount() == 4);
    }

    UFUNCTION()
    private void Step_AssertIndependentAdvances(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Counts = _Queue.Get_Pressure().Get_OriginMemberCounts();
        Assert_True(_Advance0Result == ECk_Request_OperationResult::Succeeded
            && _Advance1Result == ECk_Request_OperationResult::Succeeded,
            "both independently claimed fronts advance with successful completions");
        Assert_True(_Advance0SpamOneResult == ECk_Request_OperationResult::Failed
            && _Advance0SpamTwoResult == ECk_Request_OperationResult::Failed,
            "same-origin advance spam after the first service is rejected without a second removal");
        Assert_Equals_Int(_Origin0ServingAdvancedEvents, 1,
            "same-origin advance spam emits exactly one origin-zero Serving event");
        Assert_Equals_Int(_ServingAdvancedEvents, 2,
            "each origin emits one Serving Advanced event in the shared request drain");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 4,
            "one served front is removed from each origin without serializing the other");
        Assert_Equals_Int(Counts[0], 2,
            "post-advance weighted reflow retains two survivors at origin zero");
        Assert_Equals_Int(Counts[1], 2,
            "post-advance weighted reflow retains two survivors at origin one");
        for (const auto& Member : _Queue.Get_Members())
        {
            Assert_True(Member.Get_Ticket() >= 1 && Member.Get_Ticket() <= 6,
                "independent advance preserves every surviving global ticket identity");
        }
    }

    private FCk_Handle_Queue CreateWeightedQueue(FCk_Handle& InOwner)
    {
        auto Origins = TArray<FCk_Queue_Origin>();
        auto Origin0 = FCk_Queue_Origin(FTransform(FVector(200.0f, 0.0f, 0.0f)));
        Origin0.Set_Weight(1);
        auto Origin1 = FCk_Queue_Origin(FTransform(FVector(200.0f, 480.0f, 0.0f)));
        Origin1.Set_Weight(2);
        Origins.Add(Origin0);
        Origins.Add(Origin1);
        auto Params = FCk_Fragment_Queue_ParamsData(Origins);
        Params.Set_HardLimit(6);
        Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ClaimFirstAvailableOnReach);
        return utils_queue::Add(InOwner, Params);
    }
}
