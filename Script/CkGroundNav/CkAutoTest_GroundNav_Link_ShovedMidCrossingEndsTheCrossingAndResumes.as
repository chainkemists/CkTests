// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A WALKER SHOVED OFF ITS CORRIDOR MID-CROSSING
//============================================================================
//
// The sibling file (Link_DisabledMidCrossingHoldsTheBodyAndResumesOnEnable)
// takes the GROUND away from under a crossing. This one takes the BODY away
// from under the route instead - the same scene, the same ladder, the same
// walker, shoved 500uu sideways onto open floor while its crossing is the
// traverser's ACTIVE one - and it reaches the ending through a DIFFERENT seam.
//
//----------------------------------------------------------------------------
// WHAT IS PINNED
//----------------------------------------------------------------------------
//
//   1. The crossing ENDS, and it ends in FProcessor_CrowdAgent_ConstrainToNavmesh
//      rather than at the install of the answer. The discriminator is ORDER: the
//      crowd's FTag_CrowdAgent_TraversingLink clears on a frame where the shared
//      nav slot still reads Pending. Ready at the clear would mean the install
//      seam ended it and the guard was never reached at all.
//   2. The body does not CLIMB while it has no route. Its Z never rises above
//      where it stood on the frame the tag cleared, sampled every poll until it
//      is Walking a route again. That is the whole point of ending the crossing:
//      the tag is what licenses ConstrainToNavmesh to stand its surface walk
//      down, and left standing on a body that is NOT walking it makes a free 3D
//      body steered at the ladder exit that nothing in the frame is grounding.
//   3. The crossing is REPORTED, not dropped. The handshake reads NOT traversing
//      once the ending has drained, and OnLinkTraversalCompleted named the
//      abandoned crossing - the same correlator Begun announced - with
//      Failed_Cancelled, because the body did not walk off the ladder's far end.
//   4. The walker RESUMES and ARRIVES, with ZERO OnGoalFailed. The active move
//      survives the displacement: nothing here issues Request_Stop and nothing
//      re-issues the goal. The re-path plans from the floor, over the ladder
//      again, and the walker climbs it for real.
//
//----------------------------------------------------------------------------
// THE MECHANISM (file:line, verified against the tree this file was written on)
//----------------------------------------------------------------------------
//
// FProcessor_CrowdAgent_ConstrainToNavmesh stands its surface walk down while
// FTag_CrowdAgent_TraversingLink is set, but ONLY while the agent is ALSO
// Walking (CkCrowdAgent_ConstrainToNavmesh_Processor.cpp:201-216): a
// TraversingLink agent that is NOT Walking has left its route part-way across a
// link, so the pass calls DoCancelActiveLinkTraversal and grounds the body.
//
// The sibling's mid-crossing pin never reaches that guard - its crossing ends
// through the install seam's Fail branch
// (CkCrowdAgent_OnGroundNavPathResolved_Processor.cpp:205-207) - so the guard
// has had no pin of its own.
//
// The way OUT of Walking that reaches it is the off-path tier of
// FProcessor_CrowdAgent_BlockDetect. Its view is Walking + HasProbe with NO
// TraversingLink exclusion (CkCrowdAgent_BlockDetect_Processor.h:26-39), and on
// the _BlockDetectionInterval cadence (0.5s, CkCrowd_ProjectSettings.h:238) an
// agent further than _BlockDetectionOffPathRepathThresholdCm (300cm XY,
// CkCrowd_ProjectSettings.h:263) from its current path segment is re-pathed by
// DoRepathAtActiveGoal (CkCrowdAgent_BlockDetect_Processor.cpp:488-507 ->
// :575-600). That helper REMOVES FTag_CrowdAgent_Walking, ADDS
// FTag_CrowdAgent_PathPending, zeroes the desired velocity and re-requests the
// ACTIVE goal - and leaves TraversingLink standing. From that frame until the
// answer installs the agent is TraversingLink + PathPending, which is exactly
// the guard's case.
//
// The install seam ALSO cancels a stale crossing on the Install branch
// (CkCrowdAgent_OnGroundNavPathResolved_Processor.cpp:132-134), which is why
// the ORDER claim, not the mere fact of the ending, is what separates the two.
//
//----------------------------------------------------------------------------
// FALSIFIER
//----------------------------------------------------------------------------
//
// Remove the guard's `NOT Walking` branch and the tag survives the whole
// re-path window: it would then clear only when the answer installs, the slot
// reads Ready at the clear, and claim 1 goes red. Remove the guard entirely and
// the body is a free 3D body steered at the ladder exit for the whole
// PathPending window - claim 1 goes red again; the no-rise half of claim 2 is a
// BOUND on that window rather than a second discriminator, since the window is
// one or two polls long and a body braking from <= 240 cm/s cannot climb 25uu
// in it.
//
//----------------------------------------------------------------------------
// KNOWN UNKNOWN - stated, not worked around
//----------------------------------------------------------------------------
//
// Whether the GroundNav answer can land in the SAME frame the off-path re-path
// is dispatched. Read from the group order at authoring (CkProcessorGroups.h:
// TimeDelta -> Gameplay -> ... -> Physics): BlockDetect and ConstrainToNavmesh
// both run in FGroup_Physics, the dispatch marks the slot Pending synchronously
// and enqueues the search, the search drains and the install seam runs in the
// Gameplay groups of the NEXT frame, and this test's per-frame poll is a
// TimeDelta timer - so the guard fires in frame N, the frame N+1 poll reads the
// tag false with the slot still Pending, and the earliest Ready is later that
// same frame, after the poll. The one PRECONDITION: the guard is reached in
// frame N only because the body is still displacing (ConstrainToNavmesh early-
// outs on a zero pending displacement until its 1.0 s verify cadence), which
// holds here since the shoved body is mid-steer and AccelClamp cannot zero it
// in one frame. Nothing here sleeps, pokes a cvar or switches provider to force
// the order; a Ready at the clear is read with this paragraph, not re-measured
// blind.
//
// Ensures are not asserted explicitly - the AutoTest harness escalates a fired
// ensure to a failure on its own. No Get_ExpectedLogErrors wrapper is
// hand-authored: the guard and BlockDetect both report at Log verbosity, and
// this run expects no goal failure, so nothing here is owed a Warning.
//============================================================================

