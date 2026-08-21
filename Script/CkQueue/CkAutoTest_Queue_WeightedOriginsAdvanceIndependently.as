// Language=angelscript

class UCk_AutoTest_Queue_WeightedOriginsAdvanceIndependently : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private TArray<FCk_Handle> _Members;
    private FCk_Handle       _Origin0Front;
    private FCk_Handle       _Origin1Front;
    private int32            _SlotReachedEvents = 0;
    private int32            _ServingAdvancedEvents = 0;
    private int32            _AdvanceCompletions = 0;
    private ECk_Request_OperationResult _Advance0Result = ECk_Request_OperationResult::Failed;
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
        Add_Step_WaitUntil("weighted formation assigns all six members", n"Check_InitialFormation");
        Add_Step("assert the deterministic weighted split", n"Step_AssertWeightedSplit");
        Add_Step("report both origin fronts reached", n"Step_ReportBothFrontsReached");
        Add_Step_WaitUntil("both origin fronts reach independently", n"Check_BothFrontsReached");
        Add_Step("advance both origins", n"Step_RequestIndependentAdvances");
        Add_Step_WaitUntil("both independent advances settle", n"Check_IndependentAdvancesSettled");
        Add_Step("assert both origins progressed without global ticket churn", n"Step_AssertIndependentAdvances");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue != _Queue) { return; }
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached)
        { _SlotReachedEvents += 1; }
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::Advanced
            && InEvent.Get_Member().Get_State() == ECk_Queue_MemberState::Serving)
        { _ServingAdvancedEvents += 1; }
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
    private void Check_InitialFormation(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto Members = _Queue.Get_Members();
        auto AllAssigned = Members.Num() == 6;
        for (const auto& Member : Members)
        { AllAssigned = AllAssigned && Member.Get_AssignmentRevision() > 0; }
        auto Result = OutResult;
        Result.Set(AllAssigned);
    }

    UFUNCTION()
    private void Step_AssertWeightedSplit(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Members = _Queue.Get_Members();
        auto Origin0Count = 0;
        auto Origin1Count = 0;
        for (auto Index = 0; Index < Members.Num(); ++Index)
        {
            const auto& Member = Members[Index];
            Assert_True(Member.Get_Ticket() == Index + 1,
                "tickets are globally monotonic across weighted origins");
            if (Member.Get_OriginIndex() == 0)
            {
                Origin0Count += 1;
                if (Member.Get_Rank() == 0) { _Origin0Front = Member.Get_Member(); }
            }
            else if (Member.Get_OriginIndex() == 1)
            {
                Origin1Count += 1;
                if (Member.Get_Rank() == 0) { _Origin1Front = Member.Get_Member(); }
            }
        }
        Assert_Equals_Int(Origin0Count, 2, "weight one receives two of six tickets");
        Assert_Equals_Int(Origin1Count, 4, "weight two receives four of six tickets");
        Assert_Valid(_Origin0Front, "origin zero has a rank-zero member");
        Assert_Valid(_Origin1Front, "origin one has a rank-zero member");
    }

    UFUNCTION()
    private void Step_ReportBothFrontsReached(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin0;
        FCk_Queue_MemberSnapshot Origin1;
        Assert_True(_Queue.TryGet_MemberSnapshot(_Origin0Front, Origin0), "origin zero front snapshot exists");
        Assert_True(_Queue.TryGet_MemberSnapshot(_Origin1Front, Origin1), "origin one front snapshot exists");
        _Queue.Request_ReportMovementOutcome(FCk_Request_Queue_ReportMovementOutcome(
            _Origin0Front, Origin0.Get_AssignmentRevision(), ECk_Queue_MovementOutcome::Reached));
        _Queue.Request_ReportMovementOutcome(FCk_Request_Queue_ReportMovementOutcome(
            _Origin1Front, Origin1.Get_AssignmentRevision(), ECk_Queue_MovementOutcome::Reached));
    }

    UFUNCTION()
    private void Check_BothFrontsReached(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Origin0;
        FCk_Queue_MemberSnapshot Origin1;
        const bool HasBoth = _Queue.TryGet_MemberSnapshot(_Origin0Front, Origin0)
            && _Queue.TryGet_MemberSnapshot(_Origin1Front, Origin1);
        auto Result = OutResult;
        Result.Set(HasBoth && Origin0.Get_State() == ECk_Queue_MemberState::AtFront
            && Origin1.Get_State() == ECk_Queue_MemberState::AtFront && _SlotReachedEvents == 2);
    }

    UFUNCTION()
    private void Step_RequestIndependentAdvances(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(0),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvance0Completed"));
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(1),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvance1Completed"));
    }

    UFUNCTION()
    private void Check_IndependentAdvancesSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_AdvanceCompletions == 2 && _ServingAdvancedEvents == 2
            && _Queue.Get_MemberCount() == 4);
    }

    UFUNCTION()
    private void Step_AssertIndependentAdvances(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Pressure = _Queue.Get_Pressure();
        const auto Counts = Pressure.Get_OriginMemberCounts();
        Assert_True(_Advance0Result == ECk_Request_OperationResult::Succeeded
            && _Advance1Result == ECk_Request_OperationResult::Succeeded,
            "both rank-zero origins advance independently with successful completions");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 4, "one front is removed from each origin");
        Assert_Equals_Int(Counts[0], 2, "four survivors are deterministically rebalanced to two at origin zero");
        Assert_Equals_Int(Counts[1], 2, "four survivors are deterministically rebalanced to two at origin one");
        for (const auto& Member : _Queue.Get_Members())
        {
            Assert_True(Member.Get_Ticket() >= 1 && Member.Get_Ticket() <= 6,
                "independent advance preserves each survivor's global ticket identity");
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
        return utils_queue::Add(InOwner, Params);
    }
}
