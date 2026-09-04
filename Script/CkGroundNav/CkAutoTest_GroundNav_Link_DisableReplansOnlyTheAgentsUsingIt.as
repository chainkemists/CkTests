// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: DISABLING A LINK REPLANS ONLY ITS USERS
//============================================================================
//
// The Layer-2 claim the exact-invalidation design exists to make: a link change
// republishes the field, and the ONLY agents that hear about it are the ones
// whose cached corridor actually crosses the link that changed.
//
// A link derive republishes the tiles the link's ends stand in. Judged by
// BOUNDS alone - which is what every other publish is judged by - that reaches
// every corridor inside those tiles, and an agent walking a private errand a
// couple of hundred uu from the link would replan for a change that cannot
// touch its route. The publish note is what narrows it: a run of link-only publishes
// since the last geometry publish is described by the stable link ids it moved,
// and a corridor is flagged only when its own cached ids intersect them.
//
// So the fixture is two crowd agents on ONE field:
//
//   A crosses the link. Its corridor caches the link's id.
//   B walks a short errand entirely INSIDE the tile the link's entry
//     resolves into, west of the wall, crossing nothing. Its corridor caches
//     no link id at all.
//   -> disable the link
//   -> A replans exactly once, onto a route with no link span
//   -> B replans ZERO times, and is still Walking when that is read.
//
// B being STILL WALKING at the assertion is not decoration. A "did not replan"
// read off an agent that had already arrived would be true for the wrong
// reason - an idle agent has no episode to replan - so B is deliberately slow
// enough to be mid-errand throughout, and that is asserted.
//
//----------------------------------------------------------------------------
// THE GEOMETRY, AND THE TILE B HAS TO BE INSIDE
//----------------------------------------------------------------------------
//
// FCkAutoTest_GroundNavFixture bakes 500uu tiles over a volume spanning
// +/-1000uu around the floor's centre, so the tile lattice falls on the floor
// centre offsets -1000, -500, 0, +500 and +1000 in both X and Y. The link's
// entry is authored at (+100, -400), which lands in the tile spanning
// X [0, +500] and Y [-500, 0].
//
// B's start (+40, -60) and goal (+180, -260) are both inside that same tile,
// and both west of the wall's west face at X +250 with more than the body
// radius to spare. B therefore sits squarely inside the ground a
// bounds-only invalidator would flag, which is the only way its zero says
// anything.
//
// The wall runs from Y -1100 to Y +600 at X +300, so it splits the field
// everywhere the link and both agents are, and leaves a 400uu gap at the
// NORTH end - the detour A takes once the link is gone. Without a detour A's
// replan would simply fail, and "the new route carries no link span" would be
// true of a route that does not exist. The gap is at the far end from B, so
// A's detour never comes within four hundred uu of B's errand and cannot push
// it off its own corridor.
//
//----------------------------------------------------------------------------
// HOW A REPLAN IS COUNTED
//----------------------------------------------------------------------------
//
// Per agent, by its own OnPathReady broadcasts. A GroundNav plan is installed
// through the agent's FFragment_Nav_PathResult exactly as a Recast plan is, so
// one OnPathReady IS one installed route - a count this fixture owns end to end
// rather than a number read back out of the system under test. The plan's
// _RequestRevision is logged beside it and never asserted: a shadow query and a
// repair that retried cold both move the revision without installing a second
// route, so it corroborates WHICH plan landed and is not the claim.
//
// The provider is a WORLD selection every later fixture in this map reads, so
// the previous value is captured before the swap and handed back on every exit
// path including DoEndPlay.
//============================================================================

class UCk_AutoTest_GroundNav_Link_DisableReplansOnlyTheAgentsUsingIt : UCk_AutoTest_Base
{
    // A 16-tile bake, four kicked settles, two crowd episodes and a link toggle, each on its own
    // budgeted condition.
    default _TimeoutSeconds = 300.0f;

    //------------------------------------------------------------------------
    // Geometry, as offsets from the floor's own centre and top face.
    //------------------------------------------------------------------------

    // Clear of the floor centre, which is where the fixture probes for the floor.
    private const float WallOffsetX = 300.0;
    private const float WallHalfX = 50.0;

