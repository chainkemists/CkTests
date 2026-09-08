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
    private const float32 ExpectedSlotSpacingUu = 180.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Context = InHandle;
        utils_transform::Add(Context, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        Add_Step_WaitUntil("queue facing spawn and target are navigable", n"Check_NavigationReady");
        Add_Step("compose a queue with a rotated owner target and one CrowdAgent", n"Step_ComposeQueueAndAgent");
        Add_Step_WaitUntil("queue formation becomes ready", n"Check_QueueReady");
        Add_Step("join through the Crowd queue adapter", n"Step_RequestJoin");
        // 520uu spawn-to-slot walk at 600uu/s (MaxSpeed) + claim + 10uu settle needs ~2.2s; the
        // harness default of 240 frames only buffers ~1s at 240fps and this lane has measured
        // 58-107fps, so match the sibling CrowdAdapterMovesAndResumes's 1200-frame budget.
        Add_Step_WaitUntil("Crowd reaches the assigned queue slot and becomes idle", n"Check_ArrivedAndIdle", 1200);
        Add_Step_WaitUntil("adapter applies the assigned owner-target facing after arrival", n"Check_FacingApplied");
        Add_Step_WaitFrames("queue facing remains owned across later Crowd facing passes", 3);
        Add_Step("assert final queue-facing contract", n"Step_AssertFacing");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_NavigationReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto SpawnResult = Do_ProjectOntoSurface(FVector(-400.0f, 0.0f, 0.0f), FVector(100.0f, 100.0f, 300.0f));
        const auto TargetResult = Do_ProjectOntoSurface(FVector(-280.0f, 0.0f, 0.0f), FVector(100.0f, 100.0f, 300.0f));
        const bool SpawnIsNavigable = SpawnResult.Get_Status() == ECk_NavSurface_QueryStatus::Success;
        const bool TargetIsNavigable = TargetResult.Get_Status() == ECk_NavSurface_QueryStatus::Success;
        if (SpawnIsNavigable) { _Spawn = SpawnResult.Get_Location(); }
        auto Result = OutResult;
        Result.Set(SpawnIsNavigable && TargetIsNavigable);
    }

    private FCk_NavSurface_ProjectionResult Do_ProjectOntoSurface(FVector InPoint, FVector InSearchHalfExtents) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(InSearchHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query);
    }

    UFUNCTION()
    private void Step_ComposeQueueAndAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _QueueOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_QueueOwner,
            FTransform(FRotator(0.0f, ExpectedYaw, 0.0f), FVector(120.0f, 0.0f, 0.0f), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto QueueParams = FCk_Fragment_Queue_ParamsData();
        _Category = utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.AutoTestFacing");
        QueueParams.Set_Category(_Category);
        QueueParams.Set_SlotSpacingUu(ExpectedSlotSpacingUu);
        QueueParams.Set_LayoutAlgorithm(ECk_Queue_LayoutAlgorithm::Linear);
        QueueParams.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ReserveOnFormation);
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
        FCk_Queue_DebugSnapshot DebugSnapshot;
        bool HasDebugSnapshot = false;
        for (const auto& Snapshot : utils_queue::Get_DebugSnapshots(InHandle))
        {
            if (Snapshot.Get_Category() == _Category)
            {
                DebugSnapshot = Snapshot;
                HasDebugSnapshot = true;
                break;
            }
        }
        const auto FormationState = DebugSnapshot.Get_FormationState();
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue)
            && _Queue.Get_State() == ECk_Queue_State::Ready
            && _Queue.Get_Category() == _Category
            && HasDebugSnapshot
            && DebugSnapshot.Get_LayoutAlgorithm() == ECk_Queue_LayoutAlgorithm::Linear
            && DebugSnapshot.Get_SlotSpacingUu() == ExpectedSlotSpacingUu
            && DebugSnapshot.Get_SlotClaimPolicy() == ECk_Queue_SlotClaimPolicy::ReserveOnFormation
            && FormationState.Get_State() == DebugSnapshot.Get_State()
            && FormationState.Get_Reason() == ECk_Queue_EventReason::None
            && FormationState.Get_QueueRevision() == DebugSnapshot.Get_Revision()
            && FormationState.Get_RetryEpisode() == DebugSnapshot.Get_RetryEpisode());
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
            "Crowd queue adapter applies the assigned Queue owner-target yaw only after its movement episode reaches idle");
    }
}
