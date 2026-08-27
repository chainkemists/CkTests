// Language=angelscript

class UCk_AutoTest_QueueCoordinator_SingleQueueSelectionAndAdmission : UCk_AutoTest_Base
{
    private FCk_Handle _CoordinatorOwner;
    private FCk_Handle_QueueCoordinator _Coordinator;
    private FCk_Handle _QueueOwner;
    private FCk_Handle_Queue _Queue;
    private FCk_Handle _Member;
    private FCk_QueueCoordinator_SelectResult _Selection;
    private int32 _RegisterCompletions = 0;
    private int32 _SelectCompletions = 0;
    private int32 _JoinCompletions = 0;
    private ECk_Request_OperationResult _SelectCompletion = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _JoinCompletion = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _CoordinatorOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto CoordinatorParams = FCk_Fragment_QueueCoordinator_ParamsData();
        CoordinatorParams.Set_RequiredQueueCategory(
            utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        _Coordinator = utils_queue_coordinator::Add(_CoordinatorOwner, CoordinatorParams);
        _QueueOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_QueueOwner, FTransform(FVector(200.0f, 0.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_Category(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        _Queue = utils_queue::Add(_QueueOwner, Params);
        _Member = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Member, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        Add_Step_WaitUntil("Queue and coordinator exist", n"Check_Ready");
        Add_Step("register the explicit Gym Queue", n"Step_Register");
        Add_Step_WaitUntil("registration completes", n"Check_Registered");
        Add_Step("select the only eligible Queue", n"Step_Select");
        Add_Step_WaitUntil("selection result and admission complete", n"Check_SelectedAndJoined");
        Add_Step("assert single Queue selection contract", n"Step_Assert");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Coordinator)
            && ck::IsValid(_Queue)
            && _Queue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_Register(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Coordinator.Request_RegisterQueue(
            FCk_Request_QueueCoordinator_RegisterQueue(_Queue),
            FCk_Delegate_Request_OnCompleted(this, n"OnRegister"));
    }

    UFUNCTION()
    private void OnRegister(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        if (InOwner == FCk_Handle(_Coordinator)
            && InResult == ECk_Request_OperationResult::Succeeded)
        {
            _RegisterCompletions += 1;
        }
    }

    UFUNCTION()
    private void Check_Registered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_RegisterCompletions == 1 && _Coordinator.Get_Services().Num() == 1);
    }

    UFUNCTION()
    private void Step_Select(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Coordinator.Request_SelectQueue(
            FCk_Request_QueueCoordinator_SelectQueue(_Member, FVector::ZeroVector),
            FCk_Delegate_QueueCoordinator_OnSelected(this, n"OnSelected"),
            FCk_Delegate_Request_OnCompleted(this, n"OnSelect"));
    }

    UFUNCTION()
    private void OnSelected(FCk_QueueCoordinator_SelectResult InResult)
    {
        _Selection = InResult;
        if (InResult.Get_Outcome() == ECk_QueueCoordinator_SelectOutcome::Selected)
        {
            auto SelectedQueue = InResult.Get_SelectedQueue();
            SelectedQueue.Request_Join(
                FCk_Request_Queue_Join(_Member),
                FCk_Delegate_Request_OnCompleted(this, n"OnJoin"));
        }
    }

    UFUNCTION()
    private void OnSelect(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        if (InOwner == FCk_Handle(_Coordinator))
        {
            _SelectCompletions += 1;
            _SelectCompletion = InResult;
        }
    }

    UFUNCTION()
    private void OnJoin(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        if (InOwner == FCk_Handle(_Queue))
        {
            _JoinCompletions += 1;
            _JoinCompletion = InResult;
        }
    }

    UFUNCTION()
    private void Check_SelectedAndJoined(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_SelectCompletions == 1 && _JoinCompletions == 1 && _Queue.Get_IsMember(_Member));
    }

    UFUNCTION()
    private void Step_Assert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Selection.Get_Outcome() == ECk_QueueCoordinator_SelectOutcome::Selected, "single registered Gym Queue is selected");
        Assert_True(_Selection.Get_SelectedQueue() == _Queue && _Selection.Get_EligibleFallbackQueues().Num() == 1, "selection exposes its single Queue fallback");
        Assert_True(_SelectCompletion == ECk_Request_OperationResult::Succeeded && _JoinCompletion == ECk_Request_OperationResult::Succeeded, "selection and immediate Queue admission complete successfully");
    }
}
