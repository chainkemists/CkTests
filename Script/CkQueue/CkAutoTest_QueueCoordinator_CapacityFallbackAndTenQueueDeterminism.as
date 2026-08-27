// Language=angelscript

class UCk_AutoTest_QueueCoordinator_CapacityFallbackAndTenQueueDeterminism : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;
    private FCk_Handle_QueueCoordinator _Coordinator;
    private TArray<FCk_Handle_Queue> _Queues;
    private FCk_Handle _Member;
    private FCk_QueueCoordinator_SelectResult _Result;
    private int32 _Registers = 0;
    private int32 _Selects = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto CoordinatorParams = FCk_Fragment_QueueCoordinator_ParamsData();
        CoordinatorParams.Set_RequiredQueueCategory(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        _Coordinator = utils_queue_coordinator::Add(_Owner, CoordinatorParams);
        for (int32 Index = 0; Index < 10; ++Index)
        {
            auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
            utils_transform::Add(Owner, FTransform(FVector(200.0f, float(Index) * 100.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
            auto Params = FCk_Fragment_Queue_ParamsData();
            Params.Set_Category(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
            Params.Set_HardLimit(Index == 0 ? 1 : 2);
            auto Queue = utils_queue::Add(Owner, Params);
            _Queues.Add(Queue);
            if (Index == 0)
            {
                auto Full = utils_entity_lifetime::Request_CreateEntity(InHandle);
                Queue.Request_Join(FCk_Request_Queue_Join(Full));
            }
        }
        _Member = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Member, FTransform(FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        Add_Step_WaitUntil("ten Queues settle and first Queue is full", n"Check_Ready");
        Add_Step("register the ten explicit Queues in order", n"Step_Register");
        Add_Step_WaitUntil("all ten registrations complete", n"Check_Registered");
        Add_Step("select with Queue one excluded and Queue zero full", n"Step_Select");
        Add_Step_WaitUntil("capacity filtered deterministic selection completes", n"Check_Selected");
        Add_Step("assert ordered fallback contract", n"Step_Assert");
        Run_Steps(InHandle);
    }
    UFUNCTION()
    private void Check_Ready(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Ready = _Queues.Num() == 10;
        for (auto Queue : _Queues)
        {
            Ready = Ready && Queue.Get_State() == ECk_Queue_State::Ready;
        }
        auto Result = OutResult;
        Result.Set(Ready && _Queues[0].Get_MemberCount() == 1);
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
        if (InResult == ECk_Request_OperationResult::Succeeded)
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
        Result.Set(_Registers == 10 && _Coordinator.Get_Services().Num() == 10);
    }

    UFUNCTION()
    private void Step_Select(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Request = FCk_Request_QueueCoordinator_SelectQueue(_Member, FVector::ZeroVector);
        auto Excluded = TArray<FCk_Handle_Queue>();
        Excluded.Add(_Queues[1]);
        Request.Set_ExcludedQueues(Excluded);
        _Coordinator.Request_SelectQueue(
            Request,
            FCk_Delegate_QueueCoordinator_OnSelected(this, n"OnSelected"),
            FCk_Delegate_Request_OnCompleted(this, n"OnSelect"));
    }

    UFUNCTION()
    private void OnSelected(FCk_QueueCoordinator_SelectResult InResult)
    {
        _Result = InResult;
    }

    UFUNCTION()
    private void OnSelect(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        if (InResult == ECk_Request_OperationResult::Succeeded)
        {
            _Selects += 1;
        }
    }

    UFUNCTION()
    private void Check_Selected(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Selects == 1 && _Result.Get_Outcome() == ECk_QueueCoordinator_SelectOutcome::Selected);
    }

    UFUNCTION()
    private void Step_Assert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Fallbacks = _Result.Get_EligibleFallbackQueues();
        Assert_True(_Result.Get_SelectedQueue() == _Queues[2],
            "full and explicitly excluded first candidates fall back in stable registration order");
        Assert_Equals_Int(Fallbacks.Num(), 8,
            "fallback list excludes full Queue zero and excluded Queue one");
        Assert_True(Fallbacks[0] == _Queues[2] && Fallbacks[7] == _Queues[9],
            "ten Queue fallback order follows registration-order ties");
    }
}
