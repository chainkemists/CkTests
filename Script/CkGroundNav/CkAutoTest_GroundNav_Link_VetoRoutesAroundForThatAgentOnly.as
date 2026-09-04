// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A LINK VETO ROUTES AROUND, FOR ONE AGENT
//============================================================================
//
// The veto rides the QUERY, never the field. One link, one published field, one
// epoch - and two agents planning over it in the same breath, one of which may
// not use the link and one of which may. The first routes around; the second
// goes straight over. Nothing about the ground changed between the two answers,
// and that is the whole claim: a body that cannot climb ladders is a fact about
// the body, so what the link JOINS - and every reachability label that follows
// from it - is the same for everyone.
//
// A crowd agent carries the veto in its own params. FCk_Fragment_CrowdAgent_ParamsData
// gains _DeniedLinkIds, _DeniedLinkUserTypeTags and _LinkCostMultipliers, and the
// crowd's GroundNav dispatch copies all three onto the FindPath request it issues.
// This pin is the only place that path is exercised end to end from authored
// content: the C++ rows drive FCk_Request_GroundNavPath_FindPath directly, so a
// dispatch that dropped the copy would still pass every one of them.
//
// Two phases, because there are two ways to say no:
//
//   PHASE 1, BY ID. A denies the link's stable id. B denies nothing.
//     -> A's route carries no link span, B's carries one.
//   PHASE 2, BY CLASS. C denies the link's authored _UserTypeTag, and names no
//     id at all - "this body cannot use ladders", said once, for links it has
//     never heard of.
//     -> C's route carries no link span either, planned against the SAME field
//        epoch B's was.
//
// The epoch is asserted equal across all three, which is what makes this a
// statement about the query rather than about a field that quietly moved
// between the phases.
//
// The user-type tag is CkTests.GroundNav.Veto.Ladder, defined natively by the
// C++ veto suite (Test_GroundNav_LinkVeto.cpp) and therefore registered at
// module load - a link's _UserTypeTag has to be a REGISTERED tag, and the tag is
// asserted valid before it is used so a missing registration names itself
// instead of reading as a veto that did not bite.
//
//----------------------------------------------------------------------------
// THE SCENE
//----------------------------------------------------------------------------
//
// The invalidation pin's, unchanged: a field over the origin floor, a wall at
// X +300 running from Y -1100 to Y +600, and one link over it at Y -400. The
// wall leaves a 400uu gap at its northern end, so a denied agent has somewhere
// to go - a veto that produced no route at all would make "carries no link
// span" true of a route that does not exist.
//
// Both lanes are chosen so the link route beats the northern detour by more
// than eight hundred uu, so an undenied agent's preference for the link is not
// a coin flip a clearance offset could turn over.
//
// And neither lane lies ON the link's own Y. A link contributes one DEGENERATE
// portal per endpoint, and the funnel emits an apex only where it CLOSES - a
// degenerate portal sitting on the apex-to-goal line closes nothing. A start,
// two link endpoints and a goal that are collinear are therefore string-pulled
// into one straight segment, the finished route carries neither endpoint as a
// waypoint, and DoStamp_LinkWaypoints has nothing to stamp: Get_LinksOnPath
// answers ZERO on a route that did cross. Both lanes sit 200uu off the link, on
// opposite sides of it, which makes both endpoints genuine corners.
//
// Every agent is slowed to 40uu/s. None of them can actually CROSS the link -
// the crowd's grounded locomotion walks the navmesh and knows nothing about
// links - so an undenied agent would eventually press against the wall and be
// re-pathed by the block detector, which would replace the very answer this pin
// reads. At 40uu/s the wall is fifteen seconds away and both phases are long
// over.
//
// The provider is a WORLD selection every later fixture in this map reads, so
// the previous value is captured before the swap and handed back on every exit
// path including DoEndPlay.
//============================================================================

