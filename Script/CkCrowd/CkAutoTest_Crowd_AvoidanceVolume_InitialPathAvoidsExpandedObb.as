// Language=angelscript

class UCk_AutoTest_Crowd_AvoidanceVolume_InitialPathAvoidsExpandedObb : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private const float AgentRadius = 42.0f;
    private const FVector Spawn = FVector(-700.0, 0.0, 100.0);
    private const FVector Goal = FVector(700.0, 0.0, 100.0);
    private const FVector VolumeHalfExtents = FVector(220.0, 90.0, 100.0);
    private const float VolumeYaw = 35.0;
    private const float StraightPathLateralTolerance = 5.0;

    private FCk_Handle _AgentEntity;
    private FCk_Handle _VolumeEntity;
    private FCk_Handle_CrowdAvoidanceVolume _Volume;
    private FCk_Handle_CrowdAgent _Agent;
    private FVector _Centre;
    private bool _RouteIssued = false;
    private bool _ReplacementRouteIssued = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto SelfHandle = DoGet_ScriptEntity();
        if (_RouteIssued == false)
        {
            FVector Projected;
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector::ZeroVector, 100.0f, Projected, 300.0f) == false)
            { return; }
            _Centre = FVector(0.0, 0.0, float(Projected.Z));
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, Spawn + FVector(0.0, 0.0, _Centre.Z), 100.0f, Projected, 300.0f) == false)
            { return; }
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, Goal + FVector(0.0, 0.0, _Centre.Z), 100.0f, Projected, 300.0f) == false)
            { return; }
            SpawnVolumeAndAgent(SelfHandle);
            return;
        }

        const auto Status = utils_nav::Get_PathStatus(_Agent);
        if (_ReplacementRouteIssued == false &&
            utils_crowd_avoidance_volume::Get_IsNavigationConfirmed(_Volume) == false)
        { return; }
        if (Status == ECk_Nav_PathStatus::Failed || Status == ECk_Nav_PathStatus::Partial)
        {
            const auto PhaseName = _ReplacementRouteIssued ? "replacement path" : "avoidance-volume path";
            FinishFailure(f"{PhaseName} returned unexpected status {Status}");
            return;
        }
        if (Status != ECk_Nav_PathStatus::Ready) { return; }

        const auto Waypoints = utils_nav::Get_PathResult(_Agent).Get_Waypoints();
        if (Waypoints.Num() == 0)
        {
            const auto PhaseName = _ReplacementRouteIssued ? "replacement path" : "avoidance-volume path";
            FinishFailure(f"{PhaseName} was Ready with no installed waypoints");
            return;
        }

        if (_ReplacementRouteIssued)
        {
            if (IsReplacementPathStraight(Waypoints))
            { FinishSuccess(); }
            return;
        }

        auto Previous = Spawn + FVector(0.0, 0.0, _Centre.Z);
        auto Deviates = false;
        for (auto Waypoint : Waypoints)
        {
            if (SegmentIntersectsExpandedObb(Previous, Waypoint))
            { FinishFailure(f"installed CkNavigation segment crosses the expanded avoidance OBB: {Previous} -> {Waypoint}"); return; }
            if (DistanceToBaseline(Waypoint) > StraightPathLateralTolerance) { Deviates = true; }
            Previous = Waypoint;
        }
        const auto FinalGoal = Goal + FVector(0.0, 0.0, _Centre.Z);
        if (SegmentIntersectsExpandedObb(Previous, FinalGoal))
        { FinishFailure(f"installed final CkNavigation segment crosses the expanded avoidance OBB: {Previous} -> {FinalGoal}"); return; }
        Assert_True(Deviates, "installed path has a waypoint that deviates from the straight baseline");
        BeginImmediateReplacementPath(SelfHandle);
    }

    private void SpawnVolumeAndAgent(FCk_Handle& InOwner)
    {
        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        auto VolumeTransform = utils_transform::Add(_VolumeEntity,
            FTransform(FRotator(0.0, VolumeYaw, 0.0), _Centre, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        const auto VolumeParams = FCk_Fragment_CrowdAvoidanceVolume_ParamsData(VolumeHalfExtents, 400.0);
        _Volume = utils_crowd_avoidance_volume::Add(VolumeTransform, VolumeParams);
        if (ck::Is_NOT_Valid(_Volume))
        { FinishFailure("failed to compose avoidance volume"); return; }

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(FRotator::ZeroRotator, Spawn + FVector(0.0, 0.0, _Centre.Z), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _Agent = utils_crowd_agent::Add(AgentTransform, FCk_Fragment_CrowdAgent_ParamsData(AgentRadius, 192.0f));
        if (ck::Is_NOT_Valid(_Agent))
        { FinishFailure("failed to compose crowd agent"); return; }
        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal + FVector(0.0, 0.0, _Centre.Z)));
        _RouteIssued = true;
    }

    private void BeginImmediateReplacementPath(FCk_Handle& InOwner)
    {
        // Intentionally do not wait for the deferred destroys: this is the first-reset removal path.
        utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
        utils_entity_lifetime::Request_DestroyEntity(_AgentEntity);

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(FRotator::ZeroRotator, Spawn + FVector(0.0, 0.0, _Centre.Z), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _Agent = utils_crowd_agent::Add(AgentTransform, FCk_Fragment_CrowdAgent_ParamsData(AgentRadius, 192.0f));
        if (ck::Is_NOT_Valid(_Agent))
        { FinishFailure("failed to compose replacement crowd agent after removal"); return; }
        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal + FVector(0.0, 0.0, _Centre.Z)));
        _ReplacementRouteIssued = true;
    }

    private bool IsReplacementPathStraight(const TArray<FVector>& InWaypoints)
    {
        for (auto Waypoint : InWaypoints)
        {
            const auto LateralDistance = DistanceToBaseline(Waypoint);
            if (LateralDistance > StraightPathLateralTolerance)
            { return false; }
        }
        return true;
    }

    private bool SegmentIntersectsExpandedObb(FVector InStart, FVector InEnd)
    {
        const auto Transform = FTransform(FRotator(0.0, VolumeYaw, 0.0), _Centre, FVector::OneVector);
        const auto A = Transform.InverseTransformPosition(InStart);
        const auto B = Transform.InverseTransformPosition(InEnd);
        const auto Extent = VolumeHalfExtents + FVector(AgentRadius, AgentRadius, 0.0);
        auto Enter = 0.0;
        auto Exit = 1.0;
        return ClipAxis(A.X, B.X - A.X, Extent.X, Enter, Exit)
            && ClipAxis(A.Y, B.Y - A.Y, Extent.Y, Enter, Exit);
    }

    private bool ClipAxis(float InStart, float InDelta, float InExtent, float&out InOutEnter, float&out InOutExit)
    {
        if (Math::Abs(InDelta) < 0.0001)
        { return InStart >= -InExtent && InStart <= InExtent; }
        auto T0 = (-InExtent - InStart) / InDelta;
        auto T1 = (InExtent - InStart) / InDelta;
        if (T0 > T1) { const auto Swap = T0; T0 = T1; T1 = Swap; }
        InOutEnter = Math::Max(InOutEnter, T0);
        InOutExit = Math::Min(InOutExit, T1);
        return InOutEnter <= InOutExit;
    }

    private float DistanceToBaseline(FVector InPoint)
    { return float(Math::Abs(InPoint.Y)); }
}
