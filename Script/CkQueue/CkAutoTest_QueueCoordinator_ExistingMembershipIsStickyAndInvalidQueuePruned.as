// Language=angelscript

class UCk_AutoTest_QueueCoordinator_ExistingMembershipIsStickyAndInvalidQueuePruned : UCk_AutoTest_Base
{
    private FCk_Handle _Owner;
    private FCk_Handle_QueueCoordinator _Coordinator;
    private FCk_Handle _OwnerA;
    private FCk_Handle _OwnerB;
    private FCk_Handle_Queue _QueueA;
    private FCk_Handle_Queue _QueueB;
    private FCk_Handle _Member;
    private FCk_QueueCoordinator_SelectResult _First;
    private FCk_QueueCoordinator_SelectResult _Sticky;
    private FCk_QueueCoordinator_SelectResult _AfterPrune;
    private int32 _Registers = 0;
    private int32 _Selections = 0;
    private int32 _Joins = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto CoordinatorParams = FCk_Fragment_QueueCoordinator_ParamsData();
        CoordinatorParams.Set_RequiredQueueCategory(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        _Coordinator = utils_queue_coordinator::Add(_Owner, CoordinatorParams);
        _OwnerA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _OwnerB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_OwnerA, FTransform(FVector(100.0f, 0.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
        utils_transform::Add(_OwnerB, FTransform(FVector(1000.0f, 0.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_Category(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        _QueueA = utils_queue::Add(_OwnerA, Params);
        _QueueB = utils_queue::Add(_OwnerB, Params);
        _Member = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Member, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        Add_Step_WaitUntil("both Queues are ready", n"Check_Ready");
        Add_Step("register both explicit Queues", n"Step_Register");
        Add_Step_WaitUntil("registration completes", n"Check_Registered");
        Add_Step("select and admit member to Queue A", n"Step_SelectFirst");
        Add_Step_WaitUntil("first admission completes", n"Check_Joined");
        Add_Step("select again from changed position", n"Step_SelectSticky");
        Add_Step_WaitUntil("existing membership result arrives", n"Check_Sticky");
        Add_Step("destroy registered Queue B", n"Step_DestroyB");
        Add_Step_WaitUntil("coordinator prunes destroyed Queue B", n"Check_QueueBPruned");
        Add_Step("select a different member after invalid Queue prune", n"Step_SelectAfterPrune");
        Add_Step_WaitUntil("terminal prune selection completes", n"Check_AfterPrune");
        Add_Step("assert sticky and prune outcomes", n"Step_Assert");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_QueueA.Get_State() == ECk_Queue_State::Ready
            && _QueueB.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_Register(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Coordinator.Request_RegisterQueue(
            FCk_Request_QueueCoordinator_RegisterQueue(_QueueA),
            FCk_Delegate_Request_OnCompleted(this, n"OnRegister"));
        _Coordinator.Request_RegisterQueue(
            FCk_Request_QueueCoordinator_RegisterQueue(_QueueB),
            FCk_Delegate_Request_OnCompleted(this, n"OnRegister"));
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
        Result.Set(_Registers == 2);
    }

    UFUNCTION()
    private void Step_SelectFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Coordinator.Request_SelectQueue(
            FCk_Request_QueueCoordinator_SelectQueue(_Member, FVector::ZeroVector),
            FCk_Delegate_QueueCoordinator_OnSelected(this, n"OnFirst"),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompletion"));
    }

    UFUNCTION()
    private void OnFirst(FCk_QueueCoordinator_SelectResult InResult)
    {
        _First = InResult;
        if (InResult.Get_Outcome() == ECk_QueueCoordinator_SelectOutcome::Selected)
        {
            auto SelectedQueue = InResult.Get_SelectedQueue();
            SelectedQueue.Request_Join(
                FCk_Request_Queue_Join(_Member),
                FCk_Delegate_Request_OnCompleted(this, n"OnJoin"));
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
    private void OnCompletion(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        if (InResult == ECk_Request_OperationResult::Succeeded)
        {
            _Selections += 1;
        }
    }

    UFUNCTION()
    private void Check_Joined(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Selections == 1
            && _Joins == 1
            && _QueueA.Get_IsMember(_Member));
    }

    UFUNCTION()
    private void Step_SelectSticky(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Coordinator.Request_SelectQueue(
            FCk_Request_QueueCoordinator_SelectQueue(
                _Member,
                FVector(1000.0f, 0.0f, 0.0f)),
            FCk_Delegate_QueueCoordinator_OnSelected(this, n"OnSticky"),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompletion"));
    }

    UFUNCTION()
    private void OnSticky(FCk_QueueCoordinator_SelectResult InResult)
    {
        _Sticky = InResult;
    }

    UFUNCTION()
    private void Check_Sticky(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Selections == 2
            && _Sticky.Get_Outcome() == ECk_QueueCoordinator_SelectOutcome::AlreadyQueued);
    }

    UFUNCTION()
    private void Step_DestroyB(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_OwnerB);
    }

    UFUNCTION()
    private void Check_QueueBPruned(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Coordinator.Get_Services().Num() == 1);
    }

    UFUNCTION()
    private void Step_SelectAfterPrune(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Other = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(
            Other,
            FTransform(FVector(1000.0f, 0.0f, 0.0f)),
            ECk_Replication::DoesNotReplicate);
        _Coordinator.Request_SelectQueue(
            FCk_Request_QueueCoordinator_SelectQueue(
                Other,
                FVector(1000.0f, 0.0f, 0.0f)),
            FCk_Delegate_QueueCoordinator_OnSelected(this, n"OnAfterPrune"),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompletion"));
    }

    UFUNCTION()
    private void OnAfterPrune(FCk_QueueCoordinator_SelectResult InResult)
    {
        _AfterPrune = InResult;
    }

    UFUNCTION()
    private void Check_AfterPrune(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Selections == 3
            && _AfterPrune.Get_Outcome() == ECk_QueueCoordinator_SelectOutcome::Selected);
    }

    UFUNCTION()
    private void Step_Assert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_First.Get_SelectedQueue() == _QueueA,
            "initial score selects Queue A");
        Assert_True(_Sticky.Get_SelectedQueue() == _QueueA
            && _QueueA.Get_IsMember(_Member),
            "existing admitted membership stays sticky after position changes");
        Assert_True(_AfterPrune.Get_SelectedQueue() == _QueueA
            && _Coordinator.Get_Services().Num() == 1,
            "destroyed registered Queue is pruned and never selected");
    }
}
