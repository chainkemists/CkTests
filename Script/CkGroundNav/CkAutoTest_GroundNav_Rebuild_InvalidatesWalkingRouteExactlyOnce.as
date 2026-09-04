// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A REBUILD UNDER A WALKING ROUTE REPLANS IT ONCE
//============================================================================
//
// The rebuild-then-repath contract, end to end. An agent is walking a route
// GroundNav planned. An impassable box is painted ON the ground still ahead of
// it. The volume rebuilds, republishes, and the publish is broadcast as a
// neutral OnSurfaceRebuilt carrying the ground it changed;
// FProcessor_GroundNavPath_InvalidateOnRebuilt compares that ground against the
// corridor the agent's last plan cached and raises
// FTag_GroundNavPath_RepathRequired on it; the crowd's path refresh consumes
// that flag, replans in Repair mode, and installs the answer through the SAME
// shared nav slot a first plan installs through.
//
// Three things are asserted, and they are the whole contract:
//
//   1. EXACTLY ONE route swap follows the paint. Not zero - the news reached
//      the agent. Not two - a flag raised once must not be answered twice, and
//      a burst of overlapping rebuild boxes is one flag by construction.
//   2. The agent never leaves Walking between the paint and the arrival. A
//      repath that drops the agent to Idle or PathPending is a visible stall;
//      the point of a repair is that the body keeps moving while it happens.
//   3. The route it ends up walking does not pass through the painted box.
//
// HOW A ROUTE SWAP IS OBSERVED. AngelScript cannot read the log, so the
// [REBUILD-REPLAN] line the crowd emits is not available to this fixture.
// What IS observable is the install itself: a GroundNav plan is installed
// through the agent's own FFragment_Nav_PathResult and broadcasts
// UUtils_Signal_Nav_OnPathReady, exactly as a Recast plan does - which is the
// same signal CkAutoTest_Crowd_GroundNav_WalksInstalledRoute counts to prove a
// walk was fed by exactly one route. One OnPathReady IS one route swap, and
// counting them after the paint is a count this test owns end to end rather
// than a number read back out of the system under test. The GroundNav result's
// own PlannedAgainstEpoch and RepairVerdict are recorded alongside it and
// logged, never asserted: they corroborate WHICH plan was installed without
// making the pin depend on the search's internal verdict vocabulary.
//
// WHY THE PIN IS ONLY REAL WITH THE GATE. Assertion 1 must FAIL under
// ck.GroundNav.Debug.RepathOnRebuild 0, which makes the invalidator flag
// nobody: with no flag there is no replan, the swap count after the paint is
// zero, and the route the agent finishes on is the straight one it started on,
// through the box. Assertion 1 is checked first so the bypass names the
// invalidation rather than the geometry.
//
// WHY THE BAKE IS SLICED TO ONE TILE A TICK. The window this test is about is
// the one between the paint and the republish - the frames in which the agent
// must keep walking on a route that is already known to be stale. At the
// default probe budget the whole volume re-bakes inside one frame and there is
// no window to observe. A budget of one probe admits exactly one tile per tick,
// so the fifteen tiles of this fixture span fifteen slices.
//
// FIXTURE. One Static JoltBody slab whose top sits at Z 0, overhanging the
// GroundNav volume on every horizontal side so no cliff edge exists inside the
// field, auto-build disabled so the bake waited on is the one asked for. A box
// shape is convex and therefore closed - an open mesh would trip the bake's
// OPEN COLLISION warning, and the harness escalates a Warning into a failure.
// The volume is 2200 x 1400 uu with the walk running 1600 uu down its middle,
// leaving 300 uu of margin at each end and 550 uu of corridor either side of
// the painted box - many times the 42 uu body radius, so a detour exists and
// the paint is the only thing that narrows anything.
//
// The GroundNavPath feature is added to the agent by this fixture rather than
// left to the crowd's own dispatch, with the same params the crowd would have
// used (FCk_Fragment_GroundNavPath_ParamsData{radius}). The crowd composes it
// only if it is missing, so pre-adding changes nothing about what runs - it is
// what gives this test the typesafe handle it needs to read the plan's epoch
// and repair verdict back.
//
// The provider is per world and every other fixture in this map reads it, so
// the previous selection is captured before the swap and handed back both when
// this test concludes AND in DoEndPlay - every exit path, including the engine
// TimeLimit one, must put the world back.
//
// Isolated Y band: 132000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Rebuild_InvalidatesWalkingRouteExactlyOnce : UCk_AutoTest_Base
{
    // Wide enough that every wait below expires on its OWN budget and names the condition it was
    // on, rather than the harness's anonymous TimesUp arriving first.
    default _TimeoutSeconds = 120.0f;

    //------------------------------------------------------------------------
    // Fixture geometry
    //------------------------------------------------------------------------

    private const float BandY = 132000.0;

    private const float SlabHalfX = 1300.0;
    private const float SlabHalfY = 900.0;
    private const float SlabHalfZ = 50.0;

    private const float VolumeHalfX = 1100.0;
    private const float VolumeHalfY = 700.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float SurfaceZ = 0.0;
    private const float AgentCentreOffsetZ = 100.0;

    private const float SpawnX = -800.0;
    private const float GoalX = 800.0;

    // Where the agent has to have reached before the paint lands. Far enough along that it is
    // unambiguously Walking on an installed route, and far enough short of the box that the
    // rebuild has hundreds of uu of travel to complete in.
    private const float PaintTriggerX = -400.0;

    // On the straight line between the ends, so the route being walked crosses it, and 350 uu
    // past the trigger so the body cannot reach it before the volume has republished.
    private const float BlockX = 300.0;

    private const float BlockHalfXY = 150.0;
    private const float BlockHalfZ = 200.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 500.0;

    // 2200 x 1400 uu of volume at 500 uu tiles is a 5 x 3 lattice. The budget gates whether the
    // NEXT tile starts and a tile is never split, so one probe buys exactly one tile a tick.
    private const int32 ProbeBudgetPerTick = 1;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;
    private const float ProfileHalfHeightUu = 96.0;

    // How near the goal the walker has to be for a non-Walking frame to be read as the arrival
    // rather than as a stall. The arrival flips the agent out of Walking and OnGoalReached is a
    // signal, so which of the two an observer sees first on that one frame is not ordered; this
    // makes the count immune to it. A stall caused by a repath happens where the paint is, more
    // than a thousand uu from the goal, so nothing this exists to catch can hide inside it.
    private const float ArrivalExclusionUu = 200.0;

    // What was measured between the paint reading live and the replacement route
    // installing. LOGGED against, never asserted: how many passes an effect needs is a property
    // of processor ordering, and pinning it here would make an ordering change read as a defect.
    private const int32 MeasuredFramesFromLiveToNewRoute = 2;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 3600;
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

    //------------------------------------------------------------------------
    // Episode bookkeeping
    //------------------------------------------------------------------------

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    private int32 _PathReadyCount = 0;
    private int32 _PathReadyAtPaint = 0;
    private int32 _PathFailedCount = 0;

    private bool _Painted = false;
    private bool _Arrived = false;

    // The route the LAST install put in the shared nav slot, and where the body stood when it
    // landed. Both are needed together: GroundNav drops the first waypoint when the body already
    // stands on it, so the origin is what makes the first leg a leg at all.
    private TArray<FVector> _LastRouteWaypoints;
    private FVector _LastRouteOrigin = FVector::ZeroVector;

    // Non-Walking frames observed between the paint and the arrival. The terminal state the
    // arrival itself puts the agent in is excluded: _Arrived is set by OnGoalReached and every
    // observation is gated on it, so the frame the walk ENDS on is never counted against it.
    private int32 _NonWalkingFramesAfterPaint = 0;
    private ECk_CrowdAgent_MovementState _FirstNonWalkingState = ECk_CrowdAgent_MovementState::None;

    // One monotonic count of observed frames since the paint. Every stamp below is an index into
    // it, so two stamps can be subtracted whatever order they arrived in.
    private int32 _FramesSincePaint = 0;
    private int32 _FrameAtLive = -1;
    private int32 _FrameAtFirstSwap = -1;

    private int64 _RevisionAtPaint = -1;
    private int64 _RevisionAtLive = -1;

    private int64 _EpochAtPaint = 0;
    private int64 _EpochAtSwap = 0;
    private ECk_GroundNav_RepairVerdict _VerdictAtSwap = ECk_GroundNav_RepairVerdict::None;

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
        Add_Step_WaitUntil("the floor reaches the Jolt static world",            n"Check_FloorBodyAdded",      BodyFrameBudget);
        Add_Step(          "ask the volume to bake",                             n"Step_RequestBake");
        Add_Step_WaitUntil("the field reports itself built",                     n"Check_FieldBuilt",          BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",            n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles at Ready",                   n"Check_SurfaceSettled",      SurfaceFrameBudget);
        Add_Step(          "spawn the walker and send it down the corridor",     n"Step_SpawnAgent");
        Add_Step_WaitUntil("the walker is Walking an installed route",           n"Check_WalkingInstalledRoute", WalkingFrameBudget);
        Add_Step_WaitUntil("the walker has passed the paint trigger",            n"Check_PassedPaintTrigger",  ProgressFrameBudget);
        Add_Step(          "paint the ground still ahead of the walker",         n"Step_PaintAheadOfWalker");
        Add_Step_WaitUntil("the paint is live on the surface",                   n"Check_PaintIsLive",         LiveFrameBudget);
        Add_Step(          "record the surface state the wait let go on",        n"Step_RecordLive");
        Add_Step_WaitUntil("the walker reaches its goal",                        n"Check_WalkerArrived",       ArrivalFrameBudget);
        Add_Step(          "the rebuild replanned the walk exactly once",        n"Step_AssertReplannedOnce");
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
        _AgentEntity.Set_DebugName(n"GroundNav_RebuildReplan_Walker");

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

        // The nav signals live on the agent's own entity - the shared slot the GroundNav install
        // writes through is that entity's FFragment_Nav_PathResult, and one broadcast of
        // OnPathReady is one installed route.
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

        _LastRouteWaypoints = InResult.Get_Waypoints();
        _LastRouteOrigin = Get_AgentLocation();

        const auto PlanResult = utils_ground_nav_path::Get_Result(_Planner);

        if (_Painted && _FrameAtFirstSwap < 0)
        {
            _FrameAtFirstSwap = _FramesSincePaint;
            _EpochAtSwap = PlanResult.Get_PlannedAgainstEpoch();
            _VerdictAtSwap = PlanResult.Get_RepairVerdict();
        }
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

        Teardown();
        FinishFailure(f"the walker reported OnGoalFailed on a field whose only obstruction leaves 550uu of corridor either side of it (painted={_Painted}, routeSwapsAfterPaint={Get_RouteSwapsAfterPaint()}, pathFailures={_PathFailedCount})");
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
    // The paint, and everything observed from it onward
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PaintAheadOfWalker(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto WalkerAt = Get_AgentLocation();
        const auto RouteAtPaint = Get_RoutePolyline(WalkerAt, _LastRouteWaypoints);

        Assert_True(Get_RouteEntersBox(RouteAtPaint, Get_BlockMin(), Get_BlockMax()),
            f"the route the walker is on when the paint lands must pass through the ground about to be painted - a route that already misses it cannot be pushed off by a rebuild, so the fixture would assert nothing. (walker at {WalkerAt}, waypoints {_LastRouteWaypoints.Num()})");

        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(BlockHalfXY, BlockHalfXY, BlockHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_BlockCentre(), FVector::OneVector));

        _Markup = utils_nav_surface::Request_ImpassableBox(Request);

        Assert_True(ck::IsValid(_Markup),
            "Request_ImpassableBox hands back the handle the caller needs to observe and release the paint - an invalid one leaves the carve unreachable");

        // The markup entity is parented to the WORLD, not to this runner, so the harness's own
        // subtree teardown never reaches it - registering it here is what unpaints the carve.
        Track_ForCleanup(FCk_Handle(_Markup));

        _Painted = true;
        _PathReadyAtPaint = _PathReadyCount;
        _RevisionAtPaint = utils_nav_surface::Get_SurfaceRevision();
        _EpochAtPaint = utils_ground_nav_path::Get_Result(_Planner).Get_PlannedAgainstEpoch();

        Do_ObserveFrame();
    }

    UFUNCTION()
    private void Check_PaintIsLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_ObserveFrame();

        const auto IsLive = utils_nav_surface::Get_IsMarkupLive(_Markup);

        // Taken at the FIRST poll that answers true and never overwritten: what the trace is about
        // is the state of the surface at the moment the wait let go, not at the moment it was read.
        if (IsLive && _FrameAtLive < 0)
        {
            _FrameAtLive = _FramesSincePaint;
            _RevisionAtLive = utils_nav_surface::Get_SurfaceRevision();
        }

        auto Res = OutResult;
        Res.Set(IsLive);
    }

    UFUNCTION()
    private void Step_RecordLive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_ObserveFrame();

        ck::nav::Display(f"[REBUILD-REPLAN-TEST] paint: revisionAtPaint={_RevisionAtPaint} revisionAtLive={_RevisionAtLive} framesFromPaintToLive={_FrameAtLive} epochAtPaint={_EpochAtPaint}");
    }

    UFUNCTION()
    private void Check_WalkerArrived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_ObserveFrame();

        auto Res = OutResult;
        Res.Set(_Arrived);
    }

    // Every frame from the paint to the arrival passes through here: the two waits either side of
    // the live condition poll it, and the steps between them call it once so no frame the
    // sequencer spends between waits goes unobserved.
    private void Do_ObserveFrame()
    {
        if (_Arrived) { return; }
        if (ck::Is_NOT_Valid(_Agent)) { return; }

        _FramesSincePaint += 1;

        const auto State = utils_crowd_agent::Get_MovementState(_Agent);
        const auto DistanceToGoalUu = (Get_AgentLocation() - Get_GoalPoint()).Size();

        if (State != ECk_CrowdAgent_MovementState::Walking && DistanceToGoalUu > ArrivalExclusionUu)
        {
            if (_NonWalkingFramesAfterPaint == 0)
            { _FirstNonWalkingState = State; }

            _NonWalkingFramesAfterPaint += 1;
        }
    }

    //------------------------------------------------------------------------
    // The contract
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertReplannedOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto RouteSwaps = Get_RouteSwapsAfterPaint();

        // -1 wherever one of the two stamps never landed. A replan that installed BEFORE the paint
        // read live is a negative here, and that is a legitimate reading rather than an error: the
        // publish that made the paint live is the same publish the invalidator flagged on.
        int32 FramesFromLive = -1;

        if (_FrameAtFirstSwap >= 0 && _FrameAtLive >= 0)
        { FramesFromLive = _FrameAtFirstSwap - _FrameAtLive; }

        ck::nav::Display(f"[REBUILD-REPLAN-TEST] routeSwaps={RouteSwaps} framesFromLiveToNewRoute={FramesFromLive} (measured {MeasuredFramesFromLiveToNewRoute})");
        ck::nav::Display(f"[REBUILD-REPLAN-TEST] plan: epochAtPaint={_EpochAtPaint} epochAtSwap={_EpochAtSwap} repairVerdict={_VerdictAtSwap} nonWalkingFrames={_NonWalkingFramesAfterPaint} observedFrames={_FramesSincePaint}");

        // First, because this is the half that fails under ck.GroundNav.Debug.RepathOnRebuild 0:
        // with the invalidator flagging nobody there is no replan, and every geometric assertion
        // below would fail for a reason that names the route rather than the invalidation.
        Assert_True(_VerdictAtSwap != ECk_GroundNav_RepairVerdict::None,
            f"the replacement route must come from a repair plan, the route the invalidation re-issued - a cold plan means something else re-planned the walk (verdict {_VerdictAtSwap})");

        Assert_Equals_Int(RouteSwaps, 1,
            f"an impassable paint on the ground still ahead of a walking agent must republish the volume, meet the corridor that agent's plan cached, and install exactly ONE replacement route (got {RouteSwaps} route swaps after the paint, {_PathFailedCount} plan failures). Zero means the news never reached the agent - which is what ck.GroundNav.Debug.RepathOnRebuild 0 produces on purpose. More than one means a flag raised once was answered twice.");

        Assert_Equals_Int(_NonWalkingFramesAfterPaint, 0,
            f"the walker left Walking on {_NonWalkingFramesAfterPaint} of the {_FramesSincePaint} frames observed between the paint and the arrival (first seen in {_FirstNonWalkingState}). A repair replans the route the body is already on; dropping to Idle or PathPending to do it is the visible stall the whole mechanism exists to avoid.");

        const auto FinalRoute = Get_RoutePolyline(_LastRouteOrigin, _LastRouteWaypoints);

        Assert_False(Get_RouteEntersBox(FinalRoute, Get_BlockMin(), Get_BlockMax()),
            f"a LEG of the route the walker finished on passes through the painted box. The volume republished and the agent took a new route, so the field that route was planned against had already applied the paint - crossing anyway means the replan was planned against the field the rebuild replaced. (routeSwaps={RouteSwaps}, waypoints={_LastRouteWaypoints.Num()}, epochAtSwap={_EpochAtSwap})");
    }

    //------------------------------------------------------------------------
    // Fixture geometry helpers
    //------------------------------------------------------------------------

    private FVector Get_SpawnPoint()  { return FVector(SpawnX, BandY, SurfaceZ + AgentCentreOffsetZ); }
    private FVector Get_GoalPoint()   { return FVector(GoalX,  BandY, SurfaceZ + AgentCentreOffsetZ); }
    private FVector Get_BlockCentre() { return FVector(BlockX, BandY, SurfaceZ); }

    private FVector Get_BlockHalfExtents() { return FVector(BlockHalfXY, BlockHalfXY, BlockHalfZ); }
    private FVector Get_BlockMin() { return Get_BlockCentre() - Get_BlockHalfExtents(); }
    private FVector Get_BlockMax() { return Get_BlockCentre() + Get_BlockHalfExtents(); }

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

    //------------------------------------------------------------------------
    // Route geometry - answered here rather than by an engine helper, because
    // the questions are about SEGMENTS and AngelScript binds no segment-box
    // primitive. Exact: no sampling, no tolerance.
    //------------------------------------------------------------------------

    // The polyline the BODY actually walks: where it stood when the route was installed, then the
    // waypoints. GroundNav does not repeat the start as a waypoint - the post-process drops the
    // first one when the body already stands on it - so a leg test over the waypoints alone can
    // have no leg to test. Empty stays empty: prepending an origin to a route that answered
    // nothing would manufacture a one-point route out of a failure.
    private TArray<FVector> Get_RoutePolyline(FVector InOrigin, const TArray<FVector>& InWaypoints)
    {
        TArray<FVector> Polyline;

        if (InWaypoints.Num() == 0)
        { return Polyline; }

        Polyline.Add(InOrigin);

        for (int32 Index = 0; Index < InWaypoints.Num(); Index++)
        { Polyline.Add(InWaypoints[Index]); }

        return Polyline;
    }

    // Whether any LEG of the route meets the box, not merely whether a point of it does. A
    // funnelled route over open ground is the body's position and a straight line to the goal, so
    // a point test alone would report a route driven clean through the box as clear of it.
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

    // Idempotent, and called from BOTH the conclusion and DoEndPlay: the provider is a WORLD
    // selection every later fixture in this map reads, so leaving it on GroundNav would silently
    // re-provider the rest of the lane.
    private void Teardown()
    {
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
