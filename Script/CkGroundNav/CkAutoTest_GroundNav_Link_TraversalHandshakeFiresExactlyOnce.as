// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: THE LINK-TRAVERSAL HANDSHAKE FIRES ONCE
//============================================================================
//
// The crowd half of the neutral link handshake, on a real published field. The
// cursor driver and the CkNavigation state machine are pinned at Layer 1 from
// C++ against hand-written spans; this is the same handshake reached the only
// way a game reaches it - a crowd agent, a GroundNav route, and an authored
// link that route crosses.
//
// The scene is the authored-link pin's, unchanged and for its reasons: a field over
// the origin floor, one runtime wall that runs OFF the field's edge in Y so no
// route gets round it, and one link over that wall. The wall is offset in X
// from the floor's centre because FCkAutoTest_GroundNavFixture probes straight
// down through that centre to decide whether the floor is already in the Jolt
// static world, and a wall standing on the probe line would answer that
// question for the floor.
//
//----------------------------------------------------------------------------
// WHAT IS PINNED, AND WHAT IS DELIBERATELY NOT
//----------------------------------------------------------------------------
//
// Pinned here:
//
//   1. The install's METADATA. The route the agent is handed carries exactly
//      ONE link span, its entry and exit are CONSECUTIVE waypoints, and those
//      two waypoints are the link's authored endpoints. A span whose indices
//      named other waypoints would drive the cursor onto the wrong ground.
//   2. OnLinkTraversalBegun fires EXACTLY ONCE for the first route, carrying
//      the link's stable authored id and the correlator the traverser reads
//      back as active.
//   3. Get_IsTraversingLink answers true while that crossing is the active one.
//   4. The crossing COMPLETES. OnLinkTraversalCompleted fires EXACTLY ONCE for
//      that first crossing, reporting Succeeded and naming the same authored
//      link and the same correlator Begun reported. Get_IsTraversingLink
//      answers false inside that broadcast - the traverser clears its state
//      before it broadcasts, so a listener may start the next crossing from
//      inside this one's end.
//   5. The body is on the FAR SIDE afterwards and goes on to reach the goal.
//      The wall runs off the field's edge, so the goal is unreachable except
//      across the link: an arrival is a crossing that was walked, not a route
//      that found a way round.
//   6. The agent never leaves Walking for the length of the crossing. The
//      crossing tag is additive - an agent on a ladder is still walking the
//      polyline it was handed - so the Idle/PathPending/Walking triple must not
//      move under it. Observation closes when the crossing ends, because the
//      arrival ahead legitimately puts the agent in Idle.
//   7. A route swap while a crossing is live ends it as Failed_Cancelled,
//      exactly once, naming the SAME link and the SAME correlator that Begun
//      reported. Re-targeting to a DIFFERENT goal is what a game does when a
//      director changes its mind; the replacement route crosses the same link
//      under a NEW correlator, and the crossing that was running is the old
//      one's to end.
//
// A body crossing a link stands on no walkable cell between the two endpoints,
// so FProcessor_CrowdAgent_ConstrainToNavmesh - whose contract is to keep every
// grounded position ON the walkable set - hands the frame's steered
// displacement through unchanged while FTag_CrowdAgent_TraversingLink is set,
// and resumes the surface walk the frame the cursor leaves the exit. That is
// what carries the body from the entry endpoint to the exit.
//
//----------------------------------------------------------------------------
// WHY THE CROSSING IS ALREADY ACTIVE WHEN THE ROUTE INSTALLS
//----------------------------------------------------------------------------
//
// The cursor driver is RECONCILED, not edge-detected: it asks which span the
// cursor stands within each pass. A funnelled route over open ground is the
// entry, the exit and the goal, so the cursor stands within the span from the
// install onward and Begun fires there - hundreds of uu before the body reaches
// the endpoint. This test therefore waits on the SIGNAL, never on proximity.
//
//----------------------------------------------------------------------------
// WHY THE SECOND PHASE SENDS THE WALKER BACK
//----------------------------------------------------------------------------
//
// The first phase walks its crossing to the end, so there is no live crossing
// left for a swap to cancel. The second phase therefore starts a FRESH one: the
// walker is sent back to where it spawned, which crosses the same link the
// other way under a new correlator, and that route is REPLACED once Begun has
// fired and the body has covered a first hundred uu - far short of the four
// hundred that separate the link's endpoints, so the crossing the swap ends is
// unmistakably an unfinished one.
//
// The replacement names a DIFFERENT goal, and it has to. A MoveTo whose target
// is within 20uu of the goal the agent is already walking to, carrying neither
// a correlation id nor ForceRepath, is a deliberate NO-OP: the handler returns
// Succeeded without opening an episode, so that a noisy re-issuer cannot keep
// resetting the waypoint cursor and stop the final stop ever latching. Nothing
// is abandoned and nothing is cancelled, and the crossing goes on to be walked
// off the far end - which is the outbound phase's claim, not this one's.
// Re-targeting to a different point on the near side IS a new episode, and
// every new episode opens by abandoning the active provider query, which is
// where a live crossing is ended.
//
// The provider is a WORLD selection every later fixture in this map reads, so
// the previous value is captured before the swap and handed back on every exit
// path including DoEndPlay - the engine TimeLimit path never runs the finish
// path.
//============================================================================