class UCk_AutoTest_GroundNav_Link_VetoRoutesAroundForThatAgentOnly : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 300.0f;

    //------------------------------------------------------------------------
    // Geometry, as offsets from the floor's own centre and top face.
    //------------------------------------------------------------------------

    private const float WallOffsetX = 300.0;
    private const float WallHalfX = 50.0;
    private const float WallCentreOffsetY = -250.0;
    private const float WallHalfY = 850.0;
    private const float WallHalfZ = 150.0;

    private const float LinkStartOffsetX = 100.0;
    private const float LinkEndOffsetX = 500.0;
    private const float LinkOffsetY = -400.0;

    private const float LinkClearanceUu = 100.0;
    private const float LinkMultiplier = 1.0;

    // 200uu NORTH of the link, and never on it - see the header on why a lane collinear with the
    // link's endpoints reads as zero spans. The link route from this lane is about 1315uu; the
    // northern detour about 2240uu.
    private const float DeniedLaneY = -200.0;

    // 200uu SOUTH of the link, the denied lane's mirror across it: far enough from that lane that
    // the two phase-one bodies never share ground, and off the link's own Y for the reason the
    // denied lane is. The link route from this lane is about 1315uu as well; the northern detour is
    // about 2860uu, because this lane is the further of the two from the wall's northern gap.
    private const float AllowedLaneY = -600.0;

    private const float StartX = -500.0;
    private const float GoalX = 700.0;

    // Slow enough that nobody reaches the wall inside the run - see the header.
    private const float AgentMaxSpeed = 40.0;

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
    private const int32 RouteFrameBudget = 1800;

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _WallEntity;
    private FCk_Handle _LinkEntity;

    private FCk_Handle _DeniedByIdEntity;
    private FCk_Handle _AllowedEntity;
    private FCk_Handle _DeniedByTagEntity;

    private FCk_Handle_JoltBody _WallBody;

    private FCk_Handle_CrowdAgent _DeniedByIdAgent;
    private FCk_Handle_CrowdAgent _AllowedAgent;
    private FCk_Handle_CrowdAgent _DeniedByTagAgent;

    private FCk_Handle_GroundNavPath _DeniedByIdPlanner;
    private FCk_Handle_GroundNavPath _AllowedPlanner;
    private FCk_Handle_GroundNavPath _DeniedByTagPlanner;

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

    private int32 _DeniedByIdReady = 0;
    private int32 _AllowedReady = 0;
    private int32 _DeniedByTagReady = 0;

    private int32 _DeniedByIdSpans = -1;
    private int32 _AllowedSpans = -1;
    private int32 _DeniedByTagSpans = -1;

    private int64 _DeniedByIdEpoch = 0;
    private int64 _AllowedEpoch = 0;
    private int64 _DeniedByTagEpoch = 0;

    private ECk_GroundNav_PathStatus _DeniedByIdStatus = ECk_GroundNav_PathStatus::InProgress;
    private ECk_GroundNav_PathStatus _AllowedStatus = ECk_GroundNav_PathStatus::InProgress;
    private ECk_GroundNav_PathStatus _DeniedByTagStatus = ECk_GroundNav_PathStatus::InProgress;

    //------------------------------------------------------------------------
    // What Do_SpawnWalker last built. AngelScript returns one value and
    // UCk_Utils_GroundNavPath_UE's cast is C++-only (CK_DEFINE_CPP_CASTCHECKED_TYPESAFE,
    // not a UFUNCTION), so the typesafe handles cannot be recovered from the
    // entity afterwards - the helper hands them over here and the caller copies
    // them into the slot the phase owns.
    //------------------------------------------------------------------------

    private FCk_Handle _LastSpawnedEntity;
    private FCk_Handle_CrowdAgent _LastSpawnedAgent;
    private FCk_Handle_GroundNavPath _LastSpawnedPlanner;

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

        Add_Step(          "stand a wall across the origin floor",               n"Step_StageWall");
        Add_Step_WaitUntil("the wall reaches the Jolt static world",             n"Check_WallBodyAdded",   BodyFrameBudget);
        Add_Step(          "stage a GroundNav field over the origin floor",      n"Step_StageField");
        Add_Step_WaitUntil("the origin field reports itself built",              n"Check_OriginFieldBuilt", BuildFrameBudget);
        Add_Step(          "switch the world onto GroundNav",                    n"Step_SwitchProvider");
        Add_Step_WaitUntil("the surface settles after the provider switch",      n"Check_SurfaceSettled",  SurfaceFrameBudget);
        Add_Step(          "author the ladder link over the wall",               n"Step_AuthorLink");
        Add_Step_WaitUntil("the surface settles after the link",                 n"Check_SurfaceSettled",  SettleFrameBudget);
        Add_Step(          "the link is live and carries its user-type tag",     n"Step_AssertLinkLive");
        Add_Step(          "spawn the id-denied walker beside an undenied one",  n"Step_SpawnPhaseOne");
        Add_Step_WaitUntil("both phase-one routes are installed",                n"Check_PhaseOneRouted",  RouteFrameBudget);
        Add_Step(          "the id veto routed one agent around and not the other", n"Step_AssertPhaseOne");
        Add_Step(          "spawn the tag-denied walker on the same lane",       n"Step_SpawnPhaseTwo");
        Add_Step_WaitUntil("the phase-two route is installed",                   n"Check_PhaseTwoRouted",  RouteFrameBudget);
        Add_Step(          "the tag veto routed it around, in the same epoch",   n"Step_AssertPhaseTwo");
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
    private void Step_StageWall(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _WallEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _WallEntity.Request_OverrideToSelf();
        _WallEntity.Set_DebugName(n"AutoTest_GroundNav_VetoWall");

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
    // The link, authored WITH the user-type tag phase two denies by class
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AuthorLink(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Volume = _Field.Get_OriginVolume();

        Assert_True(ck::IsValid(Volume),
            "the fixture must hand back a valid volume before a link can be authored against it");

        const auto LadderTag = Get_LadderTag();

        // Asserted before it is used: an unregistered tag would make phase two's veto silently
        // match nothing, and a passing route would then be evidence of a missing registration
        // rather than of a veto.
        Assert_True(LadderTag.IsValid(),
            "CkTests.GroundNav.Veto.Ladder must be a registered gameplay tag - it is defined natively by the C++ link-veto suite and registered at module load, and a link's _UserTypeTag is only meaningful as a registered tag");

        _LinkEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _LinkEntity.Request_OverrideToSelf();
        _LinkEntity.Set_DebugName(n"AutoTest_GroundNav_VetoLadder");

        // The id is -1 because the VOLUME assigns it.
        auto Record = FCk_GroundNav_LinkRecord(-1, Get_LinkStart(), Get_LinkEnd());

        Record.Set_Direction(ECk_GroundNav_LinkDirection::Bidirectional)
              .Set_CostMultiplierForward(float32(LinkMultiplier))
              .Set_CostMultiplierBackward(float32(LinkMultiplier))
              .Set_ClearanceUu(float32(LinkClearanceUu))
              .Set_UserTypeTag(LadderTag)
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
            f"both endpoints lie inside the volume and the clearance admits every agent here, so admission must complete Succeeded (got {_LastLinkResult})");

        Assert_True(utils_ground_nav_volume::Get_IsLinkLive(_LinkEntity),
            "the surface reported itself settled after the link was authored, so the link must already be in effect before any agent plans against it");

        auto Records = utils_ground_nav_volume::Get_LinkRecords(_Field.Get_OriginVolume());

        Assert_Equals_Int(Records.Num(), 1,
            "one link was authored against this volume, so the reflected read-back must carry exactly one record");

        if (Records.Num() != 1)
        { return; }

        auto Record = Records[0];

        _AuthoredLinkId = Record.Get_Id();

        Assert_True(_AuthoredLinkId >= 0,
            f"the volume assigns a link its id at admission, so a record read back must carry a real one (got {_AuthoredLinkId})");

        Assert_True(Record.Get_UserTypeTag() == Get_LadderTag(),
            "the record must read back the user-type tag it was authored with - phase two's veto matches against exactly that field");
    }

    //------------------------------------------------------------------------
    // Phase one - the veto by id
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SpawnPhaseOne(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // "This body may not take link N." The set is the agent's, and the crowd's GroundNav
        // dispatch copies it onto every FindPath the agent issues.
        auto DeniedIds = TSet<int32>();
        DeniedIds.Add(_AuthoredLinkId);

        auto DeniedParams = Get_AgentParams();
        DeniedParams.Set_DeniedLinkIds(DeniedIds);

        Do_SpawnWalker(n"GroundNav_LinkVeto_DeniedById", DeniedLaneY, DeniedParams,
            n"OnDeniedByIdPathReady");

        _DeniedByIdEntity = _LastSpawnedEntity;
        _DeniedByIdAgent = _LastSpawnedAgent;
        _DeniedByIdPlanner = _LastSpawnedPlanner;

        Do_SpawnWalker(n"GroundNav_LinkVeto_Allowed", AllowedLaneY, Get_AgentParams(),
            n"OnAllowedPathReady");

        _AllowedEntity = _LastSpawnedEntity;
        _AllowedAgent = _LastSpawnedAgent;
        _AllowedPlanner = _LastSpawnedPlanner;

        utils_crowd_agent::Request_MoveTo(_DeniedByIdAgent,
            FCk_Request_CrowdAgent_MoveTo(Get_GoalPoint(DeniedLaneY)));
        utils_crowd_agent::Request_MoveTo(_AllowedAgent,
            FCk_Request_CrowdAgent_MoveTo(Get_GoalPoint(AllowedLaneY)));
    }

    UFUNCTION()
    private void OnDeniedByIdPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _DeniedByIdReady += 1;

        if (_DeniedByIdReady != 1)
        { return; }

        // Sampled INSIDE the first install, so a later block-detector re-path cannot replace the
        // answer this pin is about.
        const auto Result = utils_ground_nav_path::Get_Result(_DeniedByIdPlanner);

        _DeniedByIdSpans = utils_ground_nav_path::Get_LinksOnPath(_DeniedByIdPlanner).Num();
        _DeniedByIdEpoch = Result.Get_PlannedAgainstEpoch();
        _DeniedByIdStatus = Result.Get_Status();
    }

    UFUNCTION()
    private void OnAllowedPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _AllowedReady += 1;

        if (_AllowedReady != 1)
        { return; }

        const auto Result = utils_ground_nav_path::Get_Result(_AllowedPlanner);

        _AllowedSpans = utils_ground_nav_path::Get_LinksOnPath(_AllowedPlanner).Num();
        _AllowedEpoch = Result.Get_PlannedAgainstEpoch();
        _AllowedStatus = Result.Get_Status();
    }

    UFUNCTION()
    private void Check_PhaseOneRouted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DeniedByIdReady >= 1 && _AllowedReady >= 1);
    }

    UFUNCTION()
    private void Step_AssertPhaseOne(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // The POSITIVE half first: without it, "the denied agent carries no span" would also be
        // satisfied by a field on which nobody could have used the link at all.
        Assert_Equals_Int(_AllowedSpans, 1,
            f"the undenied agent's lane makes the link route more than a thousand uu shorter than the way round, so its route must cross the link exactly once (got {_AllowedSpans} link spans, status {_AllowedStatus})");

        Assert_Equals_Int(_DeniedByIdSpans, 0,
            f"the same link, the same field and the same epoch - only the agent's own _DeniedLinkIds differ. A denied link is SKIPPED where the search admits crossings, so the answer routes around it and can never be merely dearer (got {_DeniedByIdSpans} link spans, status {_DeniedByIdStatus})");

        Assert_True(_DeniedByIdStatus == ECk_GroundNav_PathStatus::Ready,
            f"the wall leaves a 400uu gap at its northern end, so a denied agent has a way round and must still be answered Ready - a veto that produced no route would make the span count above true of nothing (got {_DeniedByIdStatus})");
    }

    //------------------------------------------------------------------------
    // Phase two - the veto by user-type tag
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SpawnPhaseTwo(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Retired before the tag-denied agent takes the same lane, so the two never share ground.
        if (ck::IsValid(_DeniedByIdEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_DeniedByIdEntity);
            _DeniedByIdEntity = FCk_Handle();
        }

        // "This body cannot use ladders." No id is named at all - the container is matched against
        // the link's own authored _UserTypeTag.
        auto DeniedTags = FGameplayTagContainer();
        DeniedTags.AddTag(Get_LadderTag());

        auto DeniedParams = Get_AgentParams();
        DeniedParams.Set_DeniedLinkUserTypeTags(DeniedTags);

        Do_SpawnWalker(n"GroundNav_LinkVeto_DeniedByTag", DeniedLaneY, DeniedParams,
            n"OnDeniedByTagPathReady");

        _DeniedByTagEntity = _LastSpawnedEntity;
        _DeniedByTagAgent = _LastSpawnedAgent;
        _DeniedByTagPlanner = _LastSpawnedPlanner;

        utils_crowd_agent::Request_MoveTo(_DeniedByTagAgent,
            FCk_Request_CrowdAgent_MoveTo(Get_GoalPoint(DeniedLaneY)));
    }

    UFUNCTION()
    private void OnDeniedByTagPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _DeniedByTagReady += 1;

        if (_DeniedByTagReady != 1)
        { return; }

        const auto Result = utils_ground_nav_path::Get_Result(_DeniedByTagPlanner);

        _DeniedByTagSpans = utils_ground_nav_path::Get_LinksOnPath(_DeniedByTagPlanner).Num();
        _DeniedByTagEpoch = Result.Get_PlannedAgainstEpoch();
        _DeniedByTagStatus = Result.Get_Status();
    }

    UFUNCTION()
    private void Check_PhaseTwoRouted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DeniedByTagReady >= 1);
    }

    UFUNCTION()
    private void Step_AssertPhaseTwo(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto ByIdSpans = _DeniedByIdSpans;
        const auto AllowedSpans = _AllowedSpans;
        const auto ByTagSpans = _DeniedByTagSpans;
        const auto ByIdEpoch = _DeniedByIdEpoch;
        const auto AllowedEpoch = _AllowedEpoch;
        const auto ByTagEpoch = _DeniedByTagEpoch;

        ck::nav::Display(f"[GROUNDNAV-LINK-VETO] linkId={_AuthoredLinkId} deniedByIdSpans={ByIdSpans} deniedByTagSpans={ByTagSpans} allowedSpans={AllowedSpans} epochs={ByIdEpoch}/{ByTagEpoch}/{AllowedEpoch}");

        Assert_Equals_Int(_DeniedByTagSpans, 0,
            f"the tag-denied agent names no link id at all: its container matches the link's authored _UserTypeTag, which is what lets one tag deny every ladder a body has never heard of. Its route must therefore carry no link span (got {_DeniedByTagSpans}, status {_DeniedByTagStatus})");

        Assert_True(_DeniedByTagStatus == ECk_GroundNav_PathStatus::Ready,
            f"the tag-denied agent has the same way round the denied one had, so it must still be answered Ready (got {_DeniedByTagStatus})");

        // The two vetoes and the permission are only comparable if the ground under them never
        // moved. Nothing between the phases touches the volume, and this is what says so.
        Assert_True(_DeniedByTagEpoch == _AllowedEpoch,
            f"nothing between the phases republished the field, so every route here was planned against ONE epoch - a veto is a property of the query, and comparing answers from two different fields would prove nothing about it (tag-denied {ByTagEpoch}, undenied {AllowedEpoch})");

        Assert_True(_DeniedByIdEpoch == _AllowedEpoch,
            f"the id-denied route was planned against the same epoch as the undenied one, for the same reason (id-denied {ByIdEpoch}, undenied {AllowedEpoch})");
    }

    //------------------------------------------------------------------------
    // Spawning
    //------------------------------------------------------------------------

    private FCk_Fragment_CrowdAgent_ParamsData Get_AgentParams()
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));
        Params.Set_MaxSpeed(float32(AgentMaxSpeed));

        return Params;
    }

    private void Do_SpawnWalker(
        FName InDebugName,
        float InLaneY,
        FCk_Fragment_CrowdAgent_ParamsData InParams,
        FName InPathReadyFunction)
    {
        const auto Spawn = Get_StartPoint(InLaneY);
        const auto Goal = Get_GoalPoint(InLaneY);

        auto Entity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Entity.Set_DebugName(InDebugName);

        auto EntityTransform = utils_transform::Add(Entity,
            FTransform((Goal - Spawn).Rotation(), Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto Agent = utils_crowd_agent::Add(EntityTransform, InParams);

        Assert_True(ck::IsValid(Agent), "Add() must return a valid crowd agent handle");

        utils_velocity::Add(Entity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Entity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Entity);

        // Composed here with the params the crowd's own GroundNav dispatch would have used, purely
        // so this fixture holds the typesafe handle it needs to read the plan's spans back.
        auto Planner = utils_ground_nav_path::Add(Entity,
            FCk_Fragment_GroundNavPath_ParamsData(float32(AgentRadius)));

        Assert_True(ck::IsValid(Planner), "Add() must return a valid GroundNav path handle");

        utils_nav::BindTo_OnPathReady(Entity,
            FCk_Delegate_Nav_OnPathReady(this, InPathReadyFunction),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        _LastSpawnedEntity = Entity;
        _LastSpawnedAgent = Agent;
        _LastSpawnedPlanner = Planner;
    }

    //------------------------------------------------------------------------
    // Geometry helpers
    //------------------------------------------------------------------------

    private FGameplayTag Get_LadderTag()
    {
        return utils_gameplay_tag::ResolveGameplayTag(n"CkTests.GroundNav.Veto.Ladder");
    }

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

    private FVector Get_StartPoint(float InLaneY)
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + StartX, Centre.Y + InLaneY, _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
    }

    private FVector Get_GoalPoint(float InLaneY)
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + GoalX, Centre.Y + InLaneY, _Field.Get_FloorTopZ() + AgentCentreOffsetZ);
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
            _Field.Do_ReportCrossover("Link_VetoRoutesAroundForThatAgentOnly", _Verdict);
        }

        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_DeniedByIdEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_DeniedByIdEntity);
            _DeniedByIdEntity = FCk_Handle();
        }

        if (ck::IsValid(_DeniedByTagEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_DeniedByTagEntity);
            _DeniedByTagEntity = FCk_Handle();
        }

        if (ck::IsValid(_AllowedEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_AllowedEntity);
            _AllowedEntity = FCk_Handle();
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
