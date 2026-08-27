// Language=angelscript

class UCk_AutoTest_QueueCoordinator_BurstDistributesAcrossTwoQueues : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;
    private FCk_Handle_QueueCoordinator _Coordinator;
    private TArray<FCk_Handle> _QueueOwners;
    private TArray<FCk_Handle_Queue> _Queues;
    private TArray<FCk_Handle> _Members;
    private TArray<FCk_QueueCoordinator_SelectResult> _Results;
    private int32 _Registers = 0;
    private int32 _Selects = 0;
    private int32 _Joins = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto CoordinatorParams = FCk_Fragment_QueueCoordinator_ParamsData();
        CoordinatorParams.Set_RequiredQueueCategory(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        _Coordinator = utils_queue_coordinator::Add(_Owner, CoordinatorParams);
        for (int32 Index = 0; Index < 2; ++Index)
        {
            auto QueueOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
            utils_transform::Add(QueueOwner, FTransform(FVector(200.0f, float(Index) * 300.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
            _QueueOwners.Add(QueueOwner);
            auto Params = FCk_Fragment_Queue_ParamsData();
            Params.Set_Category(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
            _Queues.Add(utils_queue::Add(QueueOwner, Params));
        }
        for (int32 Index = 0; Index < 6; ++Index)
        {
            auto Member = utils_entity_lifetime::Request_CreateEntity(InHandle);
            utils_transform::Add(Member, FTransform(FVector(-200.0f, 0.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
            _Members.Add(Member);
        }
        Add_Step_WaitUntil("both Queues are ready", n"Check_Ready");
        Add_Step("register both explicit Queues", n"Step_Register");
        Add_Step_WaitUntil("both registrations complete", n"Check_Registered");
        Add_Step("burst select six members in one frame", n"Step_SelectBurst");
        Add_Step_WaitUntil("all selections immediately admit", n"Check_Admitted");
        Add_Step("assert projected balanced burst", n"Step_Assert");
        Run_Steps(InHandle);
    }
    UFUNCTION()
    private void Check_Ready(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Queues.Num() == 2
            && _Queues[0].Get_State() == ECk_Queue_State::Ready
            && _Queues[1].Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_Register(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Queue : _Queues)
        {
            _Coordinator.Request_RegisterQueue(
                FCk_Request_QueueCoordinator_RegisterQueue(Queue),
                FCk_Delegate_Request_OnCompleted(this, n"OnRegister"));
        }
    }

    UFUNCTION()
    private void OnRegister(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        if (InOwner == FCk_Handle(_Coordinator)
            && InResult == ECk_Request_OperationResult::Succeeded)
        {
            _Registers += 1;
        }
    }

    UFUNCTION()
    private void Check_Registered(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Registers == 2);
    }

    UFUNCTION()
    private void Step_SelectBurst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Member : _Members)
        {
            _Coordinator.Request_SelectQueue(
                FCk_Request_QueueCoordinator_SelectQueue(Member, FVector(-200.0f, 0.0f, 0.0f)),
                FCk_Delegate_QueueCoordinator_OnSelected(this, n"OnSelected"),
                FCk_Delegate_Request_OnCompleted(this, n"OnSelect"));
        }
    }

    UFUNCTION()
    private void OnSelected(FCk_QueueCoordinator_SelectResult InResult)
    {
        _Results.Add(InResult);
        if (InResult.Get_Outcome() == ECk_QueueCoordinator_SelectOutcome::Selected)
        {
            auto SelectedQueue = InResult.Get_SelectedQueue();
            SelectedQueue.Request_Join(
                FCk_Request_Queue_Join(InResult.Get_Member()),
                FCk_Delegate_Request_OnCompleted(this, n"OnJoin"));
        }
    }

    UFUNCTION()
    private void OnSelect(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        if (InOwner == FCk_Handle(_Coordinator)
            && InResult == ECk_Request_OperationResult::Succeeded)
        {
            _Selects += 1;
        }
    }

    UFUNCTION()
    private void OnJoin(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        if (InResult == ECk_Request_OperationResult::Succeeded)
        {
            _Joins += 1;
        }
    }

    UFUNCTION()
    private void Check_Admitted(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Selects == 6
            && _Joins == 6
            && _Queues[0].Get_MemberCount() == 3
            && _Queues[1].Get_MemberCount() == 3);
    }

    UFUNCTION()
    private void Step_Assert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Results.Num(), 6, "every burst request publishes one result");
        for (auto Result : _Results)
        {
            Assert_True(Result.Get_Outcome() == ECk_QueueCoordinator_SelectOutcome::Selected
                && Result.Get_ProjectedMemberCount() >= 1,
                "each projected selection succeeds before its immediate Queue join");
        }
    }
}