    // Y -1100 .. +600: past the field's southern edge, and stopping 400uu short of its northern
    // one. That gap is the detour, and it is at the opposite end of the field from B.
    private const float WallCentreOffsetY = -250.0;
    private const float WallHalfY = 850.0;
    private const float WallHalfZ = 150.0;

    // The link, over the wall, 150uu of floor between each endpoint and the face it stands beside.
    private const float LinkStartOffsetX = 100.0;
    private const float LinkEndOffsetX = 500.0;
    private const float LinkOffsetY = -400.0;

    private const float LinkClearanceUu = 100.0;
    private const float LinkMultiplier = 1.0;

    // A: across the link, on a lane where the link route (about 1230uu) beats the northern detour
    // (about 2400uu) by a margin no clearance offset can close.
    private const float ALaneY = -300.0;
    private const float AStartX = -500.0;
    private const float AGoalX = 700.0;

    // B: an errand entirely inside the tile the link's entry resolves into, west of the wall.
    private const float BStartX = 40.0;
    private const float BStartY = -60.0;
    private const float BGoalX = 180.0;
    private const float BGoalY = -260.0;

    // B walks its 244uu errand in about twelve seconds - long enough to still be mid-errand when
    // A's replacement route lands, and fast enough that the block detector's 30uu-in-3s progress
    // floor is cleared four times over.
    private const float BMaxSpeed = 20.0;

    // How far A must travel on its REPLACEMENT route before the counters are read. Frames B could
    // have replanned in, bought with a positive rather than with a hop count.
    private const float PostSwapTravelUu = 200.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;
    private const float AgentCentreOffsetZ = 100.0;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 SettleFrameBudget = 3600;
    private const int32 WalkingFrameBudget = 1800;
    private const int32 ReplanFrameBudget = 1800;
    private const int32 TravelFrameBudget = 3600;

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _WallEntity;
    private FCk_Handle _LinkEntity;
    private FCk_Handle _AEntity;
    private FCk_Handle _BEntity;

    private FCk_Handle_JoltBody _WallBody;
    private FCk_Handle_CrowdAgent _AAgent;
    private FCk_Handle_CrowdAgent _BAgent;
    private FCk_Handle_GroundNavPath _APlanner;
    private FCk_Handle_GroundNavPath _BPlanner;

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

    private int32 _AReadyCount = 0;
    private int32 _BReadyCount = 0;

    private int32 _AReadyAtDisable = -1;
    private int32 _BReadyAtDisable = -1;

    private int32 _ASpansBefore = -1;
    private int32 _BSpansBefore = -1;
    private int32 _ASpansAfter = -1;

    private int32 _ARevisionBefore = -1;
    private int32 _ARevisionAfter = -1;

    private int64 _EpochBefore = 0;
    private int64 _EpochAfter = 0;

    private bool _SwapLocationTaken = false;
    private FVector _ALocationAtSwap = FVector::ZeroVector;

    private ECk_CrowdAgent_MovementState _BStateAtAssert = ECk_CrowdAgent_MovementState::None;

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

        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stand a wall across the origin floor",                n"Step_StageWall");
        Add_Step_WaitUntil("the wall reaches the Jolt static world",              n"Check_WallBodyAdded",     BodyFrameBudget);
        Add_Step(          "stage a GroundNav field over the origin floor",       n"Step_StageField");
        Add_Step_WaitUntil("the origin field reports itself built",               n"Check_OriginFieldBuilt",  BuildFrameBudget);
        Add_Step(          "switch the world onto GroundNav",                     n"Step_SwitchProvider");
        Add_Step_WaitUntil("the surface settles after the provider switch",       n"Check_SurfaceSettled",    SurfaceFrameBudget);
        Add_Step(          "author the link over the wall",                       n"Step_AuthorLink");
        Add_Step_WaitUntil("the surface settles after the link",                  n"Check_SurfaceSettled",    SettleFrameBudget);
        Add_Step(          "the link is live and the volume names its id",        n"Step_AssertLinkLive");
        Add_Step(          "spawn the crosser and the errand-runner",             n"Step_SpawnAgents");
        Add_Step_WaitUntil("both walkers are Walking installed routes",           n"Check_BothWalking",       WalkingFrameBudget);
        Add_Step(          "only the crosser's route uses the link",              n"Step_AssertBaseline");
        Add_Step(          "disable the link and kick the settle counter",        n"Step_DisableLink");
        Add_Step_WaitUntil("the surface settles after the link was disabled",     n"Check_SurfaceSettled",    SettleFrameBudget);
        Add_Step_WaitUntil("the crosser installs a replacement route",            n"Check_CrosserReplanned",  ReplanFrameBudget);
        Add_Step_WaitUntil("the crosser has travelled its replacement route",     n"Check_CrosserTravelled",  TravelFrameBudget);
        Add_Step(          "only the crosser replanned",                          n"Step_AssertOnlyTheCrosserReplanned");
        Add_Step(          "hand the world back",                                 n"Step_Cleanup");

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
        _WallEntity.Set_DebugName(n"AutoTest_GroundNav_InvalidationWall");

