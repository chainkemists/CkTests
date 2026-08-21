// Language=angelscript

class UCk_AutoTest_Queue_DestroyedHeadReconciles : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle       _Owner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle       _Head;
    private FCk_Handle       _Survivor;
    private int32            _MemberDestroyedEvents = 0;

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

        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join a head and survivor", n"Step_RequestJoins");
        Add_Step_WaitUntil("both members are admitted", n"Check_BothMembersPresent");
        Add_Step("destroy the head without requesting leave", n"Step_DestroyHead");
        Add_Step_WaitUntil("reconcile removes the destroyed head", n"Check_HeadReconciled");
        Add_Step("assert one destruction event and survivor promotion", n"Step_AssertReconciled");
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

    private FCk_Handle_Queue CreateQueue(FCk_Handle& InOwner)
    {
        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform::Identity));
        return utils_queue::Add(InOwner, FCk_Fragment_Queue_ParamsData(Origins));
    }
}
