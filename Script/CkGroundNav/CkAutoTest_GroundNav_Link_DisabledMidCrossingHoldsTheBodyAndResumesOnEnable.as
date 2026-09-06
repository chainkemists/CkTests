// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A LINK DISABLED MID-CROSSING
//============================================================================
//
// What happens to a BODY when the ground under its route is taken away while it
// is part-way across an authored link. The ROUTE half of that is already pinned
// (Link_DisableReplansOnlyTheAgentsUsingIt); this is the body half, and it is
// the half that failed in the field: two walkers on a ladder in the GroundNav
// Links gym rose into the sky when the links were toggled off and back on, each
// then reporting UNREACHABLE: Failed (StartProjectFailed).
//
// The scene is a DECK: a 400uu box standing 200uu proud of the origin floor, so
// its top face is an ISLAND - nothing walks up a 200uu vertical wall. One
// bidirectional ladder joins the floor south of it to its top, which is the only
// way on. A walker is sent up, and the ladder is disabled while its crossing is
// the traverser's ACTIVE one.
//
//----------------------------------------------------------------------------
// WHAT IS PINNED
//----------------------------------------------------------------------------
//
//   1. The crossing ENDS. A body whose route was dropped out from under it is
//      crossing nothing, so Get_IsTraversingLink answers false and the handshake
//      REPORTS the abandoned crossing rather than dropping it.
//   2. The body does not CLIMB. Its Z never rises above where it stood when the
//      crossing was interrupted, sampled every frame across the hold window.
//      FTag_CrowdAgent_TraversingLink is what licenses
//      FProcessor_CrowdAgent_ConstrainToNavmesh to stand its surface walk down;
//      left standing on a body with no route it turns the agent into a free 3D
//      body whose staged displacement is applied verbatim - and reports it ON
//      the mesh while it does, so nothing else in the frame notices.
//   3. The body is GROUNDED, at one of the ladder's two ENDS. A ladder joins two
//      walkable cells with nothing in between, so the foot and the top are the
//      only recoverable resting places. WHICH one is the ordinary constraint's
//      business - it recovers onto the nearest walkable cell and refuses to LIFT
//      beyond a step - and this asserts only that the body ended on one of them.
//   4. The walker RESUMES. Re-enable the ladder, re-issue the same goal with
//      ForceRepath, and it walks and arrives. That is exactly what a body parked
//      in mid-air cannot do: a start that projects onto no walkable cell answers
//      StartProjectFailed, every time, forever.
//
// Ensures are not asserted explicitly - the AutoTest harness escalates a fired
// ensure to a failure on its own, so a grounding pass that ensured its way out
// of this state fails here rather than passing quietly.
//============================================================================

