// Language=angelscript

//============================================================================
// CK VOXEL NAV — AUTOMATION TEST: ANGELSCRIPT PLANS A ROUTE AROUND AN OBSTACLE
//============================================================================
//
// The whole public surface driven from AngelScript, in the order a consumer
// would drive it: compose a volume, bake it, compose the path feature on an
// agent, ask for a route, read the answer.
//
//   1. A Static JoltBody box sits at the centre of an otherwise empty volume,
//      1000uu of clear space on every side of it.
//   2. Once the body is in the Jolt world, Request_Build bakes the volume.
//      Auto-build is disabled so the bake this test waits on is the one it
//      asked for.
//   3. The endpoints face each other through the box, so the straight line
//      between them is blocked and any answer has to be longer than it.
//   4. Request_FindPath, then read the result: Ready, endpoints preserved,
//      every waypoint in baked free space, length past the straight line.
//
// The route is only ever validated against the volume's own occupancy — the
// same structure the search planned through — so a disagreement is the
// module's, never the physics world's.
//
// Isolated Y band: 62000, at Z 20000 — far from every other autotest's bodies.
//============================================================================

class UCk_AutoTest_VoxelNav_PlansARouteAroundABakedObstacle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _ObstacleBody;
    private FCk_Handle_VoxelNavVolume _Volume;
    private FCk_Handle_VoxelNavPath _Path;

    private FVector _VolumeCenter = FVector(0.0, 62000.0, 20000.0);
    private FVector _VolumeHalfExtents = FVector(800.0, 800.0, 800.0);
    private FVector _ObstacleHalfExtents = FVector(300.0, 300.0, 300.0);
    private FVector _RouteFrom = FVector(-700.0, 62000.0, 20000.0);
    private FVector _RouteTo = FVector(700.0, 62000.0, 20000.0);

    private float32 _FinestCellSizeUu = 50.0f;
    private float _EndpointToleranceUu = 1.0;

    private int32 _BuildCompletions = 0;
    private int32 _PathCompletions = 0;
    private int32 _PathReadyFires = 0;
    private int32 _PathFailedFires = 0;
    private ECk_Request_OperationResult _LastPathResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto ObstacleEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        ObstacleEntity.Request_OverrideToSelf();
        utils_transform::Add(ObstacleEntity, FTransform(FRotator::ZeroRotator, _VolumeCenter),
            ECk_Replication::DoesNotReplicate);

        auto ObstacleShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        ObstacleShape.Set_HalfExtents(_ObstacleHalfExtents);
        auto ObstacleParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        ObstacleParams.Set_ShapeDimensions(ObstacleShape);
        ObstacleParams.Set_MotionType(ECk_MotionType::Static);
        _ObstacleBody = utils_jolt_body::Add(ObstacleEntity, ObstacleParams);

        auto VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        VolumeEntity.Request_OverrideToSelf();

        auto VolumeParams = FCk_VoxelNavVolume_Spec(
            FBox(_VolumeCenter - _VolumeHalfExtents, _VolumeCenter + _VolumeHalfExtents),
            _FinestCellSizeUu);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _Volume = utils_voxel_nav_volume::Add(VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid volume handle");
        Assert_True(utils_voxel_nav_volume::Has(FCk_Handle(_Volume)),
            "the volume entity must carry the feature Add() composed");

        Add_Step_WaitUntil("the obstacle's static body joins the Jolt world", n"Check_ObstacleBodyAdded");
        Add_Step(          "request the bake",                                n"Step_RequestBuild");
        Add_Step_WaitUntil("the bake reports back to its caller",             n"Check_BakeCompleted");
        Add_Step(          "assert the bake, then request the route",         n"Step_AssertBake_RequestPath");
        Add_Step_WaitUntil("the search reports back to its caller",           n"Check_PathCompleted");
        Add_Step(          "assert the route the caller reads",               n"Step_AssertRoute");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RequestBuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_voxel_nav_volume::Request_Build(_Volume, FCk_Request_VoxelNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
    }

    UFUNCTION()
    private void Step_AssertBake_RequestPath(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_voxel_nav_volume::Get_IsBuilt(_Volume),
            "the volume must publish its octree before the route is asked for");
        Assert_True(utils_voxel_nav_volume::Get_BuildEpoch(_Volume) >= 1,
            f"the build epoch should have advanced, got {utils_voxel_nav_volume::Get_BuildEpoch(_Volume)}");

        // The obstacle is what makes the straight line an invalid answer - if the bake never saw it, the
        // detour assertion below would be measuring nothing.
        Assert_False(utils_voxel_nav_volume::Get_IsPointFree(_Volume, _VolumeCenter),
            "the bake must report the obstacle's centre as blocked");

        Assert_True(utils_voxel_nav_volume::Get_IsPointFree(_Volume, _RouteFrom) &&
                    utils_voxel_nav_volume::Get_IsPointFree(_Volume, _RouteTo),
            "both requested endpoints must stand in baked free space");

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        AgentEntity.Request_OverrideToSelf();

        _Path = utils_voxel_nav_path::Add(AgentEntity, FCk_VoxelNavPath_Spec());

        Assert_True(ck::IsValid(_Path), "Add() must return a valid path handle");

        // Bound before the request, so a search that answered synchronously would still be observed.
        utils_voxel_nav_path::BindTo_OnPathReady(_Path,
            FCk_Delegate_VoxelNavPath_OnPathReady(this, n"OnPathReady"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight);
        utils_voxel_nav_path::BindTo_OnPathFailed(_Path,
            FCk_Delegate_VoxelNavPath_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight);

        utils_voxel_nav_path::Request_FindPath(_Path,
            FCk_Request_VoxelNavPath_FindPath(_Volume, _RouteFrom, _RouteTo),
            FCk_Delegate_Request_OnCompleted(this, n"OnFindPathCompleted"));
    }

    UFUNCTION()
    private void Step_AssertRoute(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_PathCompletions, 1, "the request-completion delegate must fire exactly once");
        Assert_True(_LastPathResult == ECk_Request_OperationResult::Succeeded,
            f"a search that found a route must complete with Succeeded (got {_LastPathResult})");
        Assert_Equals_Int(_PathReadyFires, 1, "OnPathReady must fire exactly once");
        Assert_Equals_Int(_PathFailedFires, 0, "OnPathFailed must not fire for a route that was found");

        Assert_True(utils_voxel_nav_path::Get_Status(_Path) == ECk_VoxelNav_PathStatus::Ready,
            f"the path must report Ready against the bake it planned on (got {utils_voxel_nav_path::Get_Status(_Path)})");
        Assert_False(utils_voxel_nav_path::Get_IsStale(_Path),
            "a path planned against the live bake is not stale");
        Assert_Equals_Int(utils_voxel_nav_path::Get_PlannedAgainstEpoch(_Path),
            utils_voxel_nav_volume::Get_BuildEpoch(_Volume),
            "the path must record the build epoch it planned against");

        auto Waypoints = utils_voxel_nav_path::Get_Waypoints(_Path);

        Assert_True(Waypoints.Num() >= 2,
            f"a Ready path holds at least the two requested endpoints (got {Waypoints.Num()})");
        Assert_True((Waypoints[0] - _RouteFrom).Size() < _EndpointToleranceUu,
            f"the route must start where it was asked to (got {Waypoints[0]})");
        Assert_True((Waypoints[Waypoints.Num() - 1] - _RouteTo).Size() < _EndpointToleranceUu,
            f"the route must end where it was asked to (got {Waypoints[Waypoints.Num() - 1]})");

        auto EveryWaypointIsFree = true;
        for (auto Waypoint : Waypoints)
        {
            if (utils_voxel_nav_volume::Get_IsPointFree(_Volume, Waypoint) == false)
            { EveryWaypointIsFree = false; }
        }

        Assert_True(EveryWaypointIsFree, "every waypoint must stand in space the bake calls free");

        // The obstacle spans the straight line between the endpoints, so a route that is no longer than it
        // went through the box.
        auto StraightLineUu = (_RouteTo - _RouteFrom).Size();
        Assert_True(utils_voxel_nav_path::Get_PathLengthUu(_Path) > StraightLineUu,
            f"a route around the obstacle must be longer than the {StraightLineUu}uu straight line (got {utils_voxel_nav_path::Get_PathLengthUu(_Path)})");

        Assert_Equals_Int(utils_voxel_nav_path::Get_RefinedWaypointCount(_Path), Waypoints.Num(),
            "the reported refined count must be the stored waypoint count");
        Assert_True(utils_voxel_nav_path::Get_RawWaypointCount(_Path) >=
                    utils_voxel_nav_path::Get_RefinedWaypointCount(_Path),
            "refinement never adds waypoints to the search's own path");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_ObstacleBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_ObstacleBody) && utils_jolt_body::Get_IsBodyAdded(_ObstacleBody));
    }

    UFUNCTION()
    private void Check_BakeCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BuildCompletions >= 1);
    }

    UFUNCTION()
    private void Check_PathCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PathCompletions >= 1);
    }

    //------------------------------------------------------------------------
    // Delegates
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _BuildCompletions += 1;

        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"the bake must report Succeeded to the caller that requested it (got {InResult})");
    }

    UFUNCTION()
    private void OnFindPathCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _PathCompletions += 1;
        _LastPathResult = InResult;
    }

    UFUNCTION()
    private void OnPathReady(FCk_Handle_VoxelNavPath InPath)
    {
        _PathReadyFires += 1;
    }

    UFUNCTION()
    private void OnPathFailed(FCk_Handle_VoxelNavPath InPath, ECk_VoxelNav_PathSearchOutcome InOutcome)
    {
        _PathFailedFires += 1;
    }
}
