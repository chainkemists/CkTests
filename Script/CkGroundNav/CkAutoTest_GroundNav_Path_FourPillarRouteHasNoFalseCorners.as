// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: THE FOUR-PILLAR ROUTE HAS NO FALSE CORNERS
//============================================================================
//
// The Walk gym's scene, in a headless world, asked the one thing the gym can
// only be looked at to answer: does the west-east route bend where there is
// nothing to bend around? The scene is the gym's verbatim - a 3600 x 2400 slab
// and four 150 x 150 x 300 pillars staggered across the lane at Y 0, at
// (-900,-60), (-300,120), (300,-100) and (900,80). Four STAGGERED pillars is
// the shape that produces the artefact: a rectangle decomposition splits open
// floor for shape reasons rather than for obstacles, and every such split is a
// portal whose ends the funnel insets by an agent radius.
//
// A corner is REAL when there is something within reach of it to be a corner
// OF. The reach is radius + radius + one cell = 93uu: the body's own standoff,
// the corner offset that moves the waypoint a further radius off the wall, and
// one cell of lattice slack.
//
// The query that states that directly - Get_BoundarySegments - is C++-only BY
// CONTRACT (CkNavSurface_Utils.h:117-124, "no UFUNCTION here"), so AngelScript
// cannot ask it. The proxy is the facade's own surface raycast, which reads the
// same field: sixteen probes of 93uu around the waypoint, nearest Blocked hit
// wins. Sixteen at that radius spaces the arcs ~9.5uu apart, an order under the
// 150uu pillars and the slab edge, so nothing here slips between two rays.
//
// The route MUST bend - pillar 0 spans Y -135..+15 and so stands ON the lane -
// so the interior count is asserted before the corners are, or the boundary
// claim would be about an empty set.
//
// "Within 5% of the straight line" claims nothing where the straight line is
// not walkable, so it is gated on a raycast down the lane and SKIPPED loudly
// otherwise. Pillar 0 sits on the lane, so on THIS scene the skip is expected;
// the gate is here so the claim cannot silently go vacuous if the scene moves.
//
// Isolated Y band: 160000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Path_FourPillarRouteHasNoFalseCorners : UCk_AutoTest_Base
{
    // A 20-tile bake of a 3800 x 2600 region, then one search. Deliberately slack: a contract that
    // expires on the harness's anonymous TimesUp names nothing.
    default _TimeoutSeconds = 300.0f;

    // ---- The scene, verbatim from CkGroundNavGym_Walk_PlayerController.as:16-28, stated
    // scene-local and pushed onto the band by Get_ScenePoint ----------------------------------
    private const float BandY = 160000.0;
    private const float SurfaceZ = 0.0;
    private const float SlabHalfX = 1800.0;
    private const float SlabHalfY = 1200.0;
    private const float SlabHalfZ = 100.0;
    private const float PillarHalfXY = 75.0;
    private const float PillarHalfZ = 150.0;
    private const float VolumeHalfX = 1900.0;
    private const float VolumeHalfY = 1300.0;
    private const float VolumeFloorZ = -400.0;
    private const float VolumeCeilingZ = 600.0;
    private const float StartX = -1650.0;
    private const float GoalX = 1650.0;

    // ---- The bake: the 25uu lattice every GroundNav fixture bakes on, 800uu tiles, the gym's
    // own 34uu / 90uu body -------------------------------------------------------------------
    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 800.0;
    private const float AgentRadiusUu = 34.0;
    private const float AgentHalfHeightUu = 90.0;

    // AgentRadiusUu + AgentRadiusUu + CellSizeUu, written out because a class default initialiser
    // reading other members is init-order sensitive and nothing else in the corpus does it.
    private const float ProbeReachUu = 93.0;
    private const int32 ProbeDirections = 16;

    // Further than any probe can reach, so it can never be mistaken for a hit.
    private const float NoBoundaryUu = 1000000.0;
    private const float LengthSlack = 1.05;

    // ---- Budgets - every one a ceiling on a NAMED condition, never a settle -----------------
    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 PathFrameBudget = 1800;

    // ---- Fixture ---------------------------------------------------------------------------
    private FCk_Handle _SelfHandle;
    private FCk_Handle _SlabEntity;
    private FCk_Handle _VolumeEntity;
    private FCk_Handle _PlannerEntity;
    private FCk_Handle_JoltBody _SlabBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_GroundNavPath _Planner;
    private TArray<FCk_Handle> _PillarEntities;
    private TArray<FCk_Handle_JoltBody> _PillarBodies;

    // ---- World state this test changes and must hand back ----------------------------------
    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    // ---- Episode bookkeeping ---------------------------------------------------------------
    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;
    private int32 _PathRequests = 0;
    private int32 _PathCompletions = 0;
    private ECk_GroundNav_PathStatus _RouteStatus = ECk_GroundNav_PathStatus::InProgress;
    private TArray<FVector> _Waypoints;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage the slab, the four pillars, the volume and the planner", n"Step_StageScene");
        Add_Step_WaitUntil("every body reaches the Jolt static world",                     n"Check_BodiesAdded",    BodyFrameBudget);
        Add_Step(          "ask the volume to bake",                                       n"Step_RequestBake");
        Add_Step_WaitUntil("the field reports itself built",                               n"Check_FieldBuilt",     BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",                      n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles",                                      n"Check_SurfaceSettled", SurfaceFrameBudget);
        Add_Step(          "plan the west-east route down the lane",                       n"Step_PlanWestToEast");
        Add_Step_WaitUntil("the route is answered",                                        n"Check_PathAnswered",   PathFrameBudget);
        Add_Step(          "every interior waypoint stands at a real corner",              n"Step_AssertNoFalseCorners");
        Add_Step(          "the route is near-straight where the straight line is clear",  n"Step_AssertLengthIfLaneIsClear");
        Add_Step(          "hand the world back",                                          n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    // ---- Staging: the geometry goes in BEFORE the bake, because the field bakes what the Jolt
    // static world holds at the moment the build starts --------------------------------------

    UFUNCTION()
    private void Step_StageScene(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _SlabEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _SlabEntity.Request_OverrideToSelf();
        _SlabEntity.Set_DebugName(n"AutoTest_GroundNav_FourPillarSlab");
        _SlabBody = Add_StaticBox(_SlabEntity,
            Get_ScenePoint(FVector(0.0, 0.0, SurfaceZ - SlabHalfZ)),
            FVector(SlabHalfX, SlabHalfY, SlabHalfZ));

        Assert_True(ck::IsValid(_SlabBody),
            "the slab's Jolt body must be valid - the field bakes from the Jolt static world, so a slab that never got a body is a field with no ground in it");

        Add_Pillar(n"AutoTest_GroundNav_FourPillar0", FVector(-900.0, -60.0, 0.0));
        Add_Pillar(n"AutoTest_GroundNav_FourPillar1", FVector(-300.0, 120.0, 0.0));
        Add_Pillar(n"AutoTest_GroundNav_FourPillar2", FVector(300.0, -100.0, 0.0));
        Add_Pillar(n"AutoTest_GroundNav_FourPillar3", FVector(900.0, 80.0, 0.0));

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(float32(CellSizeUu), float32(CellHeightUu));
        Config.Set_TileSizeUu(float32(TileSizeUu));

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(float32(AgentHalfHeightUu), float32(AgentRadiusUu))));

        // The slab's own edges lie INSIDE the volume, so at the default sensitivity the ledge filter
        // would demote the whole perimeter and pinch the lane the pillars are supposed to be the only
        // thing bending. The gym zeroes it for the same reason.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            Get_ScenePoint(FVector(-VolumeHalfX, -VolumeHalfY, VolumeFloorZ)),
            Get_ScenePoint(FVector(VolumeHalfX, VolumeHalfY, VolumeCeilingZ)));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid GroundNav volume handle");

        _PlannerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _PlannerEntity.Request_OverrideToSelf();
        _PlannerEntity.Set_DebugName(n"AutoTest_GroundNav_FourPillarPlanner");

        auto PathParams = FCk_Fragment_GroundNavPath_ParamsData(float32(AgentRadiusUu));
        PathParams.Set_VerticalToleranceUu(float32(CellHeightUu * 4.0));
        _Planner = utils_ground_nav_path::Add(_PlannerEntity, PathParams);

        Assert_True(ck::IsValid(_Planner), "Add() must return a valid GroundNav path handle");
    }

    private void Add_Pillar(FName InDebugName, FVector InFootprint)
    {
        auto PillarEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        PillarEntity.Request_OverrideToSelf();
        PillarEntity.Set_DebugName(InDebugName);

        auto Body = Add_StaticBox(PillarEntity,
            Get_ScenePoint(FVector(InFootprint.X, InFootprint.Y, SurfaceZ + PillarHalfZ)),
            FVector(PillarHalfXY, PillarHalfXY, PillarHalfZ));

        Assert_True(ck::IsValid(Body),
            f"pillar {InDebugName} must have a valid Jolt body - a pillar the bake never saw is open floor, and the route would have nothing to bend around");

        _PillarEntities.Add(PillarEntity);
        _PillarBodies.Add(Body);
    }

    private FCk_Handle_JoltBody Add_StaticBox(FCk_Handle InEntity, FVector InCentre, FVector InHalfExtents)
    {
        auto Entity = InEntity;
        utils_transform::Add(Entity,
            FTransform(FRotator::ZeroRotator, InCentre), ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);

        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);

        return utils_jolt_body::Add(Entity, Params);
    }

    UFUNCTION()
    private void Check_BodiesAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto AllAdded = utils_jolt_body::Get_IsBodyAdded(_SlabBody);

        for (int32 Index = 0; Index < _PillarBodies.Num(); Index++)
        {
            if (utils_jolt_body::Get_IsBodyAdded(_PillarBodies[Index]) == false)
            { AllAdded = false; }
        }

        Res.Set(AllAdded && _PillarBodies.Num() == 4);
    }

    // ---- The bake and the provider ---------------------------------------------------------

    UFUNCTION()
    private void Step_RequestBake(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
    }

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _BuildCompletions += 1;
        _LastBuildResult = InResult;
    }

    UFUNCTION()
    private void Check_FieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BuildCompletions >= 1 && utils_ground_nav_volume::Get_IsBuilt(_Volume));
    }

    UFUNCTION()
    private void Step_SelectProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastBuildResult == ECk_Request_OperationResult::Succeeded,
            f"a bake that finished must complete with Succeeded (got {_LastBuildResult})");

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
        _ProviderSwapped = true;

        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::GroundNav,
            f"the world must report the provider it was told to answer on (got {ProviderNow})");
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_IsSurfaceSettled()
            && utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    // ---- The route -------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PlanWestToEast(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PathRequests += 1;

        utils_ground_nav_path::Request_FindPath(_Planner,
            FCk_Request_GroundNavPath_FindPath(Get_StartPoint(), Get_GoalPoint()),
            FCk_Delegate_Request_OnCompleted(this, n"OnPathCompleted"));
    }

    UFUNCTION()
    private void OnPathCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _PathCompletions += 1;
    }

    // EVERY episode asked for has ended, not merely one more than last time: a superseded FindPath
    // completes as Failed_Cancelled, so a count of one further completion would fire on that.
    UFUNCTION()
    private void Check_PathAnswered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PathCompletions >= _PathRequests
            && utils_ground_nav_path::Get_HasFreshResult(_Planner));
    }

    // ---- Assertions ------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertNoFalseCorners(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto RouteResult = utils_ground_nav_path::Get_Result(_Planner);

        _RouteStatus = RouteResult.Get_Status();
        _Waypoints = RouteResult.Get_Waypoints();

        const auto Route = Get_RoutePolyline(_Waypoints);
        const auto WaypointCount = _Waypoints.Num();
        const auto InteriorCount = Route.Num() > 2 ? Route.Num() - 2 : 0;

        ck::nav::Display(f"[GROUNDNAV-SHORTCUT] route: status={_RouteStatus} waypoints={WaypointCount} interior={InteriorCount}");

        Assert_True(_RouteStatus == ECk_GroundNav_PathStatus::Ready,
            f"3300uu of open slab separate the two ends and nothing spans the lane, so the west-east route must be Ready (got {_RouteStatus})");

        // The POSITIVE that keeps the boundary claim below from being about an empty set: pillar 0
        // spans Y -135..+15 and so stands ON the lane, and a route that got past it bent somewhere.
        Assert_True(InteriorCount >= 1,
            f"pillar 0 stands on the straight line between the ends, so a Ready route must carry at least one interior waypoint to have got round it (got {InteriorCount})");

        auto FalseCorners = 0;
        auto WorstUu = 0.0;
        auto Reported = FVector::ZeroVector;

        for (int32 Index = 1; Index + 1 < Route.Num(); Index++)
        {
            const auto NearestUu = Get_NearestBoundaryUu(Route[Index]);

            if (NearestUu <= ProbeReachUu)
            { continue; }

            FalseCorners += 1;

            // The FIRST offender is the one reported: it is the earliest place the polyline left the
            // field's own geometry, and every later one may simply be downstream of it.
            if (FalseCorners > 1)
            { continue; }

            Reported = Route[Index];
            WorstUu = NearestUu;
        }

        ck::nav::Display(f"[GROUNDNAV-SHORTCUT] corners: interior={InteriorCount} falseCorners={FalseCorners} firstAt={Reported}");

        Assert_Equals_Int(FalseCorners, 0,
            f"{FalseCorners} of {InteriorCount} interior waypoints stand further than {ProbeReachUu}uu from anything - the first at {Reported}, whose nearest boundary read {WorstUu}uu (a value near {NoBoundaryUu} means no probe was Blocked at all). A waypoint with no boundary within a body radius, a corner offset and a cell is a bend around a wall that is not there.");
    }

    UFUNCTION()
    private void Step_AssertLengthIfLaneIsClear(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Start = Get_StartPoint();
        const auto Goal = Get_GoalPoint();

        auto LaneQuery = FCk_NavSurface_RaycastQuery(Start, Goal);
        const auto LaneResult = utils_nav_surface::Try_SurfaceRaycast(LaneQuery);
        const auto LaneStatus = LaneResult.Get_Status();

        const auto StraightUu = Get_DistanceXY(Start, Goal);
        const auto RouteUu = Get_PolylineLengthXY(Get_RoutePolyline(_Waypoints));
        const auto CeilingUu = StraightUu * LengthSlack;

        ck::nav::Display(f"[GROUNDNAV-SHORTCUT] length: straight={StraightUu}uu route={RouteUu}uu ceiling={CeilingUu}uu laneRaycast={LaneStatus}");

        if (LaneStatus != ECk_NavSurface_QueryStatus::Success)
        {
            // Pillar 0 sits on the lane, so this is the EXPECTED outcome on this scene. Said out loud
            // rather than asserted, because the claim means nothing where the line is not walkable.
            ck::nav::Display(f"[GROUNDNAV-SHORTCUT] length: SKIPPED - the straight line from {Start} to {Goal} is not clear (the raycast answered {LaneStatus}), so a near-straight route was never owed");
            return;
        }

        Assert_True(RouteUu <= CeilingUu,
            f"the facade's own raycast says the straight line down the lane is walkable end to end, so the funnelled route across the same ground must stay within 5% of it - {StraightUu}uu straight, ceiling {CeilingUu}uu, and the route measured {RouteUu}uu");
    }

    // ---- Geometry, answered here rather than by an engine helper so the fixture states its own
    // measure --------------------------------------------------------------------------------

    // The nearest Blocked hit across a ring of surface raycasts, or a sentinel further than any probe
    // can reach when every one of them ran clear to its end.
    private float Get_NearestBoundaryUu(FVector InPoint)
    {
        auto NearestUu = NoBoundaryUu;

        for (int32 Index = 0; Index < ProbeDirections; Index++)
        {
            const auto Angle = (2.0 * Math::PI) * (float(Index) / float(ProbeDirections));
            const auto End = InPoint
                + FVector(ProbeReachUu * Math::Cos(Angle), ProbeReachUu * Math::Sin(Angle), 0.0);

            auto Query = FCk_NavSurface_RaycastQuery(InPoint, End);
            const auto ProbeResult = utils_nav_surface::Try_SurfaceRaycast(Query);

            if (ProbeResult.Get_Status() != ECk_NavSurface_QueryStatus::Blocked)
            { continue; }

            const auto HitUu = Get_DistanceXY(InPoint, ProbeResult.Get_HitLocation());

            if (HitUu < NearestUu)
            { NearestUu = HitUu; }
        }

        return NearestUu;
    }

    private TArray<FVector> Get_RoutePolyline(TArray<FVector> InWaypoints)
    {
        TArray<FVector> Polyline;
        Polyline.Add(Get_StartPoint());

        for (int32 Index = 0; Index < InWaypoints.Num(); Index++)
        { Polyline.Add(InWaypoints[Index]); }

        return Polyline;
    }

    private float Get_PolylineLengthXY(TArray<FVector> InPolyline)
    {
        auto LengthUu = 0.0;

        for (int32 Index = 1; Index < InPolyline.Num(); Index++)
        { LengthUu += Get_DistanceXY(InPolyline[Index - 1], InPolyline[Index]); }

        return LengthUu;
    }

    private float Get_DistanceXY(FVector InFrom, FVector InTo)
    {
        const auto Delta = InTo - InFrom;
        return FVector(Delta.X, Delta.Y, 0.0).Size();
    }

    private FVector Get_ScenePoint(FVector InLocal)
    {
        return FVector(InLocal.X, BandY + InLocal.Y, InLocal.Z);
    }

    private FVector Get_StartPoint() { return Get_ScenePoint(FVector(StartX, 0.0, SurfaceZ)); }
    private FVector Get_GoalPoint()  { return Get_ScenePoint(FVector(GoalX, 0.0, SurfaceZ)); }

    // ---- Teardown --------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

    private void Teardown()
    {
        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        Destroy_Entity(_PlannerEntity);
        _PlannerEntity = FCk_Handle();
        Destroy_Entity(_VolumeEntity);
        _VolumeEntity = FCk_Handle();

        for (int32 Index = 0; Index < _PillarEntities.Num(); Index++)
        { Destroy_Entity(_PillarEntities[Index]); }

        _PillarEntities.Empty();
        _PillarBodies.Empty();

        Destroy_Entity(_SlabEntity);
        _SlabEntity = FCk_Handle();
    }

    private void Destroy_Entity(FCk_Handle InEntity)
    {
        if (ck::IsValid(InEntity) == false)
        { return; }

        auto Entity = InEntity;
        utils_entity_lifetime::Request_DestroyEntity(Entity);
    }
}