class UCk_AutoTest_GroundNav_Link_ShovedMidCrossingEndsTheCrossingAndResumes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 300.0f;
    default _AutoStageOriginField = false; // stages its own origin field

    //------------------------------------------------------------------------
    // Geometry - the sibling's, verbatim, so the two files cannot drift into
    // testing two different scenes.
    //------------------------------------------------------------------------

    // Clear of the floor centre: the fixture probes straight down through it to decide whether the
    // floor is already in the Jolt static world, and a deck standing on the probe line would answer
    // that question for the floor.
    private const float DeckOffsetX = 400.0;

    private const float DeckHalfXY = 200.0;
    private const float DeckHalfZ = 100.0;

    // The ladder. 60uu of floor between its foot and the deck's south face, 60uu of deck top between
    // its exit and that same face, so both endpoints are corners on genuinely walkable ground.
    private const float LadderFootOffsetY = -260.0;
    private const float LadderTopOffsetY = -140.0;

    // Wide enough that admission is never the variable under test.
    private const float LadderClearanceUu = 100.0;

    private const float SpawnOffsetY = -600.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;
    private const float AgentCentreOffsetZ = 100.0;

    private const float RestToleranceUu = 30.0;

    // How far up the ladder the body must be before it is shoved. Well clear of the foot's own cell
    // and of the settle noise around it, so "mid-crossing" is a fact rather than a guess.
    private const float MidCrossingLiftUu = 60.0;

    // Slack on the no-climb claim: one frame of braking residual along the ladder's own direction is
    // admissible, a body that gains a body-height is not.
    private const float ClimbToleranceUu = 25.0;

    private const float ArrivalProximityUu = 200.0;

    // The shove: 500uu along -X from the ladder, on the origin floor's top face. -X because the deck
    // stands at +X, so this lands on open walkable floor and never inside the island. 500 is well
    // past the 300cm off-path threshold with room for the segment the agent is measured against
    // being the ladder's own span rather than a floor leg.
    private const float ShoveOffPathUu = 500.0;

    //------------------------------------------------------------------------
    // Budgets - every one a ceiling on a NAMED condition.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SettleFrameBudget = 3600;
    private const int32 WalkingFrameBudget = 1800;
    private const int32 SignalFrameBudget = 1800;
    private const int32 ArrivalFrameBudget = 3600;

    // 3s at the 60fps the budgets above are sized against. The off-path sample fires on a 0.5s
    // cadence and the tag clears on the constraint pass that follows it, so this is several times
    // the window the condition actually needs - and it is a CEILING on a named condition, not a
    // settle.
    private const int32 CrossingEndFrameBudget = 180;

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _DeckEntity;
    private FCk_Handle _LinkEntity;
    private FCk_Handle _AgentEntity;

    private FCk_Handle_JoltBody _DeckBody;
    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_Transform _AgentTransform;
    private FCk_Handle_GroundNavPath _Planner;

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    //------------------------------------------------------------------------
    // Episode bookkeeping
    //------------------------------------------------------------------------

    private int32 _LinkCompletions = 0;
    private ECk_Request_OperationResult _LastLinkResult = ECk_Request_OperationResult::Failed;
    private int32 _AuthoredLinkId = -1;

    private int32 _BegunCount = 0;
    private int32 _CompletedCount = 0;
    private int32 _FirstBegunCorrelator = -1;
    private int32 _CrossingEndCorrelator = -1;
    private ECk_Request_OperationResult _CrossingEndResult = ECk_Request_OperationResult::Succeeded;

    private int32 _GoalFailures = 0;
    private FString _GoalFailureReasons = "";
    private bool _Arrived = false;
    private FVector _ArrivalLocation = FVector::ZeroVector;

    // The shove, and everything sampled from it onward.
    private FVector _ShoveFromLocation = FVector::ZeroVector;

    private int32 _FramesSinceShove = 0;
    private bool _TagClearObserved = false;
    private int32 _FramesToTagClear = -1;
    private ECk_Nav_PathStatus _StatusAtTagClear = ECk_Nav_PathStatus::None;
    private ECk_CrowdAgent_MovementState _StateAtTagClear = ECk_CrowdAgent_MovementState::None;
    private float _ZAtTagClear = 0.0;

    private float _MaxZAfterTagClear = 0.0;
    private int32 _FramesAfterTagClear = 0;

    private bool _HandshakeTraversingAtClearStep = true;
    private int32 _CompletionsAtClearStep = 0;

    private FString _Verdict = "incomplete";
    private bool _Reported = false;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stand a deck on the origin floor",                 n"Step_StageDeck");
        Add_Step_WaitUntil("the deck reaches the Jolt static world",           n"Check_DeckBodyAdded",         BodyFrameBudget);
        Add_Step(          "stage a GroundNav field over the origin floor",    n"Step_StageField");
        Add_Step_WaitUntil("the origin field reports itself built",            n"Check_OriginFieldBuilt",      BuildFrameBudget);
        Add_Step(          "switch the world onto GroundNav",                  n"Step_SwitchProvider");
        Add_Step_WaitUntil("the surface settles after the provider switch",    n"Check_SurfaceSettled",        SettleFrameBudget);
        Add_Step(          "author the ladder up the deck's south face",       n"Step_AuthorLadder");
        Add_Step_WaitUntil("the surface settles after the ladder",             n"Check_SurfaceSettled",        SettleFrameBudget);
        Add_Step(          "the ladder is live and the volume names its id",   n"Step_AssertLadderLive");
        Add_Step(          "spawn the walker and send it up onto the deck",    n"Step_SpawnAgent");
        Add_Step_WaitUntil("the walker is Walking an installed route",         n"Check_WalkingInstalledRoute", WalkingFrameBudget);
        Add_Step_WaitUntil("the crossing is announced",                        n"Check_TraversalBegun",        SignalFrameBudget);
        Add_Step_WaitUntil("the body is genuinely up on the ladder",           n"Check_BodyIsOnTheLadder",     WalkingFrameBudget);
        Add_Step(          "shove the walker off its corridor mid-crossing",   n"Step_ShoveSideways");
        Add_Step_WaitUntil("the crossing ends",                                n"Check_CrossingEnded",         CrossingEndFrameBudget);
        Add_Step(          "the guard ended it, not the install seam",         n"Step_AssertGuardEndedIt");
        Add_Step_WaitUntil("the walker is Walking again",                      n"Check_WalkingAgain",          WalkingFrameBudget);
        Add_Step_WaitUntil("the walker reaches the deck post",                 n"Check_Arrived",               ArrivalFrameBudget);
        Add_Step(          "the body never rose while it had no route",        n"Step_AssertHeldAndArrived");
        Add_Step(          "hand the world back",                              n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Staging - the deck goes in BEFORE the field, because the field bakes what
    // the Jolt static world holds at the moment the build starts.
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_StageDeck(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _DeckEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _DeckEntity.Request_OverrideToSelf();
        _DeckEntity.Set_DebugName(n"AutoTest_GroundNav_ShovedCrossingDeck");

        // The floor readers on the fixture are only valid after staging, and staging is a step away,
        // so the deck is placed against the LEVEL's own floor actor. Both resolve to the same ground.
        const auto Centre = Get_LevelFloorCentre();
        const auto TopZ = Get_LevelFloorTopZ();

        utils_transform::Add(_DeckEntity,
            FTransform(FRotator::ZeroRotator,
                FVector(Centre.X + DeckOffsetX, Centre.Y, TopZ + DeckHalfZ)),
            ECk_Replication::DoesNotReplicate);

        auto DeckShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        DeckShape.Set_HalfExtents(FVector(DeckHalfXY, DeckHalfXY, DeckHalfZ));

        auto DeckParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        DeckParams.Set_ShapeDimensions(DeckShape);
        DeckParams.Set_MotionType(ECk_MotionType::Static);

        _DeckBody = utils_jolt_body::Add(_DeckEntity, DeckParams);

        Assert_True(ck::IsValid(_DeckBody),
            "the deck's Jolt body must be valid - the field bakes from the Jolt static world, so a deck that never got a body leaves a flat floor with no island on it and nothing for the ladder to climb");
    }

    UFUNCTION()
    private void Check_DeckBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_jolt_body::Get_IsBodyAdded(_DeckBody));
    }

    UFUNCTION()
    private void Step_StageField(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (_Field.Request_StageOriginField(_SelfHandle) == false)
        { FinishFailure(_Field.Get_StagingError()); }
    }

    // The fixture exposes predicate BODIES, not UFUNCTIONs: Do_EvaluatePredicate binds the named
    // predicate against THIS object, so every wait needs its own one-line forwarder here.
    UFUNCTION()
    private void Check_OriginFieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_OriginFieldBuilt(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Step_SwitchProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Field.Request_KickSettleCount();

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
        _ProviderSwapped = true;

        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::GroundNav,
            f"the world must report the provider it was told to answer on (got {ProviderNow})");
    }

    //------------------------------------------------------------------------
    // The ladder
    //------------------------------------------------------------------------

    // Built once, so the enabled form cannot drift. The id is -1 because the VOLUME assigns it.
    private FCk_Request_GroundNavVolume_Link Get_LadderRequest(ECk_EnableDisable InEnable)
    {
        auto Record = FCk_GroundNav_LinkRecord(-1, Get_LadderFoot(), Get_LadderTop());

        Record.Set_Direction(ECk_GroundNav_LinkDirection::Bidirectional)
              .Set_CostMultiplierForward(1.0f)
              .Set_CostMultiplierBackward(1.0f)
              .Set_ClearanceUu(float32(LadderClearanceUu))
              .Set_Enable(InEnable);

        return FCk_Request_GroundNavVolume_Link(_LinkEntity, Record);
    }

    UFUNCTION()
    private void Step_AuthorLadder(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Volume = _Field.Get_OriginVolume();

        Assert_True(ck::IsValid(Volume),
            "the fixture must hand back a valid volume before a link can be authored against it");

        _LinkEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _LinkEntity.Request_OverrideToSelf();
        _LinkEntity.Set_DebugName(n"AutoTest_GroundNav_ShovedCrossingLadder");

        utils_ground_nav_volume::Request_Link(Volume, Get_LadderRequest(ECk_EnableDisable::Enable),
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
    private void Step_AssertLadderLive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_LinkCompletions, 1,
            "the link request's completion delegate must fire exactly once");

        Assert_True(_LastLinkResult == ECk_Request_OperationResult::Succeeded,
            f"both endpoints stand on walkable cells and the clearance admits the agent, so admission must complete Succeeded (got {_LastLinkResult})");

        Assert_True(utils_ground_nav_volume::Get_IsLinkLive(_LinkEntity),
            "the surface reported itself settled after the ladder was authored, so it must already be in effect - a route planned against a link that is not live carries no span at all");

        auto Records = utils_ground_nav_volume::Get_LinkRecords(_Field.Get_OriginVolume());

        Assert_Equals_Int(Records.Num(), 1,
            "one link was authored against this volume, so the reflected read-back must carry exactly one record");

        if (Records.Num() != 1)
        { return; }

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
        const auto Goal = Get_DeckPost();

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"GroundNav_ShovedCrossing_Walker");

        // YAW ONLY: a post standing higher than the spawn is a fact about the route, not about
        // which way the body faces.
        const auto Facing = FRotator(0.0, (Goal - Spawn).Rotation().Yaw, 0.0);

        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(Facing, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        // Held, unlike the sibling's, because the shove goes through the TRANSFORM feature: an
        // external displacement is a SetTransform, not a crowd request.
        _AgentTransform = AgentTransform;

        _Agent = utils_crowd_agent::Add(AgentTransform,
            FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight)));

        Assert_True(ck::IsValid(_Agent), "Add() must return a valid crowd agent handle");

        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);

        // Composed here with the params the crowd's own GroundNav dispatch would have used, purely so
        // this fixture holds the handle it needs: the dispatch adds the feature only when it is
        // missing, so what runs is identical either way.
        _Planner = utils_ground_nav_path::Add(_AgentEntity,
            FCk_Fragment_GroundNavPath_ParamsData(float32(AgentRadius)));

        Assert_True(ck::IsValid(_Planner), "Add() must return a valid GroundNav path handle");

        // The handshake is HANDLE-scoped, so the binding is made on the traverser itself - the same
        // entity the crowd's steering issues the requests against.
        utils_nav_surface_link_traversal::BindTo_OnLinkTraversalBegun(_AgentEntity,
            FCk_Delegate_NavSurface_OnLinkTraversalBegun(this, n"OnLinkTraversalBegun"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav_surface_link_traversal::BindTo_OnLinkTraversalCompleted(_AgentEntity,
            FCk_Delegate_NavSurface_OnLinkTraversalCompleted(this, n"OnLinkTraversalCompleted"),
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
    private void OnLinkTraversalBegun(FCk_Handle InTraverser, int32 InLinkId, int32 InCorrelatorId)
    {
        if (IsFinished()) { return; }

        _BegunCount += 1;

        if (_BegunCount == 1)
        { _FirstBegunCorrelator = InCorrelatorId; }
    }

    // TWO crossings are expected across this run - the one that is abandoned, and the one the
    // walker actually rides onto the deck after its re-path - so only the FIRST is recorded. It is
    // the abandoned one, and it is the one every claim below is about.
    UFUNCTION()
    private void OnLinkTraversalCompleted(FCk_Handle InTraverser, int32 InLinkId, int32 InCorrelatorId, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _CompletedCount += 1;

        if (_CompletedCount == 1)
        {
            _CrossingEndCorrelator = InCorrelatorId;
            _CrossingEndResult = InResult;
        }
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        if (_Arrived) { return; }

        _Arrived = true;
        _ArrivalLocation = Get_AgentLocation();
    }

    // Expected ZERO times. The ladder is live the whole run and the deck is reachable from the floor
    // the walker was shoved onto, so a failure here is the defect wearing a different costume: a
    // body left off every walkable cell cannot plan from where it stands and answers
    // StartProjectFailed. Failed HERE so the reason the walker gave is in the message rather than
    // lost behind an expired arrival budget.
    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

        _GoalFailures += 1;
        _GoalFailureReasons += f"[{InInfo.Get_Reason()}/{InInfo.Get_NavFailReason()}]";

        Teardown();
        FinishFailure(f"the walker reported OnGoalFailed ({InInfo.Get_Reason()} / {InInfo.Get_NavFailReason()}) after being shoved 500uu sideways onto open floor with the ladder still live. The displacement it was given lands on a walkable cell, so the re-path issued from it has a start to project and a deck to reach.");
    }

    UFUNCTION()
    private void Check_WalkingInstalledRoute(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking);
    }

    UFUNCTION()
    private void Check_TraversalBegun(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BegunCount >= 1);
    }

    // The cursor stands within the span from the install onward, so Begun fires hundreds of uu before
    // the body leaves the floor. What makes the shove below MID-crossing is the body's own height
    // above the foot, not the signal.
    UFUNCTION()
    private void Check_BodyIsOnTheLadder(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(float(Get_AgentLocation().Z) >= float(Get_LadderFoot().Z) + MidCrossingLiftUu);
    }

    //------------------------------------------------------------------------
    // The shove
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_ShoveSideways(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_nav_surface_link_traversal::Get_IsTraversingLink(_AgentEntity),
            "the crossing must still be the traverser's ACTIVE one when the body is shoved - a displacement issued after it ended would take nothing away from a crossing, and every claim below would be about nothing");

        Assert_True(utils_crowd_agent::Get_IsTraversingLink(_Agent),
            "FTag_CrowdAgent_TraversingLink must still stand on the agent when it is shoved: that tag, not the handshake, is what licenses FProcessor_CrowdAgent_ConstrainToNavmesh to stand its surface walk down, and the guard this file pins is the one that ends the crossing when the tag outlives Walking");

        // The POSITIVE that makes the tag clearing below a TRANSITION rather than a predicate that
        // was already true when the wait opened.
        Assert_True(utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking,
            f"the walker must still be Walking its route when it is shoved - the crossing tag is ADDITIVE, and BlockDetect's off-path tier views Walking, so a body that had already left Walking would never reach the re-path that opens the guard's window (got {utils_crowd_agent::Get_MovementState(_Agent)})");

        _ShoveFromLocation = Get_AgentLocation();

        // The origin floor's own top face, 500uu along -X from the ladder. -X because the deck (and
        // therefore the island) stands at +X, so this is open walkable floor. The constraint places
        // an agent's transform ON the surface it walks (ResolveSurfaceOffset returns
        // surface - feet), which is why the ladder foot's Z is the right resting Z here.
        const auto Foot = Get_LadderFoot();
        const auto Destination = FVector(Foot.X - ShoveOffPathUu, Foot.Y, Foot.Z);

        const auto Current = utils_transform::Get_EntityCurrentTransform(_AgentTransform);

        // Deliberately NOT preceded by Request_Stop: the ACTIVE move must survive the displacement.
        // Cancelling it first would end the crossing through the ordinary stop path and the guard
        // would never be reached - which is the whole scenario.
        utils_transform::Request_SetTransform(_AgentTransform,
            FCk_Request_Transform_SetTransform(
                FTransform(Current.GetRotation(), Destination, Current.GetScale3D())));
    }

    // Sampled EVERY poll from the shove onward, because the discriminator is a per-frame ordering
    // fact: the frame the crowd tag clears is the frame whose nav-slot status separates "the guard
    // ended it" (Pending, the re-path still in flight) from "the install seam ended it" (Ready).
    UFUNCTION()
    private void Check_CrossingEnded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (_TagClearObserved)
        {
            Res.Set(true);
            return;
        }

        if (ck::Is_NOT_Valid(_Agent))
        {
            Res.Set(false);
            return;
        }

        _FramesSinceShove += 1;

        const auto CrowdTraversing = utils_crowd_agent::Get_IsTraversingLink(_Agent);
        const auto Status = utils_nav::Get_PathStatus(_AgentEntity);
        const auto State = utils_crowd_agent::Get_MovementState(_Agent);
        const auto Z = float(Get_AgentLocation().Z);

        if (CrowdTraversing == false)
        {
            _TagClearObserved = true;
            _FramesToTagClear = _FramesSinceShove;
            _StatusAtTagClear = Status;
            _StateAtTagClear = State;
            _ZAtTagClear = Z;
            _MaxZAfterTagClear = Z;
        }

        Res.Set(_TagClearObserved);
    }

    UFUNCTION()
    private void Step_AssertGuardEndedIt(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Read HERE rather than at the clearing poll, and that is a fact about the machinery, not a
        // convenience: DoCancelActiveLinkTraversal removes the crowd tag synchronously
        // (CkCrowdAgent_Steering_Processor.cpp:429) but ENQUEUES the handshake's ending as a request
        // (CkNavSurface_Utils.cpp:592-593), which FProcessor_NavSurface_LinkTraversal_HandleRequests
        // drains on its own pass. The handshake therefore clears at least one pass after the tag
        // does, and this step is the first frame after the wait resolved.
        //
        // The sampler is called here too, so no frame the sequencer spends between the two waits
        // around this step goes unobserved by the no-rise claim.
        Do_SampleAfterTagClear();

        _HandshakeTraversingAtClearStep = utils_nav_surface_link_traversal::Get_IsTraversingLink(_AgentEntity);
        _CompletionsAtClearStep = _CompletedCount;

        Assert_True(_StatusAtTagClear == ECk_Nav_PathStatus::Pending,
            f"the crowd's crossing tag cleared on a frame whose nav slot read {_StatusAtTagClear}. Pending is the guard's own case - the off-path re-path removed Walking, added PathPending and left TraversingLink standing, and FProcessor_CrowdAgent_ConstrainToNavmesh ended the crossing while that answer was still in flight. Ready here means the install seam ended it instead (CkCrowdAgent_OnGroundNavPathResolved_Processor.cpp:132-134) and the guard was never reached at all, so this run pins nothing.");

        Assert_True(_StateAtTagClear != ECk_CrowdAgent_MovementState::Walking,
            f"the crossing must have ended on a frame where the agent was NOT Walking (state was {_StateAtTagClear}). Walking there means something other than the guard cleared the tag: the guard's whole condition is a TraversingLink agent that has left its route, and an agent still Walking has not.");
    }

    // The frames between the ending and the next installed route: the body has no route, and a body
    // with no route must not rise. Stops sampling the moment it is Walking again, because from then
    // on climbing the ladder is exactly what it is supposed to do.
    private void Do_SampleAfterTagClear()
    {
        if (_TagClearObserved == false) { return; }
        if (ck::Is_NOT_Valid(_Agent)) { return; }
        if (utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking) { return; }

        _FramesAfterTagClear += 1;

        const auto Z = float(Get_AgentLocation().Z);

        if (Z > _MaxZAfterTagClear)
        { _MaxZAfterTagClear = Z; }
    }

    UFUNCTION()
    private void Check_WalkingAgain(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_SampleAfterTagClear();

        auto Res = OutResult;
        Res.Set(utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking);
    }

    UFUNCTION()
    private void Check_Arrived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Arrived);
    }

    //------------------------------------------------------------------------
    // The contract
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertHeldAndArrived(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto ShoveFromZ = float(_ShoveFromLocation.Z);

        ck::nav::Display(f"[GROUNDNAV-SHOVE] framesToTagClear={_FramesToTagClear} statusAtClear={_StatusAtTagClear} stateAtClear={_StateAtTagClear} zAtClear={_ZAtTagClear} maxZAfterClear={_MaxZAfterTagClear} arrived={_Arrived} goalFailures={_GoalFailures}");

        Assert_True(_MaxZAfterTagClear <= _ZAtTagClear + ClimbToleranceUu,
            f"the body rose to Z {_MaxZAfterTagClear} over the {_FramesAfterTagClear} frames it spent with no route, from the {_ZAtTagClear} it stood at when its crossing ended (it was shoved there from Z {ShoveFromZ}). A body whose crossing is over does not climb until it is walking a route again: with the crossing tag left standing, ConstrainToNavmesh keeps its surface walk down and Steering's 3D aim at the ladder exit is applied verbatim.");

        Assert_True(_HandshakeTraversingAtClearStep == false,
            "the handshake must read NOT traversing once the ending has drained - a body that is crossing nothing owes every listener that answer, and the two halves of the state (the crowd tag and the handshake's own record) must never be able to disagree about whether a crossing is live");

        Assert_True(_CompletionsAtClearStep >= 1,
            f"the abandoned crossing must be REPORTED, not dropped: by the step after the tag cleared, OnLinkTraversalCompleted had fired {_CompletionsAtClearStep} time(s). A listener gating a ladder animation on it is otherwise held forever on a climb that stopped.");

        Assert_True(_CrossingEndResult == ECk_Request_OperationResult::Failed_Cancelled,
            f"the body did not walk off the ladder's far end - it was shoved off its route part-way up - so a listener deciding whether it ARRIVED is owed Failed_Cancelled and never Succeeded (got {_CrossingEndResult})");

        Assert_Equals_Int(_CrossingEndCorrelator, _FirstBegunCorrelator,
            f"a correlator names ONE crossing, so the first completion must name the crossing Begun announced (completion says {_CrossingEndCorrelator}, Begun said {_FirstBegunCorrelator})");

        Assert_Equals_Int(_GoalFailures, 0,
            f"the ladder was live for the whole run and the shove lands on open walkable floor, so the walker's active move must survive the displacement by RE-PLANNING and never by failing (got {_GoalFailures} failures: {_GoalFailureReasons})");

        Assert_True(_Arrived,
            "the walker must reach the deck post: the re-path plans from the floor it was shoved onto, over the same ladder, and it climbs it for real");

        const auto DistanceToGoalUu = float((_ArrivalLocation - Get_DeckPost()).Size());
        const auto ArrivalZ = float(_ArrivalLocation.Z);
        const auto TopZ = float(Get_LadderTop().Z);

        Assert_True(DistanceToGoalUu <= ArrivalProximityUu,
            f"OnGoalReached is broadcast by the final-stop branch, so the body that reported it stands at the goal it was given ({DistanceToGoalUu}uu away)");

        Assert_True(ArrivalZ >= TopZ - RestToleranceUu,
            f"the deck top is an island 200uu proud of the floor and the ladder is the only way onto it, so an arrival has to be up ON it (body Z {ArrivalZ}, deck Z {TopZ})");
    }

    //------------------------------------------------------------------------
    // Geometry. The level floor readers answer before the fixture has staged;
    // the fixture's own readers answer afterwards and resolve to the same ground.
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

    private FVector Get_LadderFoot()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + DeckOffsetX, Centre.Y + LadderFootOffsetY, _Field.Get_FloorTopZ());
    }

    private FVector Get_LadderTop()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + DeckOffsetX, Centre.Y + LadderTopOffsetY,
            _Field.Get_FloorTopZ() + 2.0 * DeckHalfZ);
    }

    private FVector Get_SpawnPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + DeckOffsetX, Centre.Y + SpawnOffsetY,
            _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
    }

    private FVector Get_DeckPost()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + DeckOffsetX, Centre.Y,
            _Field.Get_FloorTopZ() + 2.0 * DeckHalfZ + AgentCentreOffsetZ);
    }

    private FVector Get_AgentLocation()
    {
        if (ck::Is_NOT_Valid(_AgentEntity))
        { return _ShoveFromLocation; }

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

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. The provider is a WORLD
    // selection every later fixture in this map reads, and the field would otherwise stay staged for
    // the rest of the lane.
    private void Teardown()
    {
        if (_Reported == false)
        {
            _Reported = true;
            _Field.Do_ReportCrossover("Link_ShovedMidCrossingEndsTheCrossingAndResumes", _Verdict);
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

        if (ck::IsValid(_DeckEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_DeckEntity);
            _DeckEntity = FCk_Handle();
        }
    }
}
