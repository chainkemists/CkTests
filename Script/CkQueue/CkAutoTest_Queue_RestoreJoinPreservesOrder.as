// Language=angelscript

class UCk_AutoTest_Queue_RestoreJoinPreservesOrder : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle_Queue _Queue;
    private FCk_Handle_CrowdAgent _AgentA;
    private FCk_Handle_CrowdAgent _AgentB;
    private FCk_Handle_CrowdAgent _AgentC;
    private FCk_Handle_CrowdAgent _AgentD;
    private int32 _RestoreCompletions = 0;
    private int32 _LeaveCompletions = 0;
    private ECk_Request_OperationResult _RestoreAResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _RestoreBResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _IdempotentResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _DuplicateResult = ECk_Request_OperationResult::Succeeded;
    private ECk_Request_OperationResult _ConflictResult = ECk_Request_OperationResult::Succeeded;
    private ECk_Request_OperationResult _NormalJoinResult = ECk_Request_OperationResult::Failed;
    private int32 _InvalidBatchCompletions = 0;
    private int32 _RevisionBeforeInvalidBatch = 0;
    private int32 _MoverRefreshCompletions = 0;
    private int32 _RevisionBeforeMoverRefresh = 0;
    private ECk_Request_OperationResult _ChangedMoverResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _AdapterMoverRestoreResult = ECk_Request_OperationResult::Failed;
    private int32 _PostLeaveRestoreCompletions = 0;
    private ECk_Request_OperationResult _PostLeaveRestoreResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Context = InHandle;
        utils_transform::Add(Context, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(Context);

        Add_Step_WaitUntil("restore test location is navigable", n"Check_NavigationReady");
        Add_Step("compose queue and four CrowdAgents", n"Step_Compose");
        Add_Step_WaitUntil("restore queue is ready", n"Check_QueueReady");
        Add_Step("restore tickets out of request order", n"Step_RequestOutOfOrderRestore");
        Add_Step_WaitUntil("restored members are admitted", n"Check_RestoredMembers");
        Add_Step("assert restored FIFO order and current movers", n"Step_AssertRestoredOrder");
        Add_Step("request idempotent, duplicate, and conflicting restores", n"Step_RequestInvalidBatch");
        Add_Step_WaitUntil("restore validation completions settle", n"Check_InvalidBatchSettled");
        Add_Step("assert invalid restore requests mutate no membership", n"Step_AssertInvalidBatch");
        Add_Step("refresh a restored member with a rebuilt mover", n"Step_RequestChangedMover");
        Add_Step_WaitUntil("rebuilt mover refresh settles", n"Check_ChangedMoverSettled");
        Add_Step("restore adapter ownership of the mover", n"Step_RequestAdapterMoverRestore");
        Add_Step_WaitUntil("adapter mover restore settles", n"Check_AdapterMoverRestoreSettled");
        Add_Step("join normally after restored high-water ticket", n"Step_RequestNormalJoin");
        Add_Step_WaitUntil("normal join receives the next ticket", n"Check_NormalJoinSettled");
        Add_Step("leave every admitted adapter member", n"Step_RequestLeaves");
        Add_Step_WaitUntil("adapter leaves settle", n"Check_LeavesSettled");
        Add_Step("restore the same adapter after its completed leave", n"Step_RequestPostLeaveRestore");
        Add_Step_WaitUntil("post-leave restore settles", n"Check_PostLeaveRestoreSettled");
        Add_Step("leave the post-leave restore episode", n"Step_RequestFinalLeave");
        Add_Step_WaitUntil("final leave settles", n"Check_FinalLeaveSettled");
        Add_Step("assert restore adapters tear down cleanly", n"Step_AssertFinal");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_NavigationReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FVector Projected;
        auto Context = InHandle;
        auto Result = OutResult;
        Result.Set(utils_nav::Try_ProjectOntoNavmesh(
            Context, FVector::ZeroVector, 100.0f, Projected, 300.0f));
    }

    UFUNCTION()
    private void Step_Compose(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform(FVector(300.0f, 0.0f, 0.0f)), ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_SoftLimit(3);
        Params.Set_HardLimit(4);
        _Queue = utils_queue::Add(Owner, Params);

        _AgentA = CreateAgent(InHandle, FVector(-300.0f, -150.0f, 0.0f));
        _AgentB = CreateAgent(InHandle, FVector(-300.0f, -50.0f, 0.0f));
        _AgentC = CreateAgent(InHandle, FVector(-300.0f, 50.0f, 0.0f));
        _AgentD = CreateAgent(InHandle, FVector(-300.0f, 150.0f, 0.0f));
    }

    private FCk_Handle_CrowdAgent CreateAgent(FCk_Handle InOwner, FVector InLocation)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto Transform = utils_transform::Add(
            Entity, FTransform(FRotator::ZeroRotator, InLocation, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(
            Transform, FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f));
        utils_velocity::Add(Entity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Entity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Entity);
        return Agent;
    }

    UFUNCTION()
    private void Check_QueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue) && _Queue.Get_State() == ECk_Queue_State::Ready);
    }

    UFUNCTION()
    private void Step_RequestOutOfOrderRestore(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AgentB.Request_RestoreJoinQueue(
            _Queue, 20, FCk_Delegate_Request_OnCompleted(this, n"OnRestoreBCompleted"));
        _AgentA.Request_RestoreJoinQueue(
            _Queue, 10, FCk_Delegate_Request_OnCompleted(this, n"OnRestoreACompleted"));
    }

    UFUNCTION()
    private void OnRestoreACompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    { _RestoreAResult = InResult; _RestoreCompletions += 1; }

    UFUNCTION()
    private void OnRestoreBCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    { _RestoreBResult = InResult; _RestoreCompletions += 1; }

    UFUNCTION()
    private void Check_RestoredMembers(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_RestoreCompletions == 2
            && _RestoreAResult == ECk_Request_OperationResult::Succeeded
            && _RestoreBResult == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_MemberCount() == 2);
    }

    UFUNCTION()
    private void Step_AssertRestoredOrder(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Members = _Queue.Get_Members();
        Assert_Equals_Int(Members.Num(), 2, "two restore joins publish exactly two members");
        Assert_True(Members[0].Get_Member() == FCk_Handle(_AgentA)
            && Members[0].Get_Mover() == FCk_Handle(_AgentA)
            && Members[0].Get_Ticket() == 10,
            "ticket 10 is first with its freshly rebuilt CrowdAgent mover");
        Assert_True(Members[1].Get_Member() == FCk_Handle(_AgentB)
            && Members[1].Get_Mover() == FCk_Handle(_AgentB)
            && Members[1].Get_Ticket() == 20,
            "ticket 20 is second even though its request was enqueued first");
    }

    UFUNCTION()
    private void Step_RequestInvalidBatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RevisionBeforeInvalidBatch = _Queue.Get_Revision();

        auto Idempotent = FCk_Request_Queue_RestoreJoin(FCk_Handle(_AgentA), 10);
        Idempotent.Set_Mover(FCk_Handle(_AgentA));
        _Queue.Request_RestoreJoin(Idempotent,
            FCk_Delegate_Request_OnCompleted(this, n"OnIdempotentCompleted"));

        auto Duplicate = FCk_Request_Queue_RestoreJoin(FCk_Handle(_AgentC), 20);
        Duplicate.Set_Mover(FCk_Handle(_AgentC));
        _Queue.Request_RestoreJoin(Duplicate,
            FCk_Delegate_Request_OnCompleted(this, n"OnDuplicateCompleted"));

        auto Conflict = FCk_Request_Queue_RestoreJoin(FCk_Handle(_AgentA), 11);
        Conflict.Set_Mover(FCk_Handle(_AgentA));
        _Queue.Request_RestoreJoin(Conflict,
            FCk_Delegate_Request_OnCompleted(this, n"OnConflictCompleted"));
    }

    UFUNCTION()
    private void OnIdempotentCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    { _IdempotentResult = InResult; _InvalidBatchCompletions += 1; }

    UFUNCTION()
    private void OnDuplicateCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    { _DuplicateResult = InResult; _InvalidBatchCompletions += 1; }

    UFUNCTION()
    private void OnConflictCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    { _ConflictResult = InResult; _InvalidBatchCompletions += 1; }

    UFUNCTION()
    private void Check_InvalidBatchSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_InvalidBatchCompletions == 3);
    }

    UFUNCTION()
    private void Step_AssertInvalidBatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Members = _Queue.Get_Members();
        Assert_True(_IdempotentResult == ECk_Request_OperationResult::Succeeded,
            "exact restore replay is idempotent");
        Assert_True(_DuplicateResult == ECk_Request_OperationResult::Failed,
            "another member cannot claim an existing restore ticket");
        Assert_True(_ConflictResult == ECk_Request_OperationResult::Failed,
            "an existing member cannot change its restore ticket");
        Assert_Equals_Int(Members.Num(), 2,
            "invalid restore requests publish no partial membership");
        Assert_True(Members[0].Get_Ticket() == 10 && Members[1].Get_Ticket() == 20,
            "invalid restore requests preserve exact FIFO order");
        Assert_Equals_Int(_Queue.Get_Revision(), _RevisionBeforeInvalidBatch,
            "idempotent and invalid restore requests do not mutate queue revision");
    }

    UFUNCTION()
    private void Step_RequestChangedMover(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RevisionBeforeMoverRefresh = _Queue.Get_Revision();
        auto Refresh = FCk_Request_Queue_RestoreJoin(FCk_Handle(_AgentA), 10);
        Refresh.Set_Mover(FCk_Handle(_AgentC));
        _Queue.Request_RestoreJoin(Refresh,
            FCk_Delegate_Request_OnCompleted(this, n"OnChangedMoverCompleted"));
    }

    UFUNCTION()
    private void OnChangedMoverCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    { _ChangedMoverResult = InResult; _MoverRefreshCompletions += 1; }

    UFUNCTION()
    private void Check_ChangedMoverSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Member;
        const bool HasA = _Queue.TryGet_MemberSnapshot(FCk_Handle(_AgentA), Member);
        auto Result = OutResult;
        Result.Set(_MoverRefreshCompletions == 1
            && _ChangedMoverResult == ECk_Request_OperationResult::Succeeded
            && HasA && Member.Get_Ticket() == 10
            && Member.Get_Mover() == FCk_Handle(_AgentC)
            && _Queue.Get_Revision() > _RevisionBeforeMoverRefresh);
    }

    UFUNCTION()
    private void Step_RequestAdapterMoverRestore(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AgentA.Request_RestoreJoinQueue(
            _Queue, 10,
            FCk_Delegate_Request_OnCompleted(this, n"OnAdapterMoverRestoreCompleted"));
    }

    UFUNCTION()
    private void OnAdapterMoverRestoreCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    { _AdapterMoverRestoreResult = InResult; _MoverRefreshCompletions += 1; }

    UFUNCTION()
    private void Check_AdapterMoverRestoreSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Member;
        const bool HasA = _Queue.TryGet_MemberSnapshot(FCk_Handle(_AgentA), Member);
        auto Result = OutResult;
        Result.Set(_MoverRefreshCompletions == 2
            && _AdapterMoverRestoreResult == ECk_Request_OperationResult::Succeeded
            && HasA && Member.Get_Ticket() == 10
            && Member.Get_Mover() == FCk_Handle(_AgentA)
            && _Queue.Get_Revision() > _RevisionBeforeMoverRefresh + 1);
    }

    UFUNCTION()
    private void Step_RequestNormalJoin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AgentD.Request_JoinQueue(
            _Queue, FCk_Delegate_Request_OnCompleted(this, n"OnNormalJoinCompleted"));
    }

    UFUNCTION()
    private void OnNormalJoinCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    { _NormalJoinResult = InResult; }

    UFUNCTION()
    private void Check_NormalJoinSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Member;
        const bool HasD = _Queue.TryGet_MemberSnapshot(FCk_Handle(_AgentD), Member);
        auto Result = OutResult;
        Result.Set(_NormalJoinResult == ECk_Request_OperationResult::Succeeded
            && HasD && Member.Get_Ticket() == 21 && _Queue.Get_MemberCount() == 3);
    }

    UFUNCTION()
    private void Step_RequestLeaves(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AgentA.Request_LeaveQueue(FCk_Delegate_Request_OnCompleted(this, n"OnLeaveCompleted"));
        _AgentB.Request_LeaveQueue(FCk_Delegate_Request_OnCompleted(this, n"OnLeaveCompleted"));
        _AgentD.Request_LeaveQueue(FCk_Delegate_Request_OnCompleted(this, n"OnLeaveCompleted"));
    }

    UFUNCTION()
    private void OnLeaveCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        if (InResult == ECk_Request_OperationResult::Succeeded)
        { _LeaveCompletions += 1; }
    }

    UFUNCTION()
    private void Check_LeavesSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_LeaveCompletions == 3 && _Queue.Get_MemberCount() == 0);
    }

    UFUNCTION()
    private void Step_RequestPostLeaveRestore(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AgentA.Request_RestoreJoinQueue(
            _Queue, 10,
            FCk_Delegate_Request_OnCompleted(this, n"OnPostLeaveRestoreCompleted"));
    }

    UFUNCTION()
    private void OnPostLeaveRestoreCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    { _PostLeaveRestoreResult = InResult; _PostLeaveRestoreCompletions += 1; }

    UFUNCTION()
    private void Check_PostLeaveRestoreSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Member;
        const bool HasA = _Queue.TryGet_MemberSnapshot(FCk_Handle(_AgentA), Member);
        auto Result = OutResult;
        Result.Set(_PostLeaveRestoreCompletions == 1
            && _PostLeaveRestoreResult == ECk_Request_OperationResult::Succeeded
            && HasA && Member.Get_Ticket() == 10
            && Member.Get_Mover() == FCk_Handle(_AgentA));
    }

    UFUNCTION()
    private void Step_RequestFinalLeave(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AgentA.Request_LeaveQueue(
            FCk_Delegate_Request_OnCompleted(this, n"OnLeaveCompleted"));
    }

    UFUNCTION()
    private void Check_FinalLeaveSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_LeaveCompletions == 4 && _Queue.Get_MemberCount() == 0);
    }

    UFUNCTION()
    private void Step_AssertFinal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_LeaveCompletions, 4,
            "every restored or normally joined Crowd adapter leaves exactly once");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 0,
            "restore lifecycle leaves no queue membership behind");
    }
}

class ACk_AutoTest_Queue_RestoreJoinPreservesOrder_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Queue_RestoreJoinPreservesOrder;
    default _TimeoutSeconds = 30.0f;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("restore ticket [20] is already owned by another member");
        Out.Add("conflicts with existing ticket [10]");
        return Out;
    }
}
