// Language=angelscript

class UCk_AutoTest_Queue_CrowdAdapterFacesOrigin : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle            _QueueOwner;
    private FCk_Handle            _AgentEntity;
    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_Queue      _Queue;
    private FGameplayTag          _Category;
    private FVector               _Spawn;
    private const float32 ExpectedYaw = 90.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Context = InHandle;
        utils_transform::Add(Context, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(Context);

        Add_Step_WaitUntil("queue facing spawn and target are navigable", n"Check_NavigationReady");
        Add_Step("compose a queue with a rotated origin and one CrowdAgent", n"Step_ComposeQueueAndAgent");
        Add_Step_WaitUntil("queue formation becomes ready", n"Check_QueueReady");
        Add_Step("join through the Crowd queue adapter", n"Step_RequestJoin");
        Add_Step_WaitUntil("Crowd reaches the assigned queue slot and becomes idle", n"Check_ArrivedAndIdle");
        Add_Step_WaitUntil("adapter applies the assigned origin facing after arrival", n"Check_FacingApplied");
        Add_Step_WaitFrames("queue facing remains owned across later Crowd facing passes", 3);
        Add_Step("assert final queue-facing contract", n"Step_AssertFacing");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_NavigationReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FVector SpawnOnMesh;
        FVector TargetOnMesh;
        auto Context = InHandle;
        const bool SpawnIsNavigable = utils_nav::Try_ProjectOntoNavmesh(
            Context, FVector(-400.0f, 0.0f, 0.0f), 100.0f, SpawnOnMesh, 300.0f);
        const bool TargetIsNavigable = utils_nav::Try_ProjectOntoNavmesh(
            Context, FVector(-280.0f, 0.0f, 0.0f), 100.0f, TargetOnMesh, 300.0f);
        if (SpawnIsNavigable) { _Spawn = SpawnOnMesh; }
        auto Result = OutResult;
        Result.Set(SpawnIsNavigable && TargetIsNavigable);
    }

    UFUNCTION()
    private void Step_ComposeQueueAndAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _QueueOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_QueueOwner,
            FTransform(FRotator::ZeroRotator, _Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform(
            FRotator(0.0f, ExpectedYaw, 0.0f), FVector(120.0f, 0.0f, 0.0f), FVector::OneVector)));
        auto QueueParams = FCk_Fragment_Queue_ParamsData(Origins);
        _Category = utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.AutoTestFacing");
        QueueParams.Set_Category(_Category);
        QueueParams.Set_SlotSpacingUu(120.0f);
        _Queue = utils_queue::Add(_QueueOwner, QueueParams);

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(FRotator::ZeroRotator, _Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        AgentParams.Set_MaxSpeed(600.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, AgentParams);
        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);
    }

    UFUNCTION()
    private void Check_QueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        bool DebugSnapshotCarriesCategory = false;
        for (const auto& Snapshot : utils_queue::Get_DebugSnapshots(InHandle))
        {
            if (Snapshot.Get_Category() == _Category)
            { DebugSnapshotCarriesCategory = true; break; }
        }
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue)
            && _Queue.Get_State() == ECk_Queue_State::Ready
            && _Queue.Get_Category() == _Category
            && DebugSnapshotCarriesCategory);
    }

    UFUNCTION()
    private void Step_RequestJoin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Agent.Request_JoinQueue(_Queue);
    }

    UFUNCTION()
    private void Check_ArrivedAndIdle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agent), Snapshot);
        auto Result = OutResult;
        Result.Set(HasSnapshot
            && Snapshot.Get_State() == ECk_Queue_MemberState::AtFront
            && _Agent.Get_MovementState() == ECk_CrowdAgent_MovementState::Idle);
    }

    UFUNCTION()
    private void Check_FacingApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto Rotation = utils_transform::Get_EntityCurrentRotation(_Agent.As_Transform());
        auto Result = OutResult;
        Result.Set(Math::Abs(Math::FindDeltaAngleDegrees(Rotation.Yaw, ExpectedYaw)) < 1.0f);
    }

    UFUNCTION()
    private void Step_AssertFacing(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Rotation = utils_transform::Get_EntityCurrentRotation(_Agent.As_Transform());
        Assert_True(Math::Abs(Math::FindDeltaAngleDegrees(Rotation.Yaw, ExpectedYaw)) < 1.0f,
            "Crowd queue adapter applies the assigned queue-origin yaw only after its movement episode reaches idle");
    }
}