        const auto Centre = Get_LevelFloorCentre();
        const auto TopZ = Get_LevelFloorTopZ();

        utils_transform::Add(_WallEntity,
            FTransform(FRotator::ZeroRotator,
                FVector(Centre.X + WallOffsetX, Centre.Y + WallCentreOffsetY, TopZ + WallHalfZ)),
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
        _LinkEntity.Set_DebugName(n"AutoTest_GroundNav_InvalidationLink");

        utils_ground_nav_volume::Request_Link(Volume, Get_LinkRequest(ECk_EnableDisable::Enable),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinkCompleted"));

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void OnLinkCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LinkCompletions += 1;
        _LastLinkResult = InResult;
    }

    // Built once, so the enabled and disabled forms cannot drift. The id is -1 because the VOLUME
    // assigns it, and naming the SAME entity is what keeps the id an update was first admitted
    // under - which is the id the corridor cached and the publish note names.
    private FCk_Request_GroundNavVolume_Link Get_LinkRequest(ECk_EnableDisable InEnable)
    {
        auto Record = FCk_GroundNav_LinkRecord(-1, Get_LinkStart(), Get_LinkEnd());

        Record.Set_Direction(ECk_GroundNav_LinkDirection::Bidirectional)
              .Set_CostMultiplierForward(float32(LinkMultiplier))
              .Set_CostMultiplierBackward(float32(LinkMultiplier))
              .Set_ClearanceUu(float32(LinkClearanceUu))
              .Set_Enable(InEnable);

        return FCk_Request_GroundNavVolume_Link(_LinkEntity, Record);
    }

    UFUNCTION()
    private void Step_AssertLinkLive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_LinkCompletions, 1,
            "the link request's completion delegate must fire exactly once");

        Assert_True(_LastLinkResult == ECk_Request_OperationResult::Succeeded,
            f"both endpoints lie inside the volume and the clearance admits both agents, so admission must complete Succeeded (got {_LastLinkResult})");

        Assert_True(utils_ground_nav_volume::Get_IsLinkLive(_LinkEntity),
            "the surface reported itself settled after the link was authored, so the link must already be in effect before either agent plans against it");

        auto Records = utils_ground_nav_volume::Get_LinkRecords(_Field.Get_OriginVolume());

        Assert_Equals_Int(Records.Num(), 1,
            "one link was authored against this volume, so the reflected read-back must carry exactly one record");

        if (Records.Num() != 1)
        { return; }

        // A local first: AngelScript reads an indexed struct element out of the array before a method
        // is called on it, and every other read-back in this corpus is written the same way.
        auto Record = Records[0];

        _AuthoredLinkId = Record.Get_Id();

