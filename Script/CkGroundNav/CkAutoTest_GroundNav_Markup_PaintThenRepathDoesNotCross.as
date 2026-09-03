// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A SETTLED REPATH NEVER CROSSES A FRESH PAINT
//============================================================================
//
// The paint-then-repath race. Painting an impassable area is DEFERRED twice over: the
// markup request drains onto the volume a tick later, and the bake that turns
// the record into blocked cells is ticks after that. A caller that paints and
// immediately asks for a route is therefore asking a field that has not heard
// about the paint yet, and it will be handed a route straight through it.
//
// Get_IsMarkupLive is the named condition that closes the window, and this
// fixture is the contract for it:
//
//   plan -> the route crosses the spot -> paint -> WAIT FOR LIVE -> plan again
//   -> the route does not cross the spot.
//
// PHASE 2 pins the race itself rather than asserting it away. A second box is
// painted elsewhere on the corridor and the route is re-requested with NO wait
// at all; whether that route crossed is RECORDED and logged, never asserted.
// Asserting it either way would be wrong: "it crossed" is a statement about
// scheduling, and "it did not cross" would pass vacuously on any machine where
// the bake happened to land first. What is being pinned is the asymmetry - the
// SETTLED route never crosses, and that is the only half this test fails on.
//
// WHY THE PIN IS ONLY REAL WITH THE GATE. A wait that is already satisfied on
// arrival proves nothing. Phase 1 must FAIL under ck.GroundNav.Debug.MarkupLiveGate 0,
// which forces Get_IsMarkupLive true without asking the field.
//
// WHY THE BAKE IS SLICED TO ONE TILE A TICK. A paint rebuilds the WHOLE volume,
// and at the default probe budget this fixture's eight tiles all bake inside the
// single frame the sequencer leaves between a satisfied wait and the step after
// it. The settled route then came out clean whether or not it had waited, and the
// test passed under the bypass. A budget of one probe admits exactly one tile per
// tick, so the re-bake spans eight slices and a route planned before liveness is
// planned against a field the paint has not reached yet.
//
// WHY THE STANDOFF IS A RADIUS LESS A CELL. Clearance admits a cell whose
// CENTRE sits a body radius from blocked ground, and the lattice quantizes that
// centre by half a cell either side. The standoff the field actually promises a
// funnelled route is therefore the radius less one cell, and inflating by the
// full radius would assert a margin nothing ever undertook to hold. The
// unambiguous half of the claim - that no LEG of the route passes through the
// painted box at all - is asserted against the raw box and is what fails under
// the bypass.
//
// FIXTURE. One Static JoltBody slab whose top sits at Z 0, overhanging the
// GroundNav volume on every horizontal side so no cliff edge exists inside the
// field, auto-build disabled so the bake waited on is the one asked for. A box
// shape is convex and therefore closed - an open mesh would trip the bake's
// OPEN COLLISION warning, and the harness escalates a Warning into a failure.
// The volume is 1800 x 800 uu with the route running 1200 uu down its middle,
// so the 300 uu of margin at each end and the 250 uu of corridor either side of
// a painted box are both comfortably wider than the 42 uu body radius.
//
// The provider is per world and every other fixture in this map reads it, so
// the previous selection is captured before the swap and handed back both when
// this test concludes AND in DoEndPlay - every exit path, including the engine
// TimeLimit one, must put the world back.
//
// Isolated Y band: 130000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Markup_PaintThenRepathDoesNotCross : UCk_AutoTest_Base
{
    // Wide enough that every wait below expires on its OWN budget and names the condition it was
    // on, rather than the harness's anonymous TimesUp arriving first.
    default _TimeoutSeconds = 180.0f;

    //------------------------------------------------------------------------
    // Fixture geometry
    //------------------------------------------------------------------------

    private const float BandY = 130000.0;

    private const float SlabHalfX = 1100.0;
    private const float SlabHalfY = 600.0;
    private const float SlabHalfZ = 50.0;

    private const float VolumeHalfX = 900.0;
    private const float VolumeHalfY = 400.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float SurfaceZ = 0.0;

    private const float StartX = -600.0;
    private const float GoalX = 600.0;

    // On the straight line between the ends, so the baseline route crosses it.
    private const float FirstBlockX = 0.0;

    // Far enough from the first box that the two never merge into one wall, and
    // still on the line the ends define.
    private const float SecondBlockX = 500.0;

    private const float BlockHalfXY = 150.0;
    private const float BlockHalfZ = 200.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 500.0;

    // 1800 x 800 uu of volume at 500uu tiles is a 4 x 2 lattice. The budget gates whether the NEXT
    // tile starts and a tile is never split, so one probe buys exactly one tile a tick: eight slices
    // of building per bake, which is more than any one frame between a wait and a plan can swallow.
    private const int32 ProbeBudgetPerTick = 1;

    private const float AgentRadius = 42.0;
    private const float ProfileHalfHeightUu = 96.0;

    // How close the BASELINE route must come to the spot for the fixture to be
    // measuring anything: a route that already detours has nothing to be
    // pushed off by a paint.
    private const float BaselineNearnessUu = 60.0;

    // What an EMPTY route answers when asked how near it passes to something. Wider than the field,
    // so it can never be mistaken for a real approach.
    private const float NoRouteDistanceUu = 1000000.0;

    //------------------------------------------------------------------------
    // Budgets - every one of these is a ceiling on a NAMED condition, never a
    // settle. A wait that expires names the step and the condition it was on.
    //
    // A bake is eight slices at the budget above and the paint reaches the field
    // through two deferrals either side of one, so the two ceilings that cover a
    // bake stand at some three hundred times what the sliced build asks for.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 3600;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 PathFrameBudget = 1800;
    private const int32 LiveFrameBudget = 3600;

    //------------------------------------------------------------------------
    // Fixture handles
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _VolumeEntity;
    private FCk_Handle _PlannerEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_GroundNavPath _Planner;

    private FCk_Handle_NavSurfaceMarkup _FirstMarkup;
    private FCk_Handle_NavSurfaceMarkup _SecondMarkup;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    //------------------------------------------------------------------------
    // Episode bookkeeping
    //------------------------------------------------------------------------

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    private int32 _PathRequests = 0;
    private int32 _PathCompletions = 0;

    private ECk_GroundNav_PathStatus _BaselineStatus = ECk_GroundNav_PathStatus::InProgress;
    private ECk_GroundNav_PathStatus _SettledStatus = ECk_GroundNav_PathStatus::InProgress;
    private ECk_GroundNav_PathStatus _UnsettledStatus = ECk_GroundNav_PathStatus::InProgress;

    private TArray<FVector> _BaselineWaypoints;
    private TArray<FVector> _SettledWaypoints;
    private TArray<FVector> _UnsettledWaypoints;

    // The settled wait's own trace, logged and never asserted. The surface revision is the sum of
    // every published tile epoch, so a re-bake that actually landed before the wait resolved moves
    // it; a wait satisfied without one reads back the number the paint saw.
    private int64 _RevisionAtPaint = -1;
    private int64 _RevisionAtLive = -1;
    private int32 _LivePolls = 0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage the floor, the volume and the planner",          n"Step_BuildFixture");
        Add_Step_WaitUntil("the floor reaches the Jolt static world",              n"Check_FloorBodyAdded",     BodyFrameBudget);
        Add_Step(          "ask the volume to bake",                               n"Step_RequestBake");
        Add_Step_WaitUntil("the field reports itself built",                       n"Check_FieldBuilt",         BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",              n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles at Ready",                     n"Check_SurfaceSettled",     SurfaceFrameBudget);
        Add_Step(          "plan the baseline route",                              n"Step_RequestBaselinePath");
        Add_Step_WaitUntil("the baseline route is answered",                       n"Check_PathAnswered",       PathFrameBudget);
        Add_Step(          "the baseline route crosses the spot",                  n"Step_AssertBaselineCrossesSpot");
        Add_Step(          "paint the spot and re-plan in the same frame",         n"Step_PaintAndRepathAtOnce");
        Add_Step_WaitUntil("the paint is live on the surface",                     n"Check_FirstPaintIsLive",   LiveFrameBudget);
        Add_Step(          "plan again now the paint is live",                     n"Step_RequestSettledPath");
        Add_Step_WaitUntil("the settled route is answered",                        n"Check_PathAnswered",       PathFrameBudget);
        Add_Step(          "the settled route does not cross the paint",           n"Step_AssertSettledPathAvoidsPaint");
        Add_Step(          "paint a second spot and re-plan with no wait at all",  n"Step_PaintSecondAndRepathAtOnce");
        Add_Step_WaitUntil("the unsettled route is answered",                      n"Check_PathAnswered",       PathFrameBudget);
        Add_Step(          "record what the unsettled route did",                  n"Step_ReportUnsettledCrossing");
        Add_Step(          "hand the world back",                                  n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Staging
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_BuildFixture(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _FloorEntity.Request_OverrideToSelf();

        utils_transform::Add(_FloorEntity,
            FTransform(FRotator::ZeroRotator, FVector(0.0, BandY, SurfaceZ - SlabHalfZ)),
            ECk_Replication::DoesNotReplicate);

        auto SlabShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        SlabShape.Set_HalfExtents(FVector(SlabHalfX, SlabHalfY, SlabHalfZ));

        auto SlabParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        SlabParams.Set_ShapeDimensions(SlabShape);
        SlabParams.Set_MotionType(ECk_MotionType::Static);

        _FloorBody = utils_jolt_body::Add(_FloorEntity, SlabParams);

        Assert_True(ck::IsValid(_FloorBody), "the slab's Jolt body must be valid");

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(float32(CellSizeUu), float32(CellHeightUu));
        Config.Set_TileSizeUu(float32(TileSizeUu));

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(float32(ProfileHalfHeightUu), float32(AgentRadius))));
        // The slab's own edges lie OUTSIDE the volume, but the field is clipped to the volume, so the
        // ledge filter would otherwise demote the whole perimeter and pinch the corridor the paint is
        // supposed to be the only thing narrowing.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(-VolumeHalfX, BandY - VolumeHalfY, VolumeFloorZ),
            FVector( VolumeHalfX, BandY + VolumeHalfY, VolumeCeilingZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        VolumeParams.Set_ProbeBudgetPerTick(ProbeBudgetPerTick);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid GroundNav volume handle");

        _PlannerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _PlannerEntity.Request_OverrideToSelf();
        _PlannerEntity.Set_DebugName(n"GroundNav_MarkupRace_Planner");

        auto PathParams = FCk_Fragment_GroundNavPath_ParamsData(float32(AgentRadius));
        PathParams.Set_VerticalToleranceUu(float32(CellHeightUu * 4.0));

        _Planner = utils_ground_nav_path::Add(_PlannerEntity, PathParams);

        Assert_True(ck::IsValid(_Planner), "Add() must return a valid GroundNav path handle");
    }

    UFUNCTION()
    private void Check_FloorBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_jolt_body::Get_IsBodyAdded(_FloorBody));
    }

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
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    //------------------------------------------------------------------------
    // Path episodes
    //------------------------------------------------------------------------

    private void Request_Route()
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

    // EVERY episode this fixture asked for has ended, not merely one more than last time. A second
    // FindPath supersedes the first and the superseded one completes as Failed_Cancelled, so a
    // condition counting a single further completion would fire on the cancellation and read the
    // slot before the episode that replaced it had answered.
    UFUNCTION()
    private void Check_PathAnswered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PathCompletions >= _PathRequests
            && utils_ground_nav_path::Get_HasFreshResult(_Planner));
    }

    UFUNCTION()
    private void Step_RequestBaselinePath(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Request_Route();
    }

    UFUNCTION()
    private void Step_AssertBaselineCrossesSpot(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_ground_nav_path::Get_Result(_Planner);

        _BaselineStatus = Result.Get_Status();
        _BaselineWaypoints = Result.Get_Waypoints();

        Assert_True(_BaselineStatus == ECk_GroundNav_PathStatus::Ready,
            f"the baseline route runs 1200uu down the middle of an unobstructed field, so it must be Ready (got {_BaselineStatus})");

        Assert_True(_BaselineWaypoints.Num() >= 1,
            f"a Ready route carries at least the goal it was planned to (got {_BaselineWaypoints.Num()})");

        const auto NearnessUu = Get_RouteDistanceTo(
            Get_RoutePolyline(_BaselineWaypoints), Get_FirstBlockCentre());

        ck::nav::Display(f"[MARKUP-RACE] baseline: status={_BaselineStatus} waypoints={_BaselineWaypoints.Num()} nearest approach to the spot={NearnessUu}uu");

        Assert_True(NearnessUu <= BaselineNearnessUu,
            f"the baseline route passes {NearnessUu}uu from the spot about to be painted (ceiling {BaselineNearnessUu}uu). A route that already detours cannot be pushed off by a paint, so the fixture would assert nothing.");
    }

    //------------------------------------------------------------------------
    // Phase 1 - the settled repath
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PaintAndRepathAtOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FirstMarkup = Paint_ImpassableBox(Get_FirstBlockCentre());

        _RevisionAtPaint = utils_nav_surface::Get_SurfaceRevision();

        // Deliberately in the same frame as the paint, and deliberately NOT read: this is the
        // caller behaviour the wait below exists to correct, kept so the fixture reproduces it
        // rather than describing it. The settled request supersedes this one.
        Request_Route();
    }

    private FCk_Handle_NavSurfaceMarkup Paint_ImpassableBox(FVector InCentre)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(BlockHalfXY, BlockHalfXY, BlockHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(FTransform(FRotator::ZeroRotator, InCentre, FVector::OneVector));

        auto Markup = utils_nav_surface::Request_ImpassableBox(Request);

        Assert_True(ck::IsValid(Markup),
            "Request_ImpassableBox hands back the handle the caller needs to observe and release the paint - an invalid one leaves the carve unreachable");

        // The markup entity is parented to the WORLD, not to this runner, so the harness's own
        // subtree teardown never reaches it - registering it here is what unpaints the carve.
        Track_ForCleanup(FCk_Handle(Markup));

        return Markup;
    }

    UFUNCTION()
    private void Check_FirstPaintIsLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _LivePolls += 1;

        const auto IsLive = utils_nav_surface::Get_IsMarkupLive(_FirstMarkup);

        // Taken at the FIRST poll that answers true and never overwritten: what the trace is about is
        // the state of the surface at the moment the wait let go, not at the moment it was read out.
        if (IsLive && _RevisionAtLive < 0)
        { _RevisionAtLive = utils_nav_surface::Get_SurfaceRevision(); }

        auto Res = OutResult;
        Res.Set(IsLive);
    }

    UFUNCTION()
    private void Step_RequestSettledPath(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        ck::nav::Display(f"[MARKUP-RACE] settled wait: revisionAtPaint={_RevisionAtPaint} revisionAtLive={_RevisionAtLive} framesWaited={_LivePolls}");

        Assert_True(utils_nav_surface::Get_IsMarkupLive(_FirstMarkup),
            "the wait resolved on Get_IsMarkupLive, so the facade must still report the paint live when the route is planned against it");

        Request_Route();
    }

    UFUNCTION()
    private void Step_AssertSettledPathAvoidsPaint(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_ground_nav_path::Get_Result(_Planner);

        _SettledStatus = Result.Get_Status();
        _SettledWaypoints = Result.Get_Waypoints();

        const auto SettledRoute = Get_RoutePolyline(_SettledWaypoints);
        const auto Standoff = Get_RouteDistanceTo(SettledRoute, Get_FirstBlockCentre());

        ck::nav::Display(f"[MARKUP-RACE] settled: status={_SettledStatus} waypoints={_SettledWaypoints.Num()} nearest approach to the paint={Standoff}uu");

        Assert_True(_SettledStatus == ECk_GroundNav_PathStatus::Ready,
            f"250uu of corridor is left on either side of the painted box, several times the {AgentRadius}uu body radius, so a settled route must still be Ready (got {_SettledStatus})");

        const auto BlockMin = Get_FirstBlockCentre() - Get_BlockHalfExtents();
        const auto BlockMax = Get_FirstBlockCentre() + Get_BlockHalfExtents();

        Assert_False(Get_RouteEntersBox(SettledRoute, BlockMin, BlockMax),
            f"a LEG of the route planned after Get_IsMarkupLive went true passes through the painted box. The paint reported itself live, so the field it was planned against had already applied it - the route crossing anyway means liveness is not the condition it claims to be. (status={_SettledStatus}, waypoints={_SettledWaypoints.Num()})");

        // A radius less one cell, for the reason in the header: the field promises a funnelled route
        // that standoff and no more, so a fuller inflation would assert a margin nothing undertook.
        const auto InflationUu = AgentRadius - CellSizeUu;
        const auto Inflation = FVector(InflationUu, InflationUu, 0.0);

        Assert_False(Get_AnyWaypointInsideBox(_SettledWaypoints, BlockMin - Inflation, BlockMax + Inflation),
            f"a waypoint of the settled route lies inside the painted box inflated by {InflationUu}uu, which is the standoff the clearance field admits a body of {AgentRadius}uu at. (nearest approach {Standoff}uu)");
    }

    //------------------------------------------------------------------------
    // Phase 2 - the unsettled repath, recorded and never asserted
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PaintSecondAndRepathAtOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _SecondMarkup = Paint_ImpassableBox(Get_SecondBlockCentre());

        Request_Route();
    }

    UFUNCTION()
    private void Step_ReportUnsettledCrossing(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_ground_nav_path::Get_Result(_Planner);

        _UnsettledStatus = Result.Get_Status();
        _UnsettledWaypoints = Result.Get_Waypoints();

        const auto BlockMin = Get_SecondBlockCentre() - Get_BlockHalfExtents();
        const auto BlockMax = Get_SecondBlockCentre() + Get_BlockHalfExtents();

        const auto Crossed = Get_RouteEntersBox(
            Get_RoutePolyline(_UnsettledWaypoints), BlockMin, BlockMax);
        const auto IsLive = utils_nav_surface::Get_IsMarkupLive(_SecondMarkup);

        ck::nav::Display(f"[MARKUP-RACE] unsettled path crossed={Crossed}");
        ck::nav::Display(f"[MARKUP-RACE] unsettled detail: status={_UnsettledStatus} waypoints={_UnsettledWaypoints.Num()} liveAtRead={IsLive}");
    }

    //------------------------------------------------------------------------
    // Fixture geometry helpers
    //------------------------------------------------------------------------

    private FVector Get_StartPoint()       { return FVector(StartX, BandY, SurfaceZ); }
    private FVector Get_GoalPoint()        { return FVector(GoalX, BandY, SurfaceZ); }
    private FVector Get_FirstBlockCentre() { return FVector(FirstBlockX, BandY, SurfaceZ); }
    private FVector Get_SecondBlockCentre(){ return FVector(SecondBlockX, BandY, SurfaceZ); }
    private FVector Get_BlockHalfExtents() { return FVector(BlockHalfXY, BlockHalfXY, BlockHalfZ); }

    //------------------------------------------------------------------------
    // Route geometry - answered here rather than by an engine helper, because
    // the questions are about SEGMENTS and AngelScript binds no segment-box
    // primitive. All three are exact: no sampling, no tolerance.
    //------------------------------------------------------------------------

    // The polyline the BODY actually walks: its own position, then the waypoints. GroundNav does not
    // repeat the start as a waypoint - the post-process drops the first one when the body already
    // stands on it - so a same-plate route publishes exactly the goal, and a leg test over the
    // waypoints alone would have no leg to test. Empty stays empty: prepending the start to a route
    // that answered nothing would manufacture a one-point route out of a failure.
    private TArray<FVector> Get_RoutePolyline(const TArray<FVector>& InWaypoints)
    {
        TArray<FVector> Polyline;

        if (InWaypoints.Num() == 0)
        { return Polyline; }

        Polyline.Add(Get_StartPoint());

        for (int32 Index = 0; Index < InWaypoints.Num(); Index++)
        { Polyline.Add(InWaypoints[Index]); }

        return Polyline;
    }

    private float Get_RouteDistanceTo(const TArray<FVector>& InRoute, FVector InPoint)
    {
        // A route with no points is infinitely far from everything, and answering zero would
        // report an empty answer as passing straight through whatever was asked about.
        if (InRoute.Num() == 0)
        { return NoRouteDistanceUu; }

        auto Nearest = (InRoute[0] - InPoint).Size();

        for (int32 Index = 1; Index < InRoute.Num(); Index++)
        {
            const auto Distance = Get_PointToSegmentDistance(
                InPoint, InRoute[Index - 1], InRoute[Index]);

            Nearest = Math::Min(Nearest, Distance);
        }

        return Nearest;
    }

    private float Get_PointToSegmentDistance(FVector InPoint, FVector InStart, FVector InEnd)
    {
        const auto Along = InEnd - InStart;
        const auto LengthSquared = Along.SizeSquared();

        if (LengthSquared <= 0.0)
        { return (InPoint - InStart).Size(); }

        const auto Alpha = Math::Clamp(
            (InPoint - InStart).DotProduct(Along) / LengthSquared, 0.0, 1.0);

        return (InPoint - (InStart + (Along * Alpha))).Size();
    }

    private bool Get_AnyWaypointInsideBox(const TArray<FVector>& InWaypoints, FVector InBoxMin, FVector InBoxMax)
    {
        for (int32 Index = 0; Index < InWaypoints.Num(); Index++)
        {
            if (Get_IsPointInsideBox(InWaypoints[Index], InBoxMin, InBoxMax))
            { return true; }
        }

        return false;
    }

    private bool Get_IsPointInsideBox(FVector InPoint, FVector InBoxMin, FVector InBoxMax)
    {
        return InPoint.X >= InBoxMin.X && InPoint.X <= InBoxMax.X
            && InPoint.Y >= InBoxMin.Y && InPoint.Y <= InBoxMax.Y
            && InPoint.Z >= InBoxMin.Z && InPoint.Z <= InBoxMax.Z;
    }

    // Whether any LEG of the route meets the box, not merely whether a point of it does. A funnelled
    // route over open ground is the body's position and a straight line to the goal, so a point test
    // alone would report a route driven clean through the box as clear of it.
    private bool Get_RouteEntersBox(const TArray<FVector>& InRoute, FVector InBoxMin, FVector InBoxMax)
    {
        for (int32 Index = 1; Index < InRoute.Num(); Index++)
        {
            if (Get_SegmentHitsBox(InRoute[Index - 1], InRoute[Index], InBoxMin, InBoxMax))
            { return true; }
        }

        return false;
    }

    private bool Get_SegmentHitsBox(FVector InStart, FVector InEnd, FVector InBoxMin, FVector InBoxMax)
    {
        const auto Direction = InEnd - InStart;

        float EntryAlpha = 0.0;
        float ExitAlpha = 1.0;

        for (int32 Axis = 0; Axis < 3; Axis++)
        {
            const auto Origin = Get_Component(InStart, Axis);
            const auto Delta = Get_Component(Direction, Axis);
            const auto SlabMin = Get_Component(InBoxMin, Axis);
            const auto SlabMax = Get_Component(InBoxMax, Axis);

            // Parallel to this pair of slabs: the segment either lies between them for its whole
            // length or misses the box outright, and there is no alpha range to narrow.
            if (Math::Abs(Delta) <= 0.000001)
            {
                if (Origin < SlabMin || Origin > SlabMax)
                { return false; }

                continue;
            }

            auto Near = (SlabMin - Origin) / Delta;
            auto Far = (SlabMax - Origin) / Delta;

            if (Near > Far)
            {
                const auto Held = Near;
                Near = Far;
                Far = Held;
            }

            EntryAlpha = Math::Max(EntryAlpha, Near);
            ExitAlpha = Math::Min(ExitAlpha, Far);

            if (EntryAlpha > ExitAlpha)
            { return false; }
        }

        return true;
    }

    private float Get_Component(FVector InVector, int32 InAxis)
    {
        if (InAxis == 0) { return InVector.X; }
        if (InAxis == 1) { return InVector.Y; }

        return InVector.Z;
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

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

        if (ck::IsValid(_PlannerEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_PlannerEntity);
            _PlannerEntity = FCk_Handle();
        }

        if (ck::IsValid(_VolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
            _VolumeEntity = FCk_Handle();
        }

        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}
