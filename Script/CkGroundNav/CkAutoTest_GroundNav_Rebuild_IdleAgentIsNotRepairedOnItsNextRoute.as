// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A LATCHED REBUILD FLAG DOES NOT REPAIR THE NEXT ROUTE
//============================================================================
//
// The other half of the rebuild-then-repath contract - the half about the
// agent that was NOT walking when the rebuild landed.
//
// FProcessor_GroundNavPath_InvalidateOnRebuilt raises
// FTag_GroundNavPath_RepathRequired on every agent whose LAST-PLANNED corridor
// a publish reaches. It has no movement gate and needs none: it is answering
// "did the ground under this plan move", and that question has an answer
// whatever the body is doing. Its only consumer is the [REBUILD-REPLAN] block
// at the top of FProcessor_CrowdAgent_PathRefresh, and that processor's view
// REQUIRES FTag_CrowdAgent_Walking - so an agent that has ARRIVED when the
// publish lands never reaches the consumer and the flag simply LATCHES on it.
// GroundNav raises the flag and never clears it.
//
// A latched flag is harmless right up until that agent is told to walk again.
// Its next MoveTo dispatches a fresh plan against the field as published NOW;
// the plan installs, the agent becomes Walking, and on the very next pass
// PathRefresh - which can finally see the row - reads the stale flag and
// dispatches a "repair" of the route that was installed one frame ago. The
// repair re-plans the SAME goal against the SAME epoch, so the install seam's
// dedup guard (CkCrowdAgent_OnGroundNavPathResolved_Processor.cpp: same
// PlannedAgainstEpoch, goal within 25 uu, nothing pending) drops the answer -
// and MarkPathPending has already parked the nav slot at Pending with no tag
// transition. Nothing ever installs over that, so the slot stays Pending for
// the rest of the episode: an agent reading Walking with a parked slot, which
// before the Steering repair-in-flight allowance meant a zero desired velocity
// and a body frozen on the spot until a DIFFERENT goal was requested.
//
// THE FIX THIS PINS. Request_NavigationPath's GroundNav branch removes
// FTag_GroundNavPath_RepathRequired immediately after it parks the slot
// (CkCrowdAgent_HandleRequests_Processor.cpp): a plan made against the field as
// published now cannot owe a repair to the corridor it replaces. A publish that
// lands BETWEEN that dispatch and its install re-raises the flag against the
// still-installed corridor, and the repair consumer takes THAT one - so the
// clear costs the mechanism nothing it was built to do.
//
// WHAT IS ASSERTED, and why each half is here:
//
//   1. EXACTLY ONE route install follows the second MoveTo. A repair whose
//      answer was NOT deduped would install a second route over a route one
//      frame old.
//   2. NOT ONE frame between the second MoveTo and the arrival has the agent
//      Walking on a nav slot that reads Pending. This is the assertion the
//      defect fails: with the dispatch-time clear reverted, the repair parks
//      the slot and the dedup drops its answer, so every frame from the repair
//      to the arrival is Walking-on-Pending. The wait ahead of it - "the nav
//      slot reads Ready under the walking body" - is the POSITIVE that makes
//      the silence mean something, and it is the wait the defect expires when
//      PathRefresh gets its pass in before the first poll.
//   3. The body ADVANCES off the near goal. Carried by its own named wait
//      rather than by an assertion: a wait that runs out of polls fails naming
//      the condition, and this is the one the frozen-walker symptom expires.
//   4. The walker REACHES the far goal. Same - carried by its named wait.
//
// The measured values behind all four are reported on one Display line so a
// green run still says what it saw.
//
// WHY THE PAINT GOES BEHIND THE WALKER. The flag is raised against the LAST
// corridor, and after the arrival that is the corridor of the walk just
// finished. Painting on ground the agent has already crossed is therefore the
// shortest path to a latched flag - and it is also the only paint that leaves
// the SECOND route untouched, which is what makes a repair of that route
// unambiguously spurious rather than a legitimate answer to moved ground. The
// box's near face is 200 uu behind where the body stands and the far goal is
// 900 uu the other way; the fixture asserts BOTH halves of that (the first
// route crosses the box, the finished second route does not) so a geometry
// drift cannot quietly turn this into a test of nothing.
//
// FIXTURE. The sibling fixture, unchanged in shape: one Static JoltBody slab
// whose top sits at Z 0, overhanging the GroundNav volume on every horizontal
// side so no cliff edge exists inside the field, auto-build disabled so the
// bake waited on is the one asked for. A box shape is convex and therefore
// closed - an open mesh would trip the bake's OPEN COLLISION warning, and the
// harness escalates a Warning into a failure. The volume is 2200 x 1400 uu; the
// near walk runs 700 uu down its middle and the far walk 900 uu on from there,
// leaving 300 uu of margin at each end and 550 uu of corridor either side of
// the painted box.
//
// The GroundNavPath feature is added to the agent by this fixture rather than
// left to the crowd's own dispatch, with the same params the crowd would have
// used (FCk_Fragment_GroundNavPath_ParamsData{radius}). The crowd composes it
// only if it is missing, so pre-adding changes nothing about what runs - it is
// what gives this test the typesafe handle it needs to read the second plan's
// epoch and repair verdict back for the report.
//
// The provider is per world and every other fixture in this map reads it, so
// the previous selection is captured before the swap and handed back both when
// this test concludes AND in DoEndPlay - every exit path, including the engine
// TimeLimit one, must put the world back.
//
// Isolated Y band: 152000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Rebuild_IdleAgentIsNotRepairedOnItsNextRoute : UCk_AutoTest_Base
{
    // Two full walk episodes, a bake and a rebuild - half again as much wall clock as the
    // single-episode sibling. Wide enough that every wait below expires on its OWN budget and names
    // the condition it was on, rather than the harness's cutoff arriving first: the defect this
    // pins expires a 1800-poll wait, and at a headless lane's frame rate that alone can be most of
    // the sibling's 120 s.
    default _TimeoutSeconds = 180.0f;
    default _AutoStageOriginField = false; // creates its own GroundNav volume

    //------------------------------------------------------------------------
    // Fixture geometry
    //------------------------------------------------------------------------

    private const float BandY = 152000.0;

    private const float SlabHalfX = 1300.0;
    private const float SlabHalfY = 900.0;
    private const float SlabHalfZ = 50.0;

    private const float VolumeHalfX = 1100.0;
    private const float VolumeHalfY = 700.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float SurfaceZ = 0.0;
    private const float AgentCentreOffsetZ = 100.0;

    // Three points on one lane. The near goal is where the agent is standing, idle, when the paint
    // lands; the far goal is where it is sent afterwards, in the direction that takes it AWAY from
    // the painted ground.
    private const float SpawnX = -800.0;
    private const float NearGoalX = -100.0;
    private const float FarGoalX = 800.0;

    // The midpoint of the walk just finished - unambiguously ground the agent crossed, so the
    // corridor its last plan cached reaches it. 200 uu of clear lane between the box's near face
    // and where the body stands (the 30 uu default arrival radius is inside that margin), which is
    // nearly five agent radii: the paint narrows ground the agent WALKED, never the ground under it.
    private const float BlockX = -450.0;
    private const float BlockHalfXY = 150.0;
    private const float BlockHalfZ = 200.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 500.0;

    // One tile a tick, as in the sibling fixture: the rebuild the paint kicks is then a sequence of
    // publishes rather than one frame's worth, which is the harder case for a flag that must not
    // survive the next dispatch.
    private const int32 ProbeBudgetPerTick = 1;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;
    private const float ProfileHalfHeightUu = 96.0;

    // Enough travel that no reading of it can be noise from the arrival settle or from a separation
    // nudge: the frozen walker this pins moves ZERO, and 100 uu is half a second of an ordinary
    // walk. Deliberately far short of the 900 uu episode so the wait resolves early and the frames
    // it does not spend are left to the arrival's own budget.
    private const float MinAdvanceUu = 100.0;

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

    // The slot goes Ready on the install itself, so this is a ceiling on a condition that is either
    // already true or never will be - kept at the sibling's Walking budget rather than tightened,
    // because a budget chosen to make a defect fail FASTER is a budget a slow lane fails on.
    private const int32 SlotReadyFrameBudget = 1800;

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
    private int32 _PathReadyAtSecondMoveTo = 0;
    private int32 _PathFailedCount = 0;

    private int32 _GoalReachedCount = 0;
    private bool _ArrivedNear = false;
    private bool _ArrivedFar = false;

    private bool _Painted = false;
    private bool _SecondMoveToIssued = false;

    // The route the LAST install put in the shared nav slot, and where the body stood when it
    // landed. Both are needed together: GroundNav drops the first waypoint when the body already
    // stands on it, so the origin is what makes the first leg a leg at all.
    private TArray<FVector> _LastRouteWaypoints;
    private FVector _LastRouteOrigin = FVector::ZeroVector;

    // Where the body stood when the second MoveTo was issued, and the furthest it was ever seen
    // from there. A maximum rather than a final reading: the arrival settles the body back a little
    // and the question is whether it MOVED, not where it ended.
    private FVector _SecondMoveToOrigin = FVector::ZeroVector;
    private float _MaxAdvancedUu = 0.0;

    // One monotonic count of observed frames since the second MoveTo, and the stamp of the install
    // inside it, so the two can be subtracted whatever order they arrived in.
    private int32 _FramesSinceSecondMoveTo = 0;
    private int32 _FrameAtSecondInstall = -1;

    // THE defect's fingerprint: frames on which the agent was Walking while its nav slot read
    // Pending. The arrival takes the agent out of Walking, so the frame the walk ENDS on is never
    // counted against it and no arrival-exclusion radius is needed.
    private int32 _PendingWhileWalkingFrames = 0;

    // What the slot read on the FIRST frame the second episode was seen Walking. Reported, never
    // asserted on its own: it is the corroboration for the count above, and a defect whose repair
    // beat the first poll makes it Pending rather than Ready.
    private ECk_Nav_PathStatus _StatusWhenWalking = ECk_Nav_PathStatus::None;
    private bool _StatusWhenWalkingRecorded = false;

    private int64 _RevisionAtPaint = -1;
    private int64 _RevisionAtSecondMoveTo = -1;

    private int64 _EpochAtSecondInstall = 0;
    private ECk_GroundNav_RepairVerdict _VerdictAtSecondInstall = ECk_GroundNav_RepairVerdict::None;

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
        Add_Step_WaitUntil("the floor reaches the Jolt static world",            n"Check_FloorBodyAdded",       BodyFrameBudget);
        Add_Step(          "ask the volume to bake",                             n"Step_RequestBake");
        Add_Step_WaitUntil("the field reports itself built",                     n"Check_FieldBuilt",           BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",            n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles at Ready",                   n"Check_SurfaceSettled",       SurfaceFrameBudget);
        Add_Step(          "spawn the walker and send it to the near goal",      n"Step_SpawnAgent");
        Add_Step_WaitUntil("the walker is Walking an installed route",           n"Check_WalkingInstalledRoute", WalkingFrameBudget);
        Add_Step_WaitUntil("the walker reaches the near goal and goes Idle",     n"Check_ArrivedNearAndIdle",   ArrivalFrameBudget);
        Add_Step(          "paint the ground the idle walker just crossed",      n"Step_PaintBehindIdleWalker");
        Add_Step_WaitUntil("the paint is live on the surface",                   n"Check_PaintIsLive",          LiveFrameBudget);
        Add_Step_WaitUntil("the rebuilt surface goes quiet again",               n"Check_SurfaceQuiet",         SurfaceFrameBudget);
        Add_Step(          "send the idle walker on to the far goal",            n"Step_MoveToFarGoal");
        Add_Step_WaitUntil("the walker is Walking the second route",             n"Check_SecondEpisodeWalking", WalkingFrameBudget);
        Add_Step(          "record the slot under the first walking frame",      n"Step_RecordSecondEpisodeStart");
        Add_Step_WaitUntil("the nav slot reads Ready under the walking body",    n"Check_SecondRouteSlotReady", SlotReadyFrameBudget);
        Add_Step_WaitUntil("the body has advanced off the near goal",            n"Check_SecondEpisodeAdvanced", ProgressFrameBudget);
        Add_Step_WaitUntil("the walker reaches the far goal",                    n"Check_ArrivedFar",           ArrivalFrameBudget);
        Add_Step(          "the latched flag did not repair the fresh route",    n"Step_AssertFreshRouteWasNotRepaired");
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
    // The near walk - the episode whose corridor the paint is aimed at
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SpawnAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Spawn = Get_SpawnPoint();
        const auto NearGoal = Get_NearGoalPoint();

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"GroundNav_IdleRebuild_Walker");

        const auto Rot = (NearGoal - Spawn).Rotation();
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

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(NearGoal));
    }

    UFUNCTION()
    private void OnPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _PathReadyCount += 1;

        _LastRouteWaypoints = InResult.Get_Waypoints();
        _LastRouteOrigin = Get_AgentLocation();

        if (_SecondMoveToIssued && _FrameAtSecondInstall < 0)
        {
            _FrameAtSecondInstall = _FramesSinceSecondMoveTo;

            const auto PlanResult = utils_ground_nav_path::Get_Result(_Planner);
            _EpochAtSecondInstall = PlanResult.Get_PlannedAgainstEpoch();
            _VerdictAtSecondInstall = PlanResult.Get_RepairVerdict();
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

        _GoalReachedCount += 1;

        // Which arrival this is comes from the episode the fixture is IN, not from the position:
        // the two goals are on one lane and a position test would be a tolerance argument.
        if (_SecondMoveToIssued)
        { _ArrivedFar = true; }
        else
        { _ArrivedNear = true; }
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

        Teardown();
        FinishFailure(f"the walker reported OnGoalFailed on a field whose only obstruction sits behind it and leaves 550uu of corridor either side (painted={_Painted}, secondMoveToIssued={_SecondMoveToIssued}, goalsReached={_GoalReachedCount}, pathFailures={_PathFailedCount})");
    }

    UFUNCTION()
    private void Check_WalkingInstalledRoute(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PathReadyCount >= 1
            && utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking);
    }

    // BOTH halves, because the paint has to land on an agent that is genuinely out of the
    // consumer's view: OnGoalReached is the event, and Idle is the movement state the flag then
    // latches under. An agent still reading Walking on the arrival frame would reach PathRefresh.
    UFUNCTION()
    private void Check_ArrivedNearAndIdle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ArrivedNear
            && utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Idle);
    }

    //------------------------------------------------------------------------
    // The paint, behind the arrived walker
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PaintBehindIdleWalker(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto WalkerAt = Get_AgentLocation();
        const auto StateAtPaint = utils_crowd_agent::Get_MovementState(_Agent);

        Assert_True(StateAtPaint == ECk_CrowdAgent_MovementState::Idle,
            f"the walker must be IDLE when the paint lands - the whole point of this fixture is a publish that reaches an agent PathRefresh's view cannot see, and a Walking agent would consume the flag the same frame it was raised (state {StateAtPaint})");

        const auto FirstRoute = Get_RoutePolyline(_LastRouteOrigin, _LastRouteWaypoints);

        Assert_True(Get_RouteEntersBox(FirstRoute, Get_BlockMin(), Get_BlockMax()),
            f"the route the walker just finished must pass through the ground about to be painted - the invalidator flags on the LAST corridor, so a paint that misses it raises nothing and the fixture would assert nothing. (walker at {WalkerAt}, waypoints {_LastRouteWaypoints.Num()})");

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
        _RevisionAtPaint = utils_nav_surface::Get_SurfaceRevision();
    }

    UFUNCTION()
    private void Check_PaintIsLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_IsMarkupLive(_Markup));
    }

    // Only ever polled AFTER the paint has read live, which is the positive that makes it mean
    // something: on its own "the surface is settled" is true of a surface nothing ever asked to
    // change. What it buys is that no publish is still in flight when the second MoveTo lands - a
    // publish landing after that dispatch would raise the flag legitimately, and the count this
    // test asserts on would then be measuring the mechanism working rather than the defect.
    UFUNCTION()
    private void Check_SurfaceQuiet(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_IsSurfaceSettled());
    }

    //------------------------------------------------------------------------
    // The second episode, and everything observed from it onward
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_MoveToFarGoal(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _SecondMoveToOrigin = Get_AgentLocation();
        _PathReadyAtSecondMoveTo = _PathReadyCount;
        _RevisionAtSecondMoveTo = utils_nav_surface::Get_SurfaceRevision();
        _SecondMoveToIssued = true;

        utils_crowd_agent::Request_MoveTo(_Agent,
            FCk_Request_CrowdAgent_MoveTo(Get_FarGoalPoint()));

        Do_ObserveSecondEpisodeFrame();
    }

    UFUNCTION()
    private void Check_SecondEpisodeWalking(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_ObserveSecondEpisodeFrame();

        auto Res = OutResult;
        Res.Set(Get_InstallsAfterSecondMoveTo() >= 1
            && utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking);
    }

    UFUNCTION()
    private void Step_RecordSecondEpisodeStart(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_ObserveSecondEpisodeFrame();

        ck::nav::Display(f"[GROUNDNAV-IDLE-REBUILD] second episode began: statusWhenWalking={_StatusWhenWalking} installs={Get_InstallsAfterSecondMoveTo()} framesToInstall={_FrameAtSecondInstall} revisionAtPaint={_RevisionAtPaint} revisionAtMoveTo={_RevisionAtSecondMoveTo}");
    }

    // The POSITIVE half of the contract, and the one the defect expires when PathRefresh gets its
    // pass in before this wait's first poll: a route installed one frame ago must leave the shared
    // nav slot READY, not parked at Pending by a repair of itself.
    UFUNCTION()
    private void Check_SecondRouteSlotReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_ObserveSecondEpisodeFrame();

        auto Res = OutResult;
        Res.Set(utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking
            && utils_nav::Get_PathStatus(_AgentEntity) == ECk_Nav_PathStatus::Ready);
    }

    UFUNCTION()
    private void Check_SecondEpisodeAdvanced(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_ObserveSecondEpisodeFrame();

        auto Res = OutResult;
        Res.Set(_MaxAdvancedUu >= MinAdvanceUu);
    }

    UFUNCTION()
    private void Check_ArrivedFar(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_ObserveSecondEpisodeFrame();

        auto Res = OutResult;
        Res.Set(_ArrivedFar);
    }

    // Every frame from the second MoveTo to the arrival passes through here: the four waits after
    // it poll it, and the two steps among them call it once so no frame the sequencer spends
    // between waits goes unobserved.
    private void Do_ObserveSecondEpisodeFrame()
    {
        if (_SecondMoveToIssued == false) { return; }
        if (_ArrivedFar) { return; }
        if (ck::Is_NOT_Valid(_Agent)) { return; }

        _FramesSinceSecondMoveTo += 1;

        const auto State = utils_crowd_agent::Get_MovementState(_Agent);
        const auto Status = utils_nav::Get_PathStatus(_AgentEntity);

        if (State == ECk_CrowdAgent_MovementState::Walking)
        {
            if (_StatusWhenWalkingRecorded == false)
            {
                _StatusWhenWalkingRecorded = true;
                _StatusWhenWalking = Status;
            }

            if (Status == ECk_Nav_PathStatus::Pending)
            { _PendingWhileWalkingFrames += 1; }
        }

        const auto AdvancedUu = Get_AdvancedFromSecondStartUu();

        if (AdvancedUu > _MaxAdvancedUu)
        { _MaxAdvancedUu = AdvancedUu; }
    }

    //------------------------------------------------------------------------
    // The contract
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertFreshRouteWasNotRepaired(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Installs = Get_InstallsAfterSecondMoveTo();
        auto Advanced = _MaxAdvancedUu;

        // Points 3 and 4 of the contract are carried by their own named waits above - a wait that
        // runs out of polls fails naming the condition it was on - so they are REPORTED here rather
        // than re-asserted.
        ck::nav::Display(f"[GROUNDNAV-IDLE-REBUILD] installsAfterSecondMoveTo={Installs} statusWhenWalking={_StatusWhenWalking} advancedUu={Advanced :.1} arrivedSecond={_ArrivedFar}");
        ck::nav::Display(f"[GROUNDNAV-IDLE-REBUILD] detail: pendingWhileWalkingFrames={_PendingWhileWalkingFrames} observedFrames={_FramesSinceSecondMoveTo} framesToSecondInstall={_FrameAtSecondInstall} epochAtSecondInstall={_EpochAtSecondInstall} repairVerdict={_VerdictAtSecondInstall} revisionAtMoveTo={_RevisionAtSecondMoveTo} revisionNow={utils_nav_surface::Get_SurfaceRevision()} pathFailures={_PathFailedCount}");

        // First, because this is the half that fails with the dispatch-time clear reverted: the
        // repair parks the slot, the install seam's dedup drops its answer, and the slot then reads
        // Pending under a Walking body for the rest of the episode.
        Assert_Equals_Int(_PendingWhileWalkingFrames, 0,
            f"the walker was Walking on a nav slot reading Pending for {_PendingWhileWalkingFrames} of the {_FramesSinceSecondMoveTo} frames observed after the second MoveTo. A rebuild that landed while this agent was IDLE latched FTag_GroundNavPath_RepathRequired on it; the dispatch of this episode's plan is what must clear it, because a plan made against the field as published now cannot owe a repair to the corridor it replaces. A repair issued anyway re-plans the same goal against the same epoch, the install seam deduplicates the answer away, and nothing ever un-parks the slot.");

        Assert_Equals_Int(Installs, 1,
            f"the second MoveTo must install exactly ONE route (got {Installs} installs, {_PathFailedCount} plan failures). Zero means the fresh plan never landed at all. More than one means the latched invalidation was answered as a repair of the route it had nothing to say about, and that repair's answer was different enough from the fresh one to survive the install seam's dedup.");

        // Fixture guards, not feature contract: they are what stops a geometry drift turning this
        // into a test of nothing. The first is that the paint reached ground the agent walked - the
        // paint step asserts it against the route as installed; this is the second half, that the
        // route the agent finished on never went near the painted box, so no repair of it could
        // ever have been the RIGHT answer.
        const auto FinalRoute = Get_RoutePolyline(_LastRouteOrigin, _LastRouteWaypoints);

        Assert_False(Get_RouteEntersBox(FinalRoute, Get_BlockMin(), Get_BlockMax()),
            f"a LEG of the route the walker finished on passes through the painted box. The box's near face is 200 uu BEHIND the near goal and the far goal is 900 uu the other way, so a second route that meets it means the lane geometry has drifted and the paint is no longer off this episode's ground. (waypoints={_LastRouteWaypoints.Num()}, installs={Installs})");
    }

    //------------------------------------------------------------------------
    // Fixture geometry helpers
    //------------------------------------------------------------------------

    private FVector Get_SpawnPoint()    { return FVector(SpawnX,    BandY, SurfaceZ + AgentCentreOffsetZ); }
    private FVector Get_NearGoalPoint() { return FVector(NearGoalX, BandY, SurfaceZ + AgentCentreOffsetZ); }
    private FVector Get_FarGoalPoint()  { return FVector(FarGoalX,  BandY, SurfaceZ + AgentCentreOffsetZ); }
    private FVector Get_BlockCentre()   { return FVector(BlockX,    BandY, SurfaceZ); }

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

    private int32 Get_InstallsAfterSecondMoveTo()
    {
        return _PathReadyCount - _PathReadyAtSecondMoveTo;
    }

    // PLANAR, because the question is whether the body travelled: the agent's Z is whatever the
    // navmesh constraint lands it on, and a fixture that counted it would read a settle onto the
    // surface as progress.
    private float Get_AdvancedFromSecondStartUu()
    {
        const auto Delta = Get_AgentLocation() - _SecondMoveToOrigin;

        return FVector(Delta.X, Delta.Y, 0.0).Size();
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