        Assert_True(_AuthoredLinkId >= 0,
            f"the volume assigns a link its id at admission, so a record read back must carry a real one (got {_AuthoredLinkId})");
    }

    //------------------------------------------------------------------------
    // The two walkers
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SpawnAgents(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // ---- A, the crosser ----

        const auto ASpawn = Get_AStartPoint();
        const auto AGoal = Get_AGoalPoint();

        _AEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AEntity.Set_DebugName(n"GroundNav_LinkInvalidation_Crosser");

        auto ATransform = utils_transform::Add(_AEntity,
            FTransform((AGoal - ASpawn).Rotation(), ASpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        _AAgent = utils_crowd_agent::Add(ATransform,
            FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight)));

        Assert_True(ck::IsValid(_AAgent), "Add() must return a valid crowd agent handle for A");

        Do_GiveLocomotion(_AEntity);

        _APlanner = utils_ground_nav_path::Add(_AEntity,
            FCk_Fragment_GroundNavPath_ParamsData(float32(AgentRadius)));

        utils_nav::BindTo_OnPathReady(_AEntity,
            FCk_Delegate_Nav_OnPathReady(this, n"OnAPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // ---- B, the errand-runner ----

        const auto BSpawn = Get_BStartPoint();
        const auto BGoal = Get_BGoalPoint();

        _BEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _BEntity.Set_DebugName(n"GroundNav_LinkInvalidation_ErrandRunner");

        auto BTransform = utils_transform::Add(_BEntity,
            FTransform((BGoal - BSpawn).Rotation(), BSpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Slow on purpose: B has to still be mid-errand when the counters are read, or its zero
        // would be the answer an ARRIVED agent gives and would say nothing about invalidation.
        auto BParams = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));
        BParams.Set_MaxSpeed(float32(BMaxSpeed));

        _BAgent = utils_crowd_agent::Add(BTransform, BParams);

        Assert_True(ck::IsValid(_BAgent), "Add() must return a valid crowd agent handle for B");

        Do_GiveLocomotion(_BEntity);

        _BPlanner = utils_ground_nav_path::Add(_BEntity,
            FCk_Fragment_GroundNavPath_ParamsData(float32(AgentRadius)));

        utils_nav::BindTo_OnPathReady(_BEntity,
            FCk_Delegate_Nav_OnPathReady(this, n"OnBPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_AAgent, FCk_Request_CrowdAgent_MoveTo(AGoal));
        utils_crowd_agent::Request_MoveTo(_BAgent, FCk_Request_CrowdAgent_MoveTo(BGoal));
    }

    private void Do_GiveLocomotion(FCk_Handle InEntity)
    {
        utils_velocity::Add(InEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(InEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(InEntity);
    }

    UFUNCTION()
    private void OnAPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _AReadyCount += 1;
    }

    UFUNCTION()
    private void OnBPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _BReadyCount += 1;
    }

    UFUNCTION()
    private void Check_BothWalking(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AReadyCount >= 1 && _BReadyCount >= 1
            && utils_crowd_agent::Get_MovementState(_AAgent) == ECk_CrowdAgent_MovementState::Walking
            && utils_crowd_agent::Get_MovementState(_BAgent) == ECk_CrowdAgent_MovementState::Walking);
    }

    UFUNCTION()
    private void Step_AssertBaseline(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ASpansBefore = utils_ground_nav_path::Get_LinksOnPath(_APlanner).Num();
        _BSpansBefore = utils_ground_nav_path::Get_LinksOnPath(_BPlanner).Num();

        const auto AResult = utils_ground_nav_path::Get_Result(_APlanner);

        _ARevisionBefore = AResult.Get_RequestRevision();
        _EpochBefore = AResult.Get_PlannedAgainstEpoch();

        // The whole file rests on these two. Without the first, disabling the link could not move
        // A's route and every count below would be about nothing; without the second, B would be
        // an agent the narrowing never had to save.
        Assert_Equals_Int(_ASpansBefore, 1,
            f"the wall splits the field everywhere A can reach, so the only route A has is over the link and its corridor must cache that link's id (got {_ASpansBefore} link spans)");

        Assert_Equals_Int(_BSpansBefore, 0,
            f"B's start and goal are both west of the wall and both inside the tile the link's entry resolves into, so B's route crosses nothing and its corridor caches no link id (got {_BSpansBefore} link spans)");
    }

    //------------------------------------------------------------------------
    // The toggle, and what each agent does with it
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_DisableLink(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AReadyAtDisable = _AReadyCount;
        _BReadyAtDisable = _BReadyCount;

        // The SAME entity: identity is the entity, so this updates the record in place and keeps
        // the id A's corridor cached rather than retiring it for a new one.
        utils_ground_nav_volume::Request_Link(_Field.Get_OriginVolume(),
            Get_LinkRequest(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinkCompleted"));

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void Check_CrosserReplanned(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AReadyCount > _AReadyAtDisable);

        if (_AReadyCount > _AReadyAtDisable && _SwapLocationTaken == false)
        {
            _SwapLocationTaken = true;
            _ALocationAtSwap = Get_ALocation();
        }
    }

    // A positive that buys B a further window of frames to replan in. A fixed hop count here would
    // be a guess about processor ordering; a distance the body has to actually cover is not.
    UFUNCTION()
    private void Check_CrosserTravelled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set((Get_ALocation() - _ALocationAtSwap).Size() >= PostSwapTravelUu);
    }

    UFUNCTION()
    private void Step_AssertOnlyTheCrosserReplanned(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto ASwaps = _AReadyCount - _AReadyAtDisable;
        const auto BSwaps = _BReadyCount - _BReadyAtDisable;

        _ASpansAfter = utils_ground_nav_path::Get_LinksOnPath(_APlanner).Num();

        const auto AResult = utils_ground_nav_path::Get_Result(_APlanner);

        _ARevisionAfter = AResult.Get_RequestRevision();
        _EpochAfter = AResult.Get_PlannedAgainstEpoch();

        _BStateAtAssert = utils_crowd_agent::Get_MovementState(_BAgent);

        const auto RevBefore = _ARevisionBefore;
        const auto RevAfter = _ARevisionAfter;
        const auto EpochBefore = _EpochBefore;
        const auto EpochAfter = _EpochAfter;
        const auto BState = _BStateAtAssert;
        const auto SpansAfter = _ASpansAfter;

        ck::nav::Display(f"[GROUNDNAV-LINK-INVALIDATION] linkId={_AuthoredLinkId} crosserReplans={ASwaps} errandReplans={BSwaps} crosserSpansBefore={_ASpansBefore} crosserSpansAfter={SpansAfter} errandSpansBefore={_BSpansBefore} errandState={BState} crosserRevision={RevBefore}->{RevAfter} epoch={EpochBefore}->{EpochAfter}");

        // B first: it is the half a bounds-only invalidator fails, and the half the publish note
        // exists to buy. Reading it first makes a regression name the narrowing rather than the
        // route A ended up on.
        Assert_True(BState == ECk_CrowdAgent_MovementState::Walking,
            f"B must still be walking its errand when this is read - a 'did not replan' taken off an agent that had already arrived would be true because there was no episode to replan, which is not the claim (B is {BState})");

        Assert_Equals_Int(BSwaps, 0,
            f"B's route crosses no link, so a link-only publish cannot have moved anything under it and it must NOT have been flagged. It installed {BSwaps} replacement route(s) - which is what a bounds-only invalidator produces, because B walks inside the very tile the link's entry resolves into.");

        Assert_Equals_Int(ASwaps, 1,
            f"A's corridor cached the disabled link's id, so the publish must reach it and it must install exactly ONE replacement route (got {ASwaps}). Zero means the narrowing dropped a corridor it had to keep; more than one means a flag raised once was answered twice.");

        Assert_Equals_Int(_ASpansAfter, 0,
            f"a disabled link is invisible to search once the publish that disabled it has landed, so the route A replanned onto is the northern detour and carries no link span at all (got {_ASpansAfter})");

        Assert_True(_EpochAfter > _EpochBefore,
            f"A replanned against the field the derive published, which is a strictly newer epoch than the one its first route was planned against ({EpochBefore} -> {EpochAfter})");
    }

    //------------------------------------------------------------------------
    // Geometry helpers
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

    private FVector Get_AStartPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + AStartX, Centre.Y + ALaneY, _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
    }

    private FVector Get_AGoalPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + AGoalX, Centre.Y + ALaneY, _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
    }

    private FVector Get_BStartPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + BStartX, Centre.Y + BStartY, _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
    }

    private FVector Get_BGoalPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + BGoalX, Centre.Y + BGoalY, _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
    }

    private FVector Get_ALocation()
    {
        if (ck::Is_NOT_Valid(_AEntity))
        { return Get_AStartPoint(); }

        return utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(_AEntity));
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

    private void Teardown()
    {
        if (_Reported == false)
        {
            _Reported = true;
            _Field.Do_ReportCrossover("Link_DisableReplansOnlyTheAgentsUsingIt", _Verdict);
        }

        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_AEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_AEntity);
            _AEntity = FCk_Handle();
        }

        if (ck::IsValid(_BEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_BEntity);
            _BEntity = FCk_Handle();
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
