// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A REPUBLISH BESIDE A ROUTE LEAVES IT ALONE
//============================================================================
//
// The other half of the rebuild-then-repath contract. Its sibling
// CkAutoTest_GroundNav_Rebuild_InvalidatesWalkingRouteExactlyOnce pins that
// ground moving UNDER a walking route replans it; this pins that ground moving
// BESIDE one does not. Without both, an invalidator that simply flagged
// everything on every publish would pass the first test perfectly, and every
// agent in a level would replan every time any corner of it was repainted.
//
// The only thing standing between those two outcomes is
// FProcessor_GroundNavPath_InvalidateOnRebuilt's box intersection: the
// published changed bounds against the corridor the agent's plan cached,
// already inflated by the body radius plus kCorridorInflationMarginUu. This
// fixture puts the paint far enough away that the intersection is the whole
// answer.
//
// WHY THE PAINT IS A COST MARKUP AND NOT AN IMPASSABLE ONE. An impassable
// paint is a walkability change, and a walkability change re-bakes the WHOLE
// volume and publishes changed bounds that are the union of every tile in it -
// so it flags every corridor in the volume however far away it was painted,
// and there is no distance at which this test could pass. A cost paint is
// derived rather than re-baked: only the tiles the record actually reaches are
// restamped and carry the new epoch, so the published bounds are local to the
// paint and the box test is the only thing deciding anything.
//
// WHY THE FIELD EPOCH STILL MOVES, AND WHY THAT MATTERS. The invalidator has
// an earlier out than the box: a corridor whose epoch is not behind the field's
// is one no queued rebuild can be news to, and it is skipped whole. A cost
// derive bumps the field epoch, so that out does NOT fire here and the box
// intersection is left carrying the whole decision. That is what makes this
// the stronger of the two ways to write this test.
//
// WHY routeSwaps == 0 IS NOT VACUOUS. It is a negative - it would read true if
// nothing had happened at all - so it is asserted only behind two positives
// that prove the machinery ran: the paint reads LIVE on the surface (which for
// GroundNav means every tile it reaches republished past the epoch it was
// submitted against), and the neutral OnSurfaceRebuilt signal delivered at
// least one broadcast whose bounds this fixture captured and measured. The
// surface revision before and after the paint is logged for the same reason.
//
// HOW A ROUTE SWAP IS OBSERVED. Identically to the sibling test: a GroundNav
// plan installs through the agent's own FFragment_Nav_PathResult and broadcasts
// UUtils_Signal_Nav_OnPathReady, so one broadcast is one installed route, and
// the count is taken against a baseline latched at the paint.
//
// GEOMETRY. Tiles are 250 uu, so a plate is at most 250 uu across and the
// corridor of a route running down Y = BandY reaches at most one tile plus its
// inflation either side of it - 250 + 42 + 25 = 317 uu at the very worst tile
// phase. The painted box sits 900 uu off that line with a 125 uu half extent,
// so the tiles it reaches begin no nearer than 525 uu: over 200 uu of daylight
// past the 134 uu this fixture requires, which is 2 x (radius + margin).
//
// The volume is deliberately ASYMMETRIC about the walk - 400 uu of field on the
// near side and 1200 uu on the far side - so the room the paint needs is bought
// on one side only rather than doubling the tile count.
//
// FIXTURE. One Static JoltBody slab whose top sits at Z 0, overhanging the
// GroundNav volume on every horizontal side so no cliff edge exists inside the
// field, auto-build disabled so the bake waited on is the one asked for. A box
// shape is convex and therefore closed - an open mesh would trip the bake's
// OPEN COLLISION warning, and the harness escalates a Warning into a failure.
//
// The provider is per world and every other fixture in this map reads it, so
// the previous selection is captured before the swap and handed back both when
// this test concludes AND in DoEndPlay - every exit path, including the engine
// TimeLimit one, must put the world back. The rebuilt signal is a WORLD signal
// rather than an entity one, so the same teardown unbinds it.
//
// Isolated Y band: 134000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Rebuild_AdjacentPaintDoesNotReplan : UCk_AutoTest_Base
{
    // Wide enough that every wait below expires on its OWN budget and names the condition it was
    // on, rather than the harness's anonymous TimesUp arriving first.
    default _TimeoutSeconds = 120.0f;

    //------------------------------------------------------------------------
    // Fixture geometry
    //------------------------------------------------------------------------

    private const float BandY = 134000.0;

    // Asymmetric about the walk: the paint needs its room on the far side only.
    private const float VolumeNearY = -400.0;
    private const float VolumeFarY = 1200.0;
    private const float VolumeHalfX = 1100.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    // Overhangs the volume by 200 uu on every horizontal side, so the volume's interior never
    // contains a slab edge for the ledge filter to find.
    private const float SlabHalfX = 1300.0;
    private const float SlabHalfY = 1000.0;
    private const float SlabCentreY = 400.0;
    private const float SlabHalfZ = 50.0;

    private const float SurfaceZ = 0.0;
    private const float AgentCentreOffsetZ = 100.0;

    private const float SpawnX = -800.0;
    private const float GoalX = 800.0;

    // Where the agent has to have reached before the paint lands - mid-walk, unambiguously on an
    // installed route with most of the corridor still ahead of it.
    private const float PaintTriggerX = -400.0;

    // Beside the middle of the walk, on the far side. 900 uu of offset against a 125 uu half
    // extent puts the nearest tile the record reaches at 525 uu from the route.
    private const float PaintOffsetY = 900.0;
    private const float PaintHalfXY = 125.0;
    private const float PaintHalfZ = 200.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;

    // 250 uu, so a plate is at most 250 uu across. The whole point of the fixture: at the 500 uu
    // tiles the sibling test uses, one plate is wide enough that no paint inside the volume could
    // be placed clear of the corridor.
    private const float TileSizeUu = 250.0;

    private const int32 ProbeBudgetPerTick = 1;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;
    private const float ProfileHalfHeightUu = 96.0;

    // kCorridorInflationMarginUu, from CkGroundNavPath_Processor.cpp. Held here so the clearance
    // this fixture claims is stated in the same terms the invalidator measures in.
    private const float CorridorInflationMarginUu = 25.0;

    // The furthest a corridor found on a route down Y = BandY can reach off that line: one whole
    // tile, at the worst tile phase, plus what the plan inflated its box by.
    private float Get_CorridorReachUu()
    {
        return TileSizeUu + AgentRadius + CorridorInflationMarginUu;
    }

    // Twice the inflation, so the paint clears the corridor on both faces however the tile phase falls.
    private float Get_RequiredClearanceUu()
    {
        return 2.0 * (AgentRadius + CorridorInflationMarginUu);
    }

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 WalkingFrameBudget = 1800;
    private const int32 ProgressFrameBudget = 3600;
    private const int32 LiveFrameBudget = 3600;
    private const int32 ArrivalFrameBudget = 3600;

    //------------------------------------------------------------------------
    // Fixture handles
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _VolumeEntity;
    private FCk_Handle _AgentEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_GroundNavPath _Planner;
    private FCk_Handle_NavSurfaceMarkup _Markup;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;
    private bool _RebuiltBound = false;

    //------------------------------------------------------------------------
    // Episode bookkeeping
    //------------------------------------------------------------------------

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    private int32 _MarkupCompletions = 0;
    private bool _MarkupSucceeded = false;

    private int32 _PathReadyCount = 0;
    private int32 _PathReadyAtPaint = 0;
    private int32 _PathFailedCount = 0;

    private bool _Painted = false;
    private bool _Arrived = false;

    private int64 _RevisionBeforePaint = -1;
    private int64 _RevisionAfterPaint = -1;

    // What the neutral signal actually broadcast after the paint. Captured rather than assumed:
    // whether the published bounds stayed local to the paint is the property this test exists to
    // measure, and taking it from the signal is taking it from the same value the invalidator read.
    private int32 _RebuiltAfterPaint = 0;
    private FBox _LastChangedBounds;
    private bool _AnyChangedBoundsUnknown = false;
    private float _NearestChangedApproachUu = 0.0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage the floor and the volume",                     n"Step_BuildFixture");
        Add_Step_WaitUntil("the floor reaches the Jolt static world",            n"Check_FloorBodyAdded",        BodyFrameBudget);
        Add_Step(          "ask the volume to bake",                             n"Step_RequestBake");
        Add_Step_WaitUntil("the field reports itself built",                     n"Check_FieldBuilt",            BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",            n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles at Ready",                   n"Check_SurfaceSettled",        SurfaceFrameBudget);
        Add_Step(          "spawn the walker and send it down the corridor",     n"Step_SpawnAgent");
        Add_Step_WaitUntil("the walker is Walking an installed route",           n"Check_WalkingInstalledRoute", WalkingFrameBudget);
        Add_Step_WaitUntil("the walker has passed the paint trigger",            n"Check_PassedPaintTrigger",    ProgressFrameBudget);
        Add_Step(          "paint a cost area beside the route, never on it",    n"Step_PaintBesideRoute");
        Add_Step_WaitUntil("the paint is live on the surface",                   n"Check_PaintIsLive",           LiveFrameBudget);
        Add_Step(          "the republish reached ground the corridor does not", n"Step_AssertChangedBoundsAreLocal");
        Add_Step_WaitUntil("the walker reaches its goal",                        n"Check_WalkerArrived",         ArrivalFrameBudget);
        Add_Step(          "the walk was never replanned",                       n"Step_AssertNeverReplanned");
        Add_Step(          "hand the world back",                                n"Step_Cleanup");

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
            FTransform(FRotator::ZeroRotator,
                FVector(0.0, BandY + SlabCentreY, SurfaceZ - SlabHalfZ)),
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
        // ledge filter would otherwise demote the whole perimeter and pinch the corridor.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(-VolumeHalfX, BandY + VolumeNearY, VolumeFloorZ),
            FVector( VolumeHalfX, BandY + VolumeFarY,  VolumeCeilingZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        VolumeParams.Set_ProbeBudgetPerTick(ProbeBudgetPerTick);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid GroundNav volume handle");

        // Bound before anything can publish, so the count taken after the paint is a count of
        // broadcasts this fixture saw arrive rather than of broadcasts it happened to be listening
        // for. The signal is a WORLD signal, so Teardown unbinds it.
        utils_nav_surface::BindTo_OnSurfaceRebuilt(
            FCk_Delegate_NavSurface_OnSurfaceRebuilt(this, n"OnSurfaceRebuilt"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        _RebuiltBound = true;
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
            f"the world must report the provider it was told to plan on (got {ProviderNow})");
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    //------------------------------------------------------------------------
    // The walk
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SpawnAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Spawn = Get_SpawnPoint();
        const auto Goal = Get_GoalPoint();

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"GroundNav_AdjacentPaint_Walker");

        const auto Rot = (Goal - Spawn).Rotation();
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(Rot, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));
        _Agent = utils_crowd_agent::Add(AgentTransform, Params);

        Assert_True(ck::IsValid(_Agent), "Add() must return a valid crowd agent handle");

        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);

        // Composed here with the params the crowd's own GroundNav dispatch would have used, purely
        // so this fixture holds the typesafe handle: the dispatch adds the feature only when it is
        // missing, so what runs is identical either way.
        _Planner = utils_ground_nav_path::Add(_AgentEntity,
            FCk_Fragment_GroundNavPath_ParamsData(float32(AgentRadius)));

        Assert_True(ck::IsValid(_Planner), "Add() must return a valid GroundNav path handle");

        // One broadcast of OnPathReady through the agent's own shared nav slot is one installed
        // route, and that count is the whole of what this test calls a route swap.
        utils_nav::BindTo_OnPathReady(_AgentEntity,
            FCk_Delegate_Nav_OnPathReady(this, n"OnPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::BindTo_OnPathFailed(_AgentEntity,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalReached(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void OnPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _PathReadyCount += 1;
    }

    UFUNCTION()
    private void OnPathFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        _PathFailedCount += 1;
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }

        _Arrived = true;
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

        const auto RouteSwaps = Get_RouteSwapsAfterPaint();

        Teardown();
        FinishFailure(f"the walker reported OnGoalFailed on a straight, unobstructed 1600uu run whose only paint is a COST area 900uu off the route (painted={_Painted}, routeSwapsAfterPaint={RouteSwaps}, pathFailures={_PathFailedCount})");
    }

    UFUNCTION()
    private void Check_WalkingInstalledRoute(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PathReadyCount >= 1
            && utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking);
    }

    UFUNCTION()
    private void Check_PassedPaintTrigger(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Get_AgentLocation().X >= PaintTriggerX
            && utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking);
    }

    //------------------------------------------------------------------------
    // The paint
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PaintBesideRoute(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Stated against the numbers the invalidator measures in, and asserted rather than
        // commented: a later edit that widens the tile or moves the box would otherwise turn this
        // fixture into one that passes because the paint was never far enough away to matter.
        const auto ClearanceUu = PaintOffsetY - PaintHalfXY - TileSizeUu - Get_CorridorReachUu();

        Assert_True(ClearanceUu >= Get_RequiredClearanceUu(),
            f"the nearest tile the paint can reach must clear the furthest the route's corridor can reach by at least 2x (radius + corridor margin) = {Get_RequiredClearanceUu()}uu, or the box test this fixture exists to pin is not the thing deciding the outcome (clearance {ClearanceUu}uu)");

        _RevisionBeforePaint = utils_nav_surface::Get_SurfaceRevision();

        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(PaintHalfXY, PaintHalfXY, PaintHalfZ))),
            utils_gameplay_tag::ResolveGameplayTag(n"Nav.Area.Restricted"));
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_PaintCentre(), FVector::OneVector));

        _Markup = utils_nav_surface::Request_AreaMarkup(
            Request, FCk_Delegate_Request_OnCompleted(this, n"OnMarkupCompleted"));

        Assert_True(ck::IsValid(_Markup),
            "Request_AreaMarkup hands back the handle the caller needs to observe and release the paint - an invalid one leaves the carve unreachable");

        // The markup entity is parented to the WORLD, not to this runner, so the harness's own
        // subtree teardown never reaches it - registering it here is what unpaints the carve.
        Track_ForCleanup(FCk_Handle(_Markup));

        _Painted = true;
        _PathReadyAtPaint = _PathReadyCount;
    }

    UFUNCTION()
    private void OnMarkupCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _MarkupCompletions += 1;
        _MarkupSucceeded = InResult == ECk_Request_OperationResult::Succeeded;
    }

    UFUNCTION()
    private void OnSurfaceRebuilt(FCk_Handle InWorldEntity, FBox InChangedBounds)
    {
        if (IsFinished()) { return; }
        if (_Painted == false) { return; }

        _RebuiltAfterPaint += 1;
        _LastChangedBounds = InChangedBounds;

        // A publisher that did not know WHERE it rebuilt sends an invalid box, and the invalidator
        // reads that as reaching everything. Recorded rather than skipped: it is the one payload
        // under which a zero swap count would mean nothing at all.
        if (!InChangedBounds.IsValid)
        {
            _AnyChangedBoundsUnknown = true;
            return;
        }

        const auto ApproachUu = Get_ApproachToRouteBandUu(InChangedBounds);

        if (_RebuiltAfterPaint == 1 || ApproachUu < _NearestChangedApproachUu)
        { _NearestChangedApproachUu = ApproachUu; }
    }

    UFUNCTION()
    private void Check_PaintIsLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto IsLive = utils_nav_surface::Get_IsMarkupLive(_Markup);

        // Taken at the FIRST poll that answers true and never overwritten: the trace is about the
        // state of the surface at the moment the wait let go, not at the moment it was read out.
        if (IsLive && _RevisionAfterPaint < 0)
        { _RevisionAfterPaint = utils_nav_surface::Get_SurfaceRevision(); }

        auto Res = OutResult;
        Res.Set(IsLive);
    }

    //------------------------------------------------------------------------
    // The positives - what makes the negative below worth asserting
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertChangedBoundsAreLocal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        ck::nav::Display(f"[REBUILD-REPLAN-TEST] adjacent paint: revisionBeforePaint={_RevisionBeforePaint} revisionAfterPaint={_RevisionAfterPaint} rebuiltBroadcasts={_RebuiltAfterPaint} nearestChangedApproachToRouteBand={_NearestChangedApproachUu}uu");

        Assert_Equals_Int(_MarkupCompletions, 1,
            f"a request completion is a fire-exactly-once guarantee (got {_MarkupCompletions})");
        Assert_True(_MarkupSucceeded,
            "Nav.Area.Restricted is a registered cost area and the box has extent, so the paint must be accepted");

        Assert_True(_RevisionAfterPaint > _RevisionBeforePaint,
            f"the cost derive must republish the tiles the paint reaches, so the surface revision has to advance across it (was {_RevisionBeforePaint}, now {_RevisionAfterPaint}). Without a publish there is no rebuild for the invalidator to have ignored, and the zero swap count below would pass vacuously.");

        Assert_True(_RebuiltAfterPaint >= 1,
            f"the neutral OnSurfaceRebuilt signal must have delivered the publish this fixture is measuring (got {_RebuiltAfterPaint} broadcasts after the paint)");

        Assert_False(_AnyChangedBoundsUnknown,
            "a publish after the paint carried an INVALID changed-bounds box, which the invalidator reads as reaching every corridor in the world. A cost derive knows exactly which tiles it restamped, so bounds-unknown here means the publish lost that knowledge and the box test below could not have decided anything.");

        Assert_True(_NearestChangedApproachUu >= Get_RequiredClearanceUu(),
            f"the ground this republish was news about came within {_NearestChangedApproachUu}uu of the band the walking route's corridor can reach, under the {Get_RequiredClearanceUu()}uu this fixture is built to hold clear. A cost derive republishes only the tiles the record reaches, so bounds this near the route mean the derive restamped tiles the paint never touched.");
    }

    UFUNCTION()
    private void Check_WalkerArrived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Arrived);
    }

    //------------------------------------------------------------------------
    // The negative
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertNeverReplanned(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto RouteSwaps = Get_RouteSwapsAfterPaint();
        const auto ChangedBoundsLocal = _AnyChangedBoundsUnknown == false
            && _NearestChangedApproachUu >= Get_RequiredClearanceUu();

        ck::nav::Display(f"[REBUILD-REPLAN-TEST] routeSwaps={RouteSwaps} changedBoundsLocal={ChangedBoundsLocal}");
        ck::nav::Display(f"[REBUILD-REPLAN-TEST] adjacent detail: revisionBeforePaint={_RevisionBeforePaint} revisionAfterPaint={_RevisionAfterPaint} rebuiltBroadcasts={_RebuiltAfterPaint} lastChangedBounds min {_LastChangedBounds.Min} max {_LastChangedBounds.Max} arrived={_Arrived}");

        Assert_True(_Arrived,
            "the walker must have reached its goal - the arrival is what proves the route it kept was still a route, rather than one it was never able to finish");

        Assert_Equals_Int(RouteSwaps, 0,
            f"a republish whose changed bounds never came within {Get_RequiredClearanceUu()}uu of the route's corridor must not replan the agent walking it, yet {RouteSwaps} replacement route(s) were installed after the paint. The publish DID happen and its bounds WERE local - both asserted above - so a swap here is the invalidator flagging a corridor no rebuilt ground reached, which would replan every agent in a level on every paint anywhere in it.");

        Assert_Equals_Int(_PathFailedCount, 0,
            f"a cost area 900uu off the route must not make the route unplannable (got {_PathFailedCount} plan failures)");
    }

    //------------------------------------------------------------------------
    // Fixture geometry helpers
    //------------------------------------------------------------------------

    private FVector Get_SpawnPoint()  { return FVector(SpawnX, BandY, SurfaceZ + AgentCentreOffsetZ); }
    private FVector Get_GoalPoint()   { return FVector(GoalX,  BandY, SurfaceZ + AgentCentreOffsetZ); }
    private FVector Get_PaintCentre() { return FVector(0.0, BandY + PaintOffsetY, SurfaceZ); }

    private FVector Get_AgentLocation()
    {
        if (ck::Is_NOT_Valid(_AgentEntity))
        { return Get_SpawnPoint(); }

        return utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(_AgentEntity));
    }

    private int32 Get_RouteSwapsAfterPaint()
    {
        return _PathReadyCount - _PathReadyAtPaint;
    }

    // How far a published box stays clear of the band the walking route's corridor can reach. The
    // corridor itself is not readable from AngelScript, so the band is derived from the fixture's
    // own geometry: the route runs down Y = BandY and a corridor found on it reaches at most one
    // tile plus its inflation either side. Zero where the box overlaps that band at all.
    private float Get_ApproachToRouteBandUu(FBox InBounds)
    {
        const auto Reach = Get_CorridorReachUu();

        const auto BandMinY = BandY - Reach;
        const auto BandMaxY = BandY + Reach;

        if (InBounds.Min.Y > BandMaxY)
        { return InBounds.Min.Y - BandMaxY; }

        if (InBounds.Max.Y < BandMinY)
        { return BandMinY - InBounds.Max.Y; }

        return 0.0;
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. Two things here outlive this
    // test's own subtree: the provider is a WORLD selection every later fixture in this map reads,
    // and OnSurfaceRebuilt is a WORLD signal that would keep calling into a finished script.
    private void Teardown()
    {
        if (_RebuiltBound)
        {
            _RebuiltBound = false;
            utils_nav_surface::UnbindFrom_OnSurfaceRebuilt(
                FCk_Delegate_NavSurface_OnSurfaceRebuilt(this, n"OnSurfaceRebuilt"));
        }

        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_AgentEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_AgentEntity);
            _AgentEntity = FCk_Handle();
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