class UCk_AutoTest_GroundNav_Link_TraversalHandshakeFiresExactlyOnce : UCk_AutoTest_Base
{
    // A 16-tile bake, four kicked settles, two crowd episodes and a route swap, each on its own
    // budgeted condition. Deliberately slack: a contract that expires on the harness's anonymous
    // TimesUp names nothing.
    default _TimeoutSeconds = 300.0f;

    //------------------------------------------------------------------------
    // Geometry - the authored-link pin's scene, offsets from the floor's own centre
    // and top face.
    //------------------------------------------------------------------------

    // Clear of the floor centre, which is where the fixture probes for the floor.
    private const float WallOffsetX = 300.0;

    private const float WallHalfX = 50.0;

    // Wider than the field's own 1000uu half-extent, so the wall leaves no way round and the link
    // is the ONLY route across. Without that the agent could reach the goal without a crossing and
    // every assertion below would be about nothing.
    private const float WallHalfY = 1100.0;

    private const float WallHalfZ = 150.0;

    private const float StartOffsetX = -500.0;
    private const float GoalOffsetX = 700.0;

    // 150uu of floor between each endpoint and the wall face it stands beside, which is more than
    // three times the body radius the field admits. Offset in Y so both endpoints are genuine
    // corners rather than points collinear with their neighbours.
    private const float LinkStartOffsetX = 100.0;
    private const float LinkEndOffsetX = 500.0;
    private const float LinkOffsetY = 400.0;

    private const float LinkClearanceUu = 100.0;
    private const float LinkMultiplier = 1.0;

    // Slack around an equality: a resolved entry copies the record's two world points verbatim and
    // Get_CornerOffset leaves a waypoint that is exactly a pinned endpoint where it is. Not a
    // search radius.
    private const float EndpointToleranceUu = 1.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;
    private const float AgentCentreOffsetZ = 100.0;
    private const float CellHeightUu = 10.0;

    // How far the body must have travelled before the walker is re-targeted. Far enough that the swap
    // is unambiguously mid-episode, short enough that the cursor cannot yet have walked off the
    // link's exit - the crossing the swap ends has to be an unfinished one.
    private const float SwapTriggerTravelUu = 100.0;

    // Where the replacement route is aimed: the start side still, but off the lane the walker was
    // already returning to. A goal within 20uu of the ACTIVE one, with no correlation id and no
    // ForceRepath, is a no-op the crowd returns Succeeded to without opening an episode - and an
    // episode is what abandons the provider query and ends the crossing. Offset in Y rather than X
    // so the near-side leg keeps the same length and the link's endpoints stay genuine corners.
    private const float SwapGoalOffsetY = -300.0;

    // How near the goal the walker must stand for OnGoalReached to read as an arrival AT the goal.
    // Deliberately NOT the crowd's own _ArrivalRadius: that one is measured in 3D against the
    // route's FINAL WAYPOINT, which sits on the nav surface, while the point handed to
    // Request_MoveTo is a body-height above it. This is the band the Rebuild pin already treats as
    // "at the goal", and the nearest other stopping point - the link's exit - is hundreds of uu out.
    private const float ArrivalProximityUu = 200.0;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 SettleFrameBudget = 3600;
    private const int32 WalkingFrameBudget = 1800;
    private const int32 SignalFrameBudget = 1800;
    private const int32 CrossingFrameBudget = 3600;
    private const int32 ArrivalFrameBudget = 3600;

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _WallEntity;
    private FCk_Handle _LinkEntity;
    private FCk_Handle _AgentEntity;

    private FCk_Handle_JoltBody _WallBody;
    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_GroundNavPath _Planner;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    //------------------------------------------------------------------------
    // Episode bookkeeping
    //------------------------------------------------------------------------

    private int32 _LinkCompletions = 0;
    private ECk_Request_OperationResult _LastLinkResult = ECk_Request_OperationResult::Failed;

    private int32 _AuthoredLinkId = -1;

    private int32 _PathReadyCount = 0;
    private FVector _SpawnLocation = FVector::ZeroVector;

    // Counted across the WHOLE run; the phase boundaries below are what make "exactly once"
    // a statement about one route rather than about the file.
    private int32 _BegunCount = 0;
    private int32 _CompletedCount = 0;

    private int32 _BegunCountAtSwap = -1;
    private int32 _CompletedCountAtSwap = -1;

    private int32 _FirstBegunLinkId = -1;
    private int32 _FirstBegunCorrelator = -1;
    private bool _TraversingAtFirstBegun = false;

    private int32 _SecondBegunCorrelator = -1;

    private int32 _FirstCompletedLinkId = -1;
    private int32 _FirstCompletedCorrelator = -1;
    private ECk_Request_OperationResult _FirstCompletedResult = ECk_Request_OperationResult::Failed;

