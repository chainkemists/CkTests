// Language=angelscript

class UCk_AutoTest_Queue_OriginCapacityRejectsAtomically : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle       _MemberA;
    private FCk_Handle       _MemberB;
    private FCk_Handle       _MemberC;
    private int32            _OriginHardLimitEvents = 0;
    private int32            _JoinCCompletions = 0;
    private int32            _ShrinkCompletions = 0;
    private ECk_Request_OperationResult _JoinCResult = ECk_Request_OperationResult::Succeeded;
    private ECk_Request_OperationResult _ShrinkResult = ECk_Request_OperationResult::Succeeded;
    private int64            _TicketA = 0;
    private int64            _TicketB = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Queue = CreateTwoOriginQueue(_Owner);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));

        _MemberA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _MemberB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _MemberC = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("fill the two one-member origins and contest a third join", n"Step_RequestJoins");
        Add_Step_WaitUntil("origin-cap rejection completes", n"Check_JoinRejected");
        Add_Step("assert origin-cap rejection is atomic", n"Step_AssertOriginCapacity");
        Add_Step("try to shrink origin capacity below live membership", n"Step_RequestInvalidShrink");
        Add_Step_WaitUntil("capacity-shrinking SetOrigins completes", n"Check_ShrinkCompleted");
        Add_Step("assert failed reconfiguration preserves live members and origins", n"Step_AssertShrinkRejected");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue == _Queue && InEvent.Get_Reason() == ECk_Queue_EventReason::OriginHardLimitReached
            && InEvent.Get_Member().Get_Member() == _MemberC)
        { _OriginHardLimitEvents += 1; }
    }

    UFUNCTION()
    private void OnJoinCCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _JoinCCompletions += 1;
        _JoinCResult = InResult;
    }

    UFUNCTION()
    private void OnShrinkCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _ShrinkCompletions += 1;
        _ShrinkResult = InResult;
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
        _Queue.Request_Join(FCk_Request_Queue_Join(_MemberA));
        _Queue.Request_Join(FCk_Request_Queue_Join(_MemberB));
        _Queue.Request_Join(FCk_Request_Queue_Join(_MemberC),
            FCk_Delegate_Request_OnCompleted(this, n"OnJoinCCompleted"));
    }

    UFUNCTION()
    private void Check_JoinRejected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot MemberA;
        FCk_Queue_MemberSnapshot MemberB;
        const bool FormationAssigned = _Queue.TryGet_MemberSnapshot(_MemberA, MemberA)
            && _Queue.TryGet_MemberSnapshot(_MemberB, MemberB)
            && MemberA.Get_AssignmentRevision() > 0
            && MemberB.Get_AssignmentRevision() > 0
            && MemberA.Get_OriginIndex() != MemberB.Get_OriginIndex();
        auto Result = OutResult;
        Result.Set(_Queue.Get_MemberCount() == 2 && _JoinCCompletions == 1
            && _OriginHardLimitEvents == 1 && FormationAssigned);
    }

    UFUNCTION()
    private void Step_AssertOriginCapacity(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Members = _Queue.Get_Members();
        Assert_Equals_Int(Members.Num(), 2, "per-origin capacity leaves the admitted pair intact");
        Assert_True(Members[0].Get_Member() == _MemberA && Members[1].Get_Member() == _MemberB,
            "origin-cap rejection does not reorder the existing FIFO admissions");
        Assert_True(Members[0].Get_OriginIndex() != Members[1].Get_OriginIndex(),
            "the two one-member origins each receive exactly one member");
        Assert_Equals_Int(_OriginHardLimitEvents, 1,
            "third join emits exactly one OriginHardLimitReached event");
        Assert_Equals_Int(_JoinCCompletions, 1, "third join completion fires exactly once");
        Assert_True(_JoinCResult == ECk_Request_OperationResult::Failed,
            "per-origin capacity rejection completes Failed");
        Assert_False(_Queue.Get_IsMember(_MemberC), "rejected third member is never admitted");
        _TicketA = Members[0].Get_Ticket();
        _TicketB = Members[1].Get_Ticket();
    }

    UFUNCTION()
    private void Step_RequestInvalidShrink(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto ShrunkOrigins = TArray<FCk_Queue_Origin>();
        auto OnlyOrigin = FCk_Queue_Origin(FTransform::Identity);
        OnlyOrigin.Set_HardLimitOverride(1);
        ShrunkOrigins.Add(OnlyOrigin);
        _Queue.Request_SetOrigins(FCk_Request_Queue_SetOrigins(ShrunkOrigins),
            FCk_Delegate_Request_OnCompleted(this, n"OnShrinkCompleted"));
    }

    UFUNCTION()
    private void Check_ShrinkCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_ShrinkCompletions == 1);
    }

    UFUNCTION()
    private void Step_AssertShrinkRejected(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Members = _Queue.Get_Members();
        Assert_True(_ShrinkResult == ECk_Request_OperationResult::Failed,
            "SetOrigins cannot shrink aggregate origin capacity below current membership");
        Assert_Equals_Int(_Queue.Get_Origins().Num(), 2,
            "failed SetOrigins preserves the previous two-origin configuration");
        Assert_Equals_Int(Members.Num(), 2, "failed SetOrigins preserves all live members");
        Assert_True(Members[0].Get_Ticket() == _TicketA && Members[1].Get_Ticket() == _TicketB,
            "failed SetOrigins preserves tickets without partial reflow");
    }

    private FCk_Handle_Queue CreateTwoOriginQueue(FCk_Handle& InOwner)
    {
        auto Origins = TArray<FCk_Queue_Origin>();
        auto OriginA = FCk_Queue_Origin(FTransform(FVector(200.0f, 0.0f, 0.0f)));
        OriginA.Set_HardLimitOverride(1);
        auto OriginB = FCk_Queue_Origin(FTransform(FVector(200.0f, 240.0f, 0.0f)));
        OriginB.Set_HardLimitOverride(1);
        Origins.Add(OriginA);
        Origins.Add(OriginB);
        auto Params = FCk_Fragment_Queue_ParamsData(Origins);
        Params.Set_SoftLimit(2);
        Params.Set_HardLimit(3);
        return utils_queue::Add(InOwner, Params);
    }
}
