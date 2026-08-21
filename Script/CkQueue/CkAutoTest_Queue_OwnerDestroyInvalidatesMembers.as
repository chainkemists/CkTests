// Language=angelscript

class UCk_AutoTest_Queue_OwnerDestroyInvalidatesMembers : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle       _MemberA;
    private FCk_Handle       _MemberB;
    private int32            _OwnerDestroyedMemberEvents = 0;
    private int32            _InvalidationEvents = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Queue = CreateQueue(_Owner);
        _Queue.BindTo_OnQueueMemberStateChanged(
            FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberStateChanged"));
        _Queue.BindTo_OnQueueInvalidated(
            FCk_Delegate_Queue_OnInvalidated(this, n"OnQueueInvalidated"));

        _MemberA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _MemberB = utils_entity_lifetime::Request_CreateEntity(InHandle);

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join two members to the separate queue owner", n"Step_RequestJoins");
        Add_Step_WaitUntil("both members are admitted", n"Check_BothMembersPresent");
        Add_Step("destroy the queue owner", n"Step_DestroyOwner");
        Add_Step_WaitUntil("owner teardown invalidates the queue and both members", n"Check_OwnerTeardownSettled");
        Add_Step("assert owner teardown events are exactly once", n"Step_AssertOwnerTeardown");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnMemberStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue != _Queue || InEvent.Get_Reason() != ECk_Queue_EventReason::OwnerDestroyed)
        { return; }
        const auto Member = InEvent.Get_Member().Get_Member();
        if (Member == _MemberA || Member == _MemberB)
        { _OwnerDestroyedMemberEvents += 1; }
    }

    UFUNCTION()
    private void OnQueueInvalidated(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        if (InQueue == _Queue && InState.Get_Reason() == ECk_Queue_EventReason::OwnerDestroyed)
        { _InvalidationEvents += 1; }
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
    }

    UFUNCTION()
    private void Check_BothMembersPresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Queue.Get_MemberCount() == 2);
    }

    UFUNCTION()
    private void Step_DestroyOwner(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_Owner);
    }

    UFUNCTION()
    private void Check_OwnerTeardownSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Owner) && ck::Is_NOT_Valid(_Queue)
            && _OwnerDestroyedMemberEvents == 2 && _InvalidationEvents == 1);
    }

    UFUNCTION()
    private void Step_AssertOwnerTeardown(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_OwnerDestroyedMemberEvents, 2,
            "each queued member receives one OwnerDestroyed terminal event");
        Assert_Equals_Int(_InvalidationEvents, 1,
            "queue invalidation fires once for owner teardown");
        Assert_True(ck::Is_NOT_Valid(_Queue), "queue handle is invalid after its separate owner is destroyed");
    }

    private FCk_Handle_Queue CreateQueue(FCk_Handle& InOwner)
    {
        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform::Identity));
        return utils_queue::Add(InOwner, FCk_Fragment_Queue_ParamsData(Origins));
    }
}