    // Everything the first Completed announces, read INSIDE the broadcast for the reason the Begun
    // readings are: the state the signal announces is the state a listener acts on.
    private bool _TraversingAtFirstCompleted = true;
    private ECk_CrowdAgent_MovementState _StateAtFirstCompleted = ECk_CrowdAgent_MovementState::None;
    private FVector _LocationAtFirstCompleted = FVector::ZeroVector;

    private int32 _SecondCompletedLinkId = -1;
    private int32 _SecondCompletedCorrelator = -1;
    private ECk_Request_OperationResult _SecondCompletedResult = ECk_Request_OperationResult::Succeeded;

    private bool _Arrived = false;
    private FVector _ArrivalLocation = FVector::ZeroVector;

    //------------------------------------------------------------------------
    // The route's own metadata, sampled at the FIRST install and never
    // overwritten: what the pin is about is the answer the agent was handed,
    // not whatever the last route in the file happened to be.
    //------------------------------------------------------------------------

    private bool _SpansSampled = false;
    private int32 _SpanCount = -1;
    private int32 _SpanLinkId = -1;
    private int32 _SpanEntryIndex = -1;
    private int32 _SpanExitIndex = -1;
    private float _SpanEntryDriftUu = -1.0;
    private float _SpanExitDriftUu = -1.0;
    private int32 _InstalledWaypointCount = -1;

    //------------------------------------------------------------------------
    // Movement-state observation, over THE CROSSING only - from the first
    // installed route to the frame the crossing is reported ended. The arrival
    // that follows legitimately puts the agent in Idle, and the re-issue after
    // it legitimately passes through PathPending; what this claim is about is
    // that a CROSSING does not move the agent out of Walking.
    //------------------------------------------------------------------------

    private bool _Observing = false;
    private int32 _ObservedFrames = 0;
    private int32 _NonWalkingFrames = 0;
    private ECk_CrowdAgent_MovementState _FirstNonWalkingState = ECk_CrowdAgent_MovementState::None;

    //------------------------------------------------------------------------
    // Reporting state
    //------------------------------------------------------------------------