class UCk_AutoTest_GroundNav_Link_DisabledMidCrossingHoldsTheBodyAndResumesOnEnable : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 300.0f;

    //------------------------------------------------------------------------
    // Geometry - offsets from the origin floor's own centre and top face.
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

    // Wide enough that admission is never the variable under test. The gym's 40uu ladder carries a
    // separate claim, about two bodies sharing one rung.
    private const float LadderClearanceUu = 100.0;

    private const float SpawnOffsetY = -600.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;
    private const float AgentCentreOffsetZ = 100.0;

    // The fixture's bake cell height. A body resting on a walkable cell is within a few of them of
    // that cell's own Z; further than that is a body standing on nothing.
    private const float RestToleranceUu = 30.0;

    // How far up the ladder the body must be before the link is pulled. Well clear of the foot's own
    // cell and of the settle noise around it, so "mid-crossing" is a fact rather than a guess.
    private const float MidCrossingLiftUu = 60.0;

    // Slack on the no-climb claim: one frame of braking residual along the ladder's own direction is
    // admissible, a body that gains a body-height is not.
    private const float ClimbToleranceUu = 25.0;

    private const float ArrivalProximityUu = 200.0;

    //------------------------------------------------------------------------
    // Budgets - every one a ceiling on a NAMED condition.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SettleFrameBudget = 3600;
    private const int32 WalkingFrameBudget = 1800;
    private const int32 SignalFrameBudget = 1800;
    private const int32 ArrivalFrameBudget = 3600;

    // The window the no-climb and grounded claims are made over. Kept as a frame count on purpose:
    // "the body did not drift" is a NEGATIVE and cannot become a named condition - it is already
    // true the moment the wait opens, so any predicate built from it would return before the drift
    // it exists to catch. What makes the silence mean something is the positive sequence ahead of
    // it (a route installed, a crossing announced, the body genuinely up the ladder, the walker
    // stopped). Sized longer than the grounding lease's own verify interval, so a body reconciled
    // only on that cadence has had its pass before this closes.
    private const int32 HoldWindowFrames = 120;

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
    private bool _ArrivedAfterResume = false;
    private FVector _ArrivalLocation = FVector::ZeroVector;

    // Sampled the frame the ladder goes away, and every frame of the hold window after it.
    private FVector _InterruptLocation = FVector::ZeroVector;
    private float _MaxHoldZ = 0.0;
    private int32 _HeldFrames = 0;
    private bool _TraversingDuringHold = false;

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
        Add_Step(          "disable the ladder under the crossing",            n"Step_DisableLadder");
        Add_Step_WaitUntil("the walker stops",                                 n"Check_WalkerStopped",         SettleFrameBudget);
        Add_Step_WaitUntil("the hold window closes",                           n"Check_HoldWindowClosed",      SettleFrameBudget);
        Add_Step(          "the body held at a ladder end and never climbed",  n"Step_AssertHeldAndGrounded");
        Add_Step(          "re-enable the ladder and re-ask for the deck",     n"Step_EnableAndRetry");
        Add_Step_WaitUntil("the surface settles after the re-enable",          n"Check_SurfaceSettled",        SettleFrameBudget);
        Add_Step_WaitUntil("the walker is Walking again",                      n"Check_WalkingAgain",          WalkingFrameBudget);
        Add_Step_WaitUntil("the walker reaches the deck post",                 n"Check_ArrivedAfterResume",    ArrivalFrameBudget);
        Add_Step(          "the walker stands on the deck",                    n"Step_AssertResumed");
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
        _DeckEntity.Set_DebugName(n"AutoTest_GroundNav_MidCrossingDeck");

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

    // Built once, so the enabled and disabled forms cannot drift. The id is -1 because the VOLUME
    // assigns it, and naming the SAME entity is what updates the record in place and keeps the id
    // the walker's corridor cached rather than retiring it for a new one.
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
        _LinkEntity.Set_DebugName(n"AutoTest_GroundNav_MidCrossingLadder");

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
        _AgentEntity.Set_DebugName(n"GroundNav_MidCrossing_Walker");

        // YAW ONLY: a post standing higher than the spawn is a fact about the route, not about
        // which way the body faces.
        const auto Facing = FRotator(0.0, (Goal - Spawn).Rotation().Yaw, 0.0);

        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(Facing, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

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

        // Three link requests have completed only once the ladder is back, so this counts the
        // arrival AFTER the re-enable and never one on the way up.
        if (_LinkCompletions < 3) { return; }

        _ArrivedAfterResume = true;
        _ArrivalLocation = Get_AgentLocation();
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

        // Expected exactly once, when the deck becomes an island under the walker. A failure after
        // the ladder is back is the defect this file is about, and it is failed HERE so the reason
        // the walker gave is in the message rather than lost behind an expired arrival budget.
        _GoalFailures += 1;
        _GoalFailureReasons += f"[{InInfo.Get_Reason()}/{InInfo.Get_NavFailReason()}]";

        if (_LinkCompletions < 3) { return; }

        Teardown();
        FinishFailure(f"the walker reported OnGoalFailed ({InInfo.Get_Reason()} / {InInfo.Get_NavFailReason()}) after the ladder was re-enabled and its goal re-issued with ForceRepath. A body parked off every walkable cell cannot plan from where it stands, so this is what a crossing that outlived its route looks like one step later.");
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
    // the body leaves the floor. What makes the disable below MID-crossing is the body's own height
    // above the foot, not the signal.
    UFUNCTION()
    private void Check_BodyIsOnTheLadder(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(float(Get_AgentLocation().Z) >= float(Get_LadderFoot().Z) + MidCrossingLiftUu);
    }

    //------------------------------------------------------------------------
    // The disable, and the hold window it opens
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_DisableLadder(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_nav_surface_link_traversal::Get_IsTraversingLink(_AgentEntity),
            "the crossing must still be the traverser's ACTIVE one when the ladder is pulled - a disable issued after it ended would take nothing away from the body, and every claim below would be about nothing");

        // The POSITIVE that makes the stop below a transition rather than a predicate that was
        // already true when the wait opened.
        Assert_True(utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking,
            f"the walker must still be Walking its route when the ladder is pulled - the crossing tag is ADDITIVE, so a body part-way up a ladder is still walking the polyline it was handed (got {utils_crowd_agent::Get_MovementState(_Agent)})");

        _InterruptLocation = Get_AgentLocation();
        _MaxHoldZ = float(_InterruptLocation.Z);

        utils_ground_nav_volume::Request_Link(_Field.Get_OriginVolume(),
            Get_LadderRequest(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinkCompleted"));

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void Check_WalkerStopped(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_SampleHold();

        auto Res = OutResult;
        Res.Set(utils_crowd_agent::Get_MovementState(_Agent) != ECk_CrowdAgent_MovementState::Walking);
    }

    UFUNCTION()
    private void Check_HoldWindowClosed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        Do_SampleHold();

        auto Res = OutResult;
        Res.Set(_HeldFrames >= HoldWindowFrames);
    }

    // Every frame from the disable onward, so the no-climb claim is about the whole hold rather than
    // about whichever frame a step boundary happened to land on.
    private void Do_SampleHold()
    {
        if (ck::Is_NOT_Valid(_Agent)) { return; }

        _HeldFrames += 1;

        const auto Z = float(Get_AgentLocation().Z);

        if (Z > _MaxHoldZ)
        { _MaxHoldZ = Z; }

        // Judged from the frame the handshake reported the crossing ENDED, not from the first held
        // frame: the ending is the grounding pass's work, and this timer can sample a frame ahead of
        // it. A tag still standing AFTER the completion fired is the defect this pins.
        if (_CompletedCount > 0 && utils_nav_surface_link_traversal::Get_IsTraversingLink(_AgentEntity))
        { _TraversingDuringHold = true; }
    }

    UFUNCTION()
    private void Step_AssertHeldAndGrounded(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto FootZ = float(Get_LadderFoot().Z);
        const auto TopZ = float(Get_LadderTop().Z);
        const auto RestZ = float(Get_AgentLocation().Z);
        const auto InterruptZ = float(_InterruptLocation.Z);
        const auto OffMesh = utils_crowd_agent::Get_IsOffNavmesh(_Agent);

        ck::nav::Display(f"[GROUNDNAV-LINK-MIDCROSSING] linkId={_AuthoredLinkId} begun={_BegunCount} completed={_CompletedCount} endResult={_CrossingEndResult} interruptZ={InterruptZ} maxHoldZ={_MaxHoldZ} restZ={RestZ} footZ={FootZ} topZ={TopZ} heldFrames={_HeldFrames} offNavmesh={OffMesh} goalFailures={_GoalFailures} begunCorr={_FirstBegunCorrelator} endCorr={_CrossingEndCorrelator} traversingAfterEnd={_TraversingDuringHold} goalFailureReasons={_GoalFailureReasons}");

        Assert_Equals_Int(_CompletedCount, 1,
            f"the route the crossing was riding was dropped out from under it, so the crossing must be reported ENDED exactly once - a listener gating a ladder animation on it is otherwise held forever on a climb that stopped (got {_CompletedCount})");

        Assert_True(_CrossingEndResult == ECk_Request_OperationResult::Failed_Cancelled,
            f"the body did not walk off the ladder's far end - the ground under its route went away - so a listener deciding whether it ARRIVED is owed Failed_Cancelled and never Succeeded (got {_CrossingEndResult})");

        Assert_Equals_Int(_CrossingEndCorrelator, _FirstBegunCorrelator,
            f"a correlator names ONE crossing, so the completion must name the crossing Begun announced (completion says {_CrossingEndCorrelator}, Begun said {_FirstBegunCorrelator})");

        Assert_True(_TraversingDuringHold == false,
            "a body with no route is crossing nothing, so Get_IsTraversingLink must answer false on every held frame from the one the crossing was reported ended. FTag_CrowdAgent_TraversingLink is what licenses FProcessor_CrowdAgent_ConstrainToNavmesh to stand its surface walk down AND to report the body on the mesh - left standing on an agent that is not Walking it makes a free 3D body that nothing in the frame is grounding, and Steering, the only thing that can clear it, needs Walking to run.");

        Assert_True(_MaxHoldZ <= InterruptZ + ClimbToleranceUu,
            f"the body must not CLIMB once its crossing is over: it rose to Z {_MaxHoldZ} over {_HeldFrames} held frames from the {InterruptZ} it stood at when the ladder was pulled. Steering aims at the exit waypoint in 3D, and an unconstrained body keeps whatever +Z the ladder gave it.");

        Assert_True(OffMesh == false,
            f"the body must end the hold ON walkable ground: a ladder joins two cells with nothing in between, so a body left between them can never plan again - every start projects onto nothing and answers StartProjectFailed (off the navmesh for {utils_crowd_agent::Get_SecondsOffNavmesh(_Agent)}s at Z {RestZ})");

        const auto DropToFoot = RestZ - FootZ;
        const auto DropToDeck = RestZ - TopZ;
        const auto RestsAtFoot = DropToFoot <= RestToleranceUu && DropToFoot >= -RestToleranceUu;
        const auto RestsOnDeck = DropToDeck <= RestToleranceUu && DropToDeck >= -RestToleranceUu;

        Assert_True(RestsAtFoot || RestsOnDeck,
            f"an interrupted crossing must end the body at one of the ladder's two ENDS - the ordinary constraint recovers onto the nearest walkable cell and refuses to lift beyond a step, so WHICH end is its answer, but between them is not one of the answers (rest Z {RestZ}, foot {FootZ}, deck {TopZ})");
    }

    //------------------------------------------------------------------------
    // The re-enable
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_EnableAndRetry(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_ground_nav_volume::Request_Link(_Field.Get_OriginVolume(),
            Get_LadderRequest(ECk_EnableDisable::Enable),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinkCompleted"));

        _Field.Request_KickSettleCount();

        // ForceRepath, exactly as the gym's retry key does: the walker is held on a goal that failed,
        // and the same goal restated is otherwise the deliberate no-op guarding against a noisy
        // re-issuer. This is the one override that clears the failure hold.
        auto Retry = FCk_Request_CrowdAgent_MoveTo(Get_DeckPost());
        Retry.Set_ForceRepath(true);

        utils_crowd_agent::Request_MoveTo(_Agent, Retry);
    }

    UFUNCTION()
    private void Check_WalkingAgain(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Walking);
    }

    UFUNCTION()
    private void Check_ArrivedAfterResume(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ArrivedAfterResume);
    }

    UFUNCTION()
    private void Step_AssertResumed(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto DistanceToGoalUu = float((_ArrivalLocation - Get_DeckPost()).Size());
        const auto ArrivalZ = float(_ArrivalLocation.Z);
        const auto TopZ = float(Get_LadderTop().Z);

        Assert_True(DistanceToGoalUu <= ArrivalProximityUu,
            f"OnGoalReached is broadcast by the final-stop branch, so the body that reported it stands at the goal it was given ({DistanceToGoalUu}uu away)");

        Assert_True(ArrivalZ >= TopZ - RestToleranceUu,
            f"the deck top is an island 200uu proud of the floor and the ladder is the only way onto it, so an arrival has to be up ON it (body Z {ArrivalZ}, deck Z {TopZ})");

        Assert_Equals_Int(_GoalFailures, 1,
            f"the deck was unreachable exactly once - while the ladder was disabled - so exactly one OnGoalFailed belongs to this run (got {_GoalFailures})");
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
        { return _InterruptLocation; }

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
            _Field.Do_ReportCrossover("Link_DisabledMidCrossingHoldsTheBodyAndResumesOnEnable", _Verdict);
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

// Hand-authored so the wrapper can register the one Warning this run expects: the crowd's Failed
// branch reports the deck's failure as "PathPending -> Idle (path failed: ..)" at Warning
// verbosity, and the harness escalates any Warning to a test failure. The generator skips a test
// whose wrapper already exists. Registered as a plain substring (AddExpectedErrorPlain, Contains,
// suppress-all) - no regex.
class ACk_AutoTest_GroundNav_Link_DisabledMidCrossingHoldsTheBodyAndResumesOnEnable_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 300.0f;

    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_GroundNav_Link_DisabledMidCrossingHoldsTheBodyAndResumesOnEnable");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        // FProcessor_CrowdAgent_OnPathResolved, Failed branch: "CrowdAgent [..] PathPending -> Idle (path failed: ..)"
        Out.Add("(path failed:");
        return Out;
    }
}