    private FString _Verdict = "incomplete";
    private bool _Reported = false;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stand a wall across the origin floor",               n"Step_StageWall");
        Add_Step_WaitUntil("the wall reaches the Jolt static world",             n"Check_WallBodyAdded",      BodyFrameBudget);
        Add_Step(          "stage a GroundNav field over the origin floor",      n"Step_StageField");
        Add_Step_WaitUntil("the origin field reports itself built",              n"Check_OriginFieldBuilt",   BuildFrameBudget);
        Add_Step(          "switch the world onto GroundNav",                    n"Step_SwitchProvider");
        Add_Step_WaitUntil("the surface settles after the provider switch",      n"Check_SurfaceSettled",     SurfaceFrameBudget);
        Add_Step(          "author the link over the wall",                      n"Step_AuthorLink");
        Add_Step_WaitUntil("the surface settles after the link",                 n"Check_SurfaceSettled",     SettleFrameBudget);
        Add_Step(          "the link is live and the volume names its id",       n"Step_AssertLinkLive");
        Add_Step(          "spawn the walker and send it across the link",       n"Step_SpawnAgent");
        Add_Step_WaitUntil("the walker is Walking an installed route",           n"Check_WalkingInstalledRoute", WalkingFrameBudget);
        Add_Step(          "the installed route carries exactly one link span",  n"Step_SampleSpans");
        Add_Step_WaitUntil("the crossing is announced",                          n"Check_TraversalBegun",     SignalFrameBudget);
        Add_Step(          "the crossing was announced exactly once",            n"Step_AssertBegunOnce");
        Add_Step_WaitUntil("the crossing is reported ended",                     n"Check_TraversalCompleted", CrossingFrameBudget);
        Add_Step(          "the crossing ended Succeeded exactly once",          n"Step_AssertCompletedOnce");
        Add_Step_WaitUntil("the walker reaches the goal past the wall",          n"Check_WalkerArrived",      ArrivalFrameBudget);
        Add_Step(          "the walker stands at the goal on the far side",      n"Step_AssertArrivedFarSide");
        Add_Step(          "send the walker back across the link",               n"Step_SendBack");
        Add_Step_WaitUntil("the return crossing is announced",                   n"Check_ReturnTraversalBegun", SignalFrameBudget);
        Add_Step_WaitUntil("the walker has left the goal behind",                n"Check_LeftArrivalBehind",  WalkingFrameBudget);
        Add_Step(          "re-target the walker while that crossing is live",    n"Step_SwapRoute");
        Add_Step_WaitUntil("the replaced crossing is reported ended",            n"Check_ReturnTraversalCompleted", SignalFrameBudget);
        Add_Step(          "the replaced crossing ended Failed_Cancelled once",  n"Step_AssertCancelledOnce");
        Add_Step(          "hand the world back",                                n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Staging - the wall goes in BEFORE the field, because the field bakes what
    // the Jolt static world holds at the moment the build starts.
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_StageWall(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _WallEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _WallEntity.Request_OverrideToSelf();
        _WallEntity.Set_DebugName(n"AutoTest_GroundNav_HandshakeWall");

        // The floor readers are only valid after staging, and staging is the step after this one,
        // so the wall is placed against the LEVEL's own floor actor. Both resolve to the same
        // ground; this one is available a step earlier.
        const auto Centre = Get_LevelFloorCentre();
        const auto TopZ = Get_LevelFloorTopZ();

        utils_transform::Add(_WallEntity,
            FTransform(FRotator::ZeroRotator,
                FVector(Centre.X + WallOffsetX, Centre.Y, TopZ + WallHalfZ)),
            ECk_Replication::DoesNotReplicate);

        auto WallShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        WallShape.Set_HalfExtents(FVector(WallHalfX, WallHalfY, WallHalfZ));

        auto WallParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        WallParams.Set_ShapeDimensions(WallShape);
        WallParams.Set_MotionType(ECk_MotionType::Static);

        _WallBody = utils_jolt_body::Add(_WallEntity, WallParams);

        Assert_True(ck::IsValid(_WallBody),
            "the wall's Jolt body must be valid - the field bakes from the Jolt static world, so a wall that never got a body is a field with nothing to split it");
    }

    UFUNCTION()
    private void Check_WallBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_jolt_body::Get_IsBodyAdded(_WallBody));
    }

    UFUNCTION()
    private void Step_StageField(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (_Field.Request_StageOriginField(_SelfHandle) == false)
        { FinishFailure(_Field.Get_StagingError()); }
    }

    // The fixture exposes predicate BODIES, not UFUNCTIONs: Do_EvaluatePredicate binds the named
    // predicate against THIS object, so every wait below needs its own one-line forwarder here.
    UFUNCTION()
    private void Check_OriginFieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_OriginFieldBuilt(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_ObserveFrame();
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Step_SwitchProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Kicked before the mutation, so the number reported afterwards measures THIS switch.
        _Field.Request_KickSettleCount();

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
        _ProviderSwapped = true;

        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::GroundNav,
            f"the world must report the provider it was told to answer on (got {ProviderNow})");
    }

    //------------------------------------------------------------------------
    // The link
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AuthorLink(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Volume = _Field.Get_OriginVolume();

        Assert_True(ck::IsValid(Volume),
            "the fixture must hand back a valid volume before a link can be authored against it");

        _LinkEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _LinkEntity.Request_OverrideToSelf();
        _LinkEntity.Set_DebugName(n"AutoTest_GroundNav_HandshakeLink");

        // The id is -1 because the VOLUME assigns it: the record's identity carries no setter.
        auto Record = FCk_GroundNav_LinkRecord(-1, Get_LinkStart(), Get_LinkEnd());

        Record.Set_Direction(ECk_GroundNav_LinkDirection::Bidirectional)
              .Set_CostMultiplierForward(float32(LinkMultiplier))
              .Set_CostMultiplierBackward(float32(LinkMultiplier))
              .Set_ClearanceUu(float32(LinkClearanceUu))
              .Set_Enable(ECk_EnableDisable::Enable);

        utils_ground_nav_volume::Request_Link(Volume,
            FCk_Request_GroundNavVolume_Link(_LinkEntity, Record),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinkCompleted"));

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void OnLinkCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LinkCompletions += 1;
        _LastLinkResult = InResult;
    }

    UFUNCTION()
    private void Step_AssertLinkLive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_LinkCompletions, 1,
            "the link request's completion delegate must fire exactly once");

        Assert_True(_LastLinkResult == ECk_Request_OperationResult::Succeeded,
            f"both endpoints lie inside the volume and the clearance admits the agent, so admission must complete Succeeded (got {_LastLinkResult})");

        Assert_True(utils_ground_nav_volume::Get_IsLinkLive(_LinkEntity),
            "the surface reported itself settled after the link was authored, so the link must already be in effect - a route planned against a link that is not live would carry no span at all");

        auto Records = utils_ground_nav_volume::Get_LinkRecords(_Field.Get_OriginVolume());

        Assert_Equals_Int(Records.Num(), 1,
            "one link was authored against this volume, so the reflected read-back must carry exactly one record");

        if (Records.Num() != 1)
        { return; }

        // The STABLE authored id. Everything downstream - the span, the Begun payload, the Completed
        // payload - is asserted against this one number, so a span carrying a field-local index
        // instead of the authored id cannot read as correct.
        // A local first: AngelScript reads an indexed struct element out of the array before a method
        // is called on it, and every other read-back in this corpus is written the same way.
        auto Record = Records[0];

        _AuthoredLinkId = Record.Get_Id();

        Assert_True(_AuthoredLinkId >= 0,
            f"the volume assigns a link its id at admission, so a record read back must carry a real one (got {_AuthoredLinkId})");
    }

    //------------------------------------------------------------------------
    // The walker
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SpawnAgent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Spawn = Get_SpawnPoint();
        const auto Goal = Get_GoalPoint();

        _SpawnLocation = Spawn;

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"GroundNav_LinkHandshake_Walker");

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
        // so this fixture holds the typesafe handle it needs to read the plan's spans back: the
        // dispatch adds the feature only when it is missing, so what runs is identical either way.
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

        // The handshake is HANDLE-scoped and composes on first use, so the binding is made on the
        // traverser itself - the same entity the crowd's steering issues the requests against.
        utils_nav_surface_link_traversal::BindTo_OnLinkTraversalBegun(_AgentEntity,
            FCk_Delegate_NavSurface_OnLinkTraversalBegun(this, n"OnLinkTraversalBegun"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav_surface_link_traversal::BindTo_OnLinkTraversalCompleted(_AgentEntity,
            FCk_Delegate_NavSurface_OnLinkTraversalCompleted(this, n"OnLinkTraversalCompleted"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // The arrival is what makes the completed crossing a crossing that was WALKED. Bound as a
        // pair: without OnGoalFailed a route that gave up would spend the arrival budget and expire
        // as a nameless wait instead of naming what the walker reported.
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
    private void OnLinkTraversalBegun(FCk_Handle InTraverser, int32 InLinkId, int32 InCorrelatorId)
    {
        if (IsFinished()) { return; }

        _BegunCount += 1;

        if (_BegunCount == 1)
        {
            _FirstBegunLinkId = InLinkId;
            _FirstBegunCorrelator = InCorrelatorId;

            // Read INSIDE the broadcast: the state the signal announces is the state a listener acts on,
            // and a reading taken a step later would be about whatever survived the frames between.
            _TraversingAtFirstBegun = utils_nav_surface_link_traversal::Get_IsTraversingLink(_AgentEntity);
            return;
        }

        // The return route's crossing - the one the swap below is here to end.
        if (_BegunCount == 2)
        { _SecondBegunCorrelator = InCorrelatorId; }
    }

    UFUNCTION()
    private void OnLinkTraversalCompleted(FCk_Handle InTraverser, int32 InLinkId, int32 InCorrelatorId, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _CompletedCount += 1;

        if (_CompletedCount == 1)
        {
            _FirstCompletedLinkId = InLinkId;
            _FirstCompletedCorrelator = InCorrelatorId;
            _FirstCompletedResult = InResult;

            // Read INSIDE the broadcast, for the reason Begun's readings are. The traverser clears
            // its state BEFORE it broadcasts the end, so what a listener sees here IS the contract
            // a listener starting the next crossing from inside this one depends on.
            _TraversingAtFirstCompleted = utils_nav_surface_link_traversal::Get_IsTraversingLink(_AgentEntity);
            _StateAtFirstCompleted = utils_crowd_agent::Get_MovementState(_Agent);
            _LocationAtFirstCompleted = Get_AgentLocation();
            return;
        }

        if (_CompletedCount == 2)
        {
            _SecondCompletedLinkId = InLinkId;
            _SecondCompletedCorrelator = InCorrelatorId;
            _SecondCompletedResult = InResult;
        }
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }

        // First arrival only: the walker is sent back afterwards, and what this records is where the
        // FAR-side arrival happened.
        if (_Arrived) { return; }

        _Arrived = true;
        _ArrivalLocation = Get_AgentLocation();
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

        Teardown();
        FinishFailure(f"the walker reported OnGoalFailed on a field whose only way to the goal is the authored link (begun={_BegunCount}, completed={_CompletedCount}, routesInstalled={_PathReadyCount})");
    }

    UFUNCTION()
    private void Check_WalkingInstalledRoute(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        const auto IsWalking = _PathReadyCount >= 1
            && utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking;

        // Observation opens on the first Walking frame and never before it: an agent that has not
        // been handed a route yet is legitimately Idle, and counting those frames would make the
        // claim about the spawn rather than about the crossing.
        if (IsWalking)
        { _Observing = true; }

        Res.Set(IsWalking);
    }

    UFUNCTION()
    private void Step_SampleSpans(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_ObserveFrame();

        if (_SpansSampled == false)
        {
            _SpansSampled = true;

            const auto Result = utils_ground_nav_path::Get_Result(_Planner);
            const auto Waypoints = Result.Get_Waypoints();

            _InstalledWaypointCount = Waypoints.Num();

            auto Spans = utils_ground_nav_path::Get_LinksOnPath(_Planner);

            _SpanCount = Spans.Num();

            if (_SpanCount == 1)
            {
                auto Span = Spans[0];

                _SpanLinkId = Span.Get_LinkId();
                _SpanEntryIndex = Span.Get_EntryWaypointIndex();
                _SpanExitIndex = Span.Get_ExitWaypointIndex();

                if (_SpanEntryIndex >= 0 && _SpanEntryIndex < Waypoints.Num())
                { _SpanEntryDriftUu = float((Waypoints[_SpanEntryIndex] - Get_LinkStart()).Size()); }

                if (_SpanExitIndex >= 0 && _SpanExitIndex < Waypoints.Num())
                { _SpanExitDriftUu = float((Waypoints[_SpanExitIndex] - Get_LinkEnd()).Size()); }
            }
        }

        // Asserted HERE rather than after the Begun wait, so a route that crossed no link at all
        // fails naming the route instead of expiring on a signal that was never going to come.
        Assert_Equals_Int(_SpanCount, 1,
            f"the wall leaves no route across the field except the one link, so the route the agent was handed must carry exactly ONE link span (got {_SpanCount} over {_InstalledWaypointCount} waypoints)");

        if (_SpanCount != 1)
        { return; }

        Assert_Equals_Int(_SpanLinkId, _AuthoredLinkId,
            f"a span names the STABLE authored id and never the field-local link index, because an installed path outlives the field it was planned against (span says {_SpanLinkId}, the volume assigned {_AuthoredLinkId})");

        Assert_Equals_Int(_SpanExitIndex, _SpanEntryIndex + 1,
            f"a link crossing is carried through the funnel as two CONSECUTIVE degenerate portals, so its exit is the waypoint immediately after its entry (entry {_SpanEntryIndex}, exit {_SpanExitIndex})");

        Assert_True(_SpanEntryDriftUu >= 0.0 && _SpanEntryDriftUu <= EndpointToleranceUu,
            f"the span's entry index must name the waypoint that IS the link's authored start - a resolved entry copies the record's world point verbatim and Get_CornerOffset leaves it where it is ({_SpanEntryDriftUu}uu away)");

        Assert_True(_SpanExitDriftUu >= 0.0 && _SpanExitDriftUu <= EndpointToleranceUu,
            f"the span's exit index must name the waypoint that IS the link's authored end, for the same reason its entry does ({_SpanExitDriftUu}uu away)");
    }

    UFUNCTION()
    private void Check_TraversalBegun(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_ObserveFrame();

        auto Res = OutResult;
        Res.Set(_BegunCount >= 1);
    }

    UFUNCTION()
    private void Step_AssertBegunOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_ObserveFrame();

        Assert_Equals_Int(_BegunCount, 1,
            f"the cursor stands within exactly one span on this route and a Begin naming the ACTIVE correlator changes nothing, so the crossing must be announced exactly ONCE however many passes the driver makes (got {_BegunCount})");

        Assert_Equals_Int(_FirstBegunLinkId, _AuthoredLinkId,
            f"OnLinkTraversalBegun carries the link the body is crossing, by its stable authored id (got {_FirstBegunLinkId}, expected {_AuthoredLinkId})");

        Assert_True(_TraversingAtFirstBegun,
            "the signal is broadcast by the drain that admitted the Begin, so Get_IsTraversingLink must already answer true inside the broadcast - a listener that gates an animation on it would otherwise see the crossing it was just told about as not running");

        const auto Traversal = utils_nav_surface_link_traversal::Get_LinkTraversal(_AgentEntity);
        const auto ActiveCorrelator = Traversal.Get_CorrelatorId();

        Assert_Equals_Int(ActiveCorrelator, _FirstBegunCorrelator,
            f"the correlator the signal reported is the one the traverser holds as active - it is what a later Complete has to name (traverser says {ActiveCorrelator}, the signal said {_FirstBegunCorrelator})");

        Assert_Equals_Int(_CompletedCount, 0,
            f"nothing has ended this crossing yet, so no completion may have been reported (got {_CompletedCount})");
    }

    UFUNCTION()
    private void Check_TraversalCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_ObserveFrame();

        auto Res = OutResult;
        Res.Set(_CompletedCount >= 1);
    }

    UFUNCTION()
    private void Step_AssertCompletedOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_ObserveFrame();

        Assert_Equals_Int(_CompletedCount, 1,
            f"the cursor walks off a span's exit once, and the driver reconciles rather than edge-detects, so the crossing must be reported ended exactly ONCE however many passes it makes (got {_CompletedCount})");

        Assert_True(_FirstCompletedResult == ECk_Request_OperationResult::Succeeded,
            f"the body walked off the link's far end under its own steering, which is the ONLY thing the driver reports as Succeeded - a route dropped out from under it would arrive here as Failed_Cancelled (got {_FirstCompletedResult})");

        Assert_Equals_Int(_FirstCompletedLinkId, _AuthoredLinkId,
            f"the completion names the link that was crossed, by its stable authored id (got {_FirstCompletedLinkId}, expected {_AuthoredLinkId})");

        Assert_Equals_Int(_FirstCompletedCorrelator, _FirstBegunCorrelator,
            f"a correlator names ONE crossing, so the completion must name the crossing Begun announced (completion says {_FirstCompletedCorrelator}, Begun said {_FirstBegunCorrelator})");

        Assert_True(_TraversingAtFirstCompleted == false,
            "the traverser clears its state BEFORE it broadcasts the end, so Get_IsTraversingLink must already answer false inside the broadcast - a listener that starts the next crossing from inside this one's end has to find the traverser free");

        Assert_True(_StateAtFirstCompleted == ECk_CrowdAgent_MovementState::Walking,
            f"the link's exit is not the route's last waypoint - the goal is still ahead of the body - so ending a crossing must leave the agent Walking the polyline it was handed (got {_StateAtFirstCompleted})");

        // Observation closes with the crossing: the arrival ahead takes the agent out of Walking on
        // purpose, and counting those frames would make this claim about the arrival instead.
        _Observing = false;

        Assert_Equals_Int(_NonWalkingFrames, 0,
            f"the walker left Walking on {_NonWalkingFrames} of the {_ObservedFrames} frames observed between its first installed route and the end of the crossing (first seen in {_FirstNonWalkingState}). FTag_CrowdAgent_TraversingLink is ADDITIVE, beside Flying and Permeable - an agent on a ladder is still walking the polyline it was handed, and the Idle/PathPending/Walking triple must not move under a crossing.");
    }

    UFUNCTION()
    private void Check_WalkerArrived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Arrived);
    }

    UFUNCTION()
    private void Step_AssertArrivedFarSide(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto DistanceToGoalUu = float((_ArrivalLocation - Get_GoalPoint()).Size());
        const auto WallFarFaceX = Get_WallFarFaceX();
        const auto ArrivalX = float(_ArrivalLocation.X);
        const auto CompletedAtX = float(_LocationAtFirstCompleted.X);

        Assert_True(DistanceToGoalUu <= ArrivalProximityUu,
            f"OnGoalReached is broadcast by the final-stop branch, so the body that reported it stands at the goal it was given ({DistanceToGoalUu}uu away)");

        Assert_True(ArrivalX > WallFarFaceX,
            f"the wall runs off the field's edge in Y, so the goal is reachable only across the link - the arrival must therefore be on the FAR side of the wall (body X {ArrivalX}, wall far face {WallFarFaceX})");

        Assert_True(CompletedAtX > WallFarFaceX,
            f"a crossing ends where the cursor walks off the link's exit endpoint, and that endpoint stands past the wall - a completion reported with the body still on the near side would be a cursor that advanced without it (body X {CompletedAtX}, wall far face {WallFarFaceX})");
    }

    //------------------------------------------------------------------------
    // The return crossing and the route swap that ends it
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SendBack(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_CompletedCount, 1,
            f"only the outbound crossing has ended at this point, so anything the swap below reports is the return crossing's (got {_CompletedCount})");

        // Back the way it came. The wall still leaves no way round, so the return route crosses the
        // SAME link - a fresh crossing under a new correlator, which is what the swap then ends.
        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Get_SpawnPoint()));
    }

    UFUNCTION()
    private void Check_ReturnTraversalBegun(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BegunCount >= 2);
    }

    UFUNCTION()
    private void Check_LeftArrivalBehind(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set((Get_AgentLocation() - _ArrivalLocation).Size() >= SwapTriggerTravelUu);
    }

    UFUNCTION()
    private void Step_SwapRoute(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _BegunCountAtSwap = _BegunCount;
        _CompletedCountAtSwap = _CompletedCount;

        // The claim below is about a crossing being ENDED, so it has to be running when the walker is
        // re-targeted. Asserted rather than assumed - the geometry says the body is still hundreds of
        // uu short of the link's exit, but a cursor that had already walked off would make the
        // cancellation counted afterwards a statement about nothing.
        Assert_True(utils_nav_surface_link_traversal::Get_IsTraversingLink(_AgentEntity),
            "the return crossing must still be the traverser's ACTIVE one when the walker is re-targeted - a swap issued after it ended would cancel nothing");

        // A DIFFERENT goal, and that is load-bearing rather than incidental. The crowd treats a
        // MoveTo naming the goal the agent is already walking to - no correlation id, no
        // ForceRepath - as a deliberate no-op: it returns Succeeded without opening an episode, so
        // that a noisy re-issuer cannot keep resetting the waypoint cursor. A no-op abandons no
        // provider query, and a crossing nothing replaced is one that goes on to be walked off the
        // far end. Re-targeting to a point off the lane IS a new episode, and a new episode opens
        // by abandoning the active query - which is where the running crossing ends.
        //
        // The replacement still crosses the same link, under a NEW correlator: the correlator
        // combines the episode's revision with the link id, so a new episode is a new crossing
        // however similar the geometry, and the one that was running is the old one's to end.
        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Get_SwapGoalPoint()));
    }

    UFUNCTION()
    private void Check_ReturnTraversalCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CompletedCount >= 2);
    }

    UFUNCTION()
    private void Step_AssertCancelledOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Spans = _SpanCount;
        const auto Entry = _SpanEntryIndex;
        const auto Exit = _SpanExitIndex;
        const auto Begun = _BegunCount;
        const auto Completed = _CompletedCount;
        const auto NonWalking = _NonWalkingFrames;
        const auto Observed = _ObservedFrames;
        const auto OutboundResult = _FirstCompletedResult;
        const auto ReturnResult = _SecondCompletedResult;

        const auto FinalState = utils_crowd_agent::Get_MovementState(_Agent);

        ck::nav::Display(f"[GROUNDNAV-LINK-HANDSHAKE] linkId={_AuthoredLinkId} spans={Spans} entryWaypoint={Entry} exitWaypoint={Exit} begun={Begun} completed={Completed} outboundResult={OutboundResult} returnResult={ReturnResult} finalMovementState={FinalState} nonWalkingFrames={NonWalking} observedFrames={Observed}");

        Assert_Equals_Int(_CompletedCount, 2,
            f"the outbound crossing was walked to its end and the return one was replaced mid-flight, so exactly TWO crossings have been reported ended - the replacement route's spans no longer name the correlator that was running, and an abandoned crossing is reported rather than dropped (got {_CompletedCount})");

        Assert_True(_SecondCompletedResult == ECk_Request_OperationResult::Failed_Cancelled,
            f"the body did not walk off the link's far end this time: the route it was following was replaced. A listener deciding whether the body ARRIVED is owed that difference, so the completion must report Failed_Cancelled (got {_SecondCompletedResult})");

        Assert_Equals_Int(_SecondCompletedLinkId, _AuthoredLinkId,
            f"the completion names the link the abandoned crossing was on (got {_SecondCompletedLinkId}, expected {_AuthoredLinkId})");

        Assert_Equals_Int(_SecondCompletedCorrelator, _SecondBegunCorrelator,
            f"a correlator names ONE crossing, so the completion must name the crossing the return route announced and never the replacement (completion says {_SecondCompletedCorrelator}, Begun said {_SecondBegunCorrelator})");

        Assert_Equals_Int(_CompletedCountAtSwap, 1,
            f"only the outbound crossing had ended before the swap was issued, so the completion counted above is the swap's (there were already {_CompletedCountAtSwap})");

        Assert_Equals_Int(_BegunCountAtSwap, 2,
            f"the outbound crossing and the return crossing are the only two announced when the goal was re-issued (there were {_BegunCountAtSwap})");
    }

    //------------------------------------------------------------------------
    // Frame observation - PHASE ONE only. Every wait and every step in that
    // phase calls it, so no frame the sequencer spends between waits goes
    // unobserved.
    //------------------------------------------------------------------------

    private void Do_ObserveFrame()
    {
        if (_Observing == false) { return; }
        if (ck::Is_NOT_Valid(_Agent)) { return; }

        _ObservedFrames += 1;

        const auto State = utils_crowd_agent::Get_MovementState(_Agent);

        if (State != ECk_CrowdAgent_MovementState::Walking)
        {
            if (_NonWalkingFrames == 0)
            { _FirstNonWalkingState = State; }

            _NonWalkingFrames += 1;
        }
    }

    //------------------------------------------------------------------------
    // Geometry. The level floor readers answer before the fixture has staged;
    // the fixture's own readers answer afterwards and resolve to the same
    // ground, which is why the wall uses the first and everything else the
    // second.
    //------------------------------------------------------------------------

    private FVector Get_LevelFloorCentre()
    {
        auto FloorActor = assets::StaticMeshActor_1().Get();

        if (!System::IsValid(FloorActor))
        { return FVector::ZeroVector; }

        auto Origin = FVector::ZeroVector;
        auto Extent = FVector::ZeroVector;
        FloorActor.GetActorBounds(false, Origin, Extent);

        return FVector(Origin.X, Origin.Y, Origin.Z);
    }

    private float Get_LevelFloorTopZ()
    {
        auto FloorActor = assets::StaticMeshActor_1().Get();

        if (!System::IsValid(FloorActor))
        { return 0.0; }

        auto Origin = FVector::ZeroVector;
        auto Extent = FVector::ZeroVector;
        FloorActor.GetActorBounds(false, Origin, Extent);

        return float(Origin.Z + Extent.Z);
    }

    // Read off the LEVEL's floor, which is the centre the wall was actually placed against.
    private float Get_WallFarFaceX()
    {
        return float(Get_LevelFloorCentre().X + WallOffsetX + WallHalfX);
    }

    private FVector Get_SpawnPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + StartOffsetX, Centre.Y, _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
    }

    private FVector Get_GoalPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + GoalOffsetX, Centre.Y, _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
    }

    // The near side still, off the lane the return route was already aimed down - far enough from
    // the active goal that the crowd reads it as a re-target rather than as the same goal restated,
    // and on the opposite side of the lane from the link so the crossing's endpoints stay corners.
    private FVector Get_SwapGoalPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + StartOffsetX, Centre.Y + SwapGoalOffsetY, _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
    }

    private FVector Get_LinkStart()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + LinkStartOffsetX, Centre.Y + LinkOffsetY, _Field.Get_FloorTopZ());
    }

    private FVector Get_LinkEnd()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + LinkEndOffsetX, Centre.Y + LinkOffsetY, _Field.Get_FloorTopZ());
    }

    private FVector Get_AgentLocation()
    {
        if (ck::Is_NOT_Valid(_AgentEntity))
        { return _SpawnLocation; }

        return utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(_AgentEntity));
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Verdict = "green";

        Teardown();
    }

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. Two things here outlive this
    // test's own subtree: the provider is a WORLD selection every later fixture in this map reads,
    // and the fixture's field - plus any floor body it pushed into the Jolt static world - would
    // otherwise stay staged for the rest of the lane.
    private void Teardown()
    {
        if (_Reported == false)
        {
            _Reported = true;
            _Field.Do_ReportCrossover("Link_TraversalHandshakeFiresExactlyOnce", _Verdict);
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

        if (ck::IsValid(_LinkEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_LinkEntity);
            _LinkEntity = FCk_Handle();
        }

        _Field.Request_ReleaseOriginField();

        if (ck::IsValid(_WallEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_WallEntity);
            _WallEntity = FCk_Handle();
        }
    }
}
