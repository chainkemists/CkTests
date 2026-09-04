// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: AN AUTHORED LINK IS LIVE AND ROUTES ACROSS
//============================================================================
//
// The third environment for navigation links. The record type, the resolver and
// the crossing enumeration are pinned at Layer 1 from C++; this is the same link
// authored from AngelScript against a live world, so a binding that compiled but
// never reached the volume is caught here rather than in a game.
//
// The shape is one field, one wall and one link:
//
//   a field over the origin floor, split end to end by a runtime wall
//   -> a route across it is NOT Ready
//   -> author a link over the wall
//   -> the route is Ready and steps THROUGH the link's two endpoints
//   -> disable the link -> the route is not Ready again
//   -> release the link -> the volume holds no record.
//
//----------------------------------------------------------------------------
// THE WALL RUNS OFF THE FIELD'S EDGE, AND SITS OFF ITS CENTRE
//----------------------------------------------------------------------------
//
// A wall that stopped inside the field would leave a way round it and the
// baseline would be Ready for a reason that has nothing to do with links, so it
// spans further in Y than the field does. It is offset in X from the floor's
// centre for a second reason: FCkAutoTest_GroundNavFixture decides whether the
// level floor is already in the Jolt static world by raycasting straight down
// through that centre, and a wall standing on the probe line would answer that
// question for the floor - the field would then bake over a wall and nothing
// else.
//
//----------------------------------------------------------------------------
// THE LINK IS OFF THE STRAIGHT LINE BETWEEN THE ENDS
//----------------------------------------------------------------------------
//
// A link crossing is carried through the funnel as two degenerate portals, and
// the string pull emits a portal it passes through as a corner only where the
// route actually bends at it. Endpoints placed on the straight line from start
// to goal would be collinear with their neighbours and the waypoint assertion
// would be about the string pull's collinearity handling rather than about the
// link. Offsetting them in Y makes both a genuine corner.
//
// The points asserted against are the AUTHORED ones, not projections of them:
// a resolved entry copies the record's two world points verbatim, the crossing
// copies them from the entry, and Get_CornerOffset leaves a waypoint that is
// exactly a pinned link endpoint where it is. The 1uu tolerance below is
// therefore slack around an equality, not a search radius.
//
//----------------------------------------------------------------------------
// THE TWO THINGS THIS PIN ADDS OVER THE C++ LAYER-1 TESTS
//----------------------------------------------------------------------------
//
//   1. ORDERING. A cost-only area markup is painted in the SAME frame as the
//      link request. The two travel different derives - a paint raises the cost
//      derive, a link raises the link derive, and the link derive runs after it
//      so it composes on the field the cost derive published - and after ONE
//      settle both must read live. Cost-only rather than impassable on purpose:
//      a walkability paint owes a repair, and a repair would make the second
//      claim below untestable.
//
//   2. NO RE-BAKE. A link is a DERIVE. Between the request and the settle the
//      volume must never report itself building, and the number of built tiles
//      must not move. Both are sampled on EVERY poll of the wait rather than
//      read once afterwards, because a bake that started and finished inside
//      the window would leave no trace in a single reading.
//
// Every wait is a NAMED CONDITION with a frame budget as its ceiling. How many
// passes a bake, a derive or a publish needs is a property of processor ordering
// and of the probe budget; a hop count would bake a guess in.
//
// The provider is a WORLD selection every later fixture in this map reads, so
// the previous value is captured before the swap and handed back on every exit
// path including DoEndPlay - the engine TimeLimit path never runs the finish
// path.
//============================================================================

class UCk_AutoTest_GroundNav_Link_AuthoredLinkIsLiveAndRoutesAcross : UCk_AutoTest_Base
{
    // A 16-tile bake of the origin floor, four kicked settles and three path episodes, each on its
    // own budgeted condition. Deliberately slack: a contract that expires on the harness's anonymous
    // TimesUp names nothing.
    default _TimeoutSeconds = 300.0f;

    //------------------------------------------------------------------------
    // Geometry, all of it as offsets from the floor's own centre and top face.
    // The shared level's origin floor is centred on the origin with its top at
    // Z 0, but these resolve onto the floor whatever that asset's transform is.
    //------------------------------------------------------------------------

    // Clear of the floor centre, which is where the fixture probes for the floor.
    private const float WallOffsetX = 300.0;

    private const float WallHalfX = 50.0;

    // Wider than the field's own 1000uu half-extent, so the wall leaves no way round.
    private const float WallHalfY = 1100.0;

    // 300uu of wall standing on the floor - well past any step height, and its top stays under the
    // volume's 400uu ceiling.
    private const float WallHalfZ = 150.0;

    private const float StartOffsetX = -500.0;
    private const float GoalOffsetX = 700.0;

    // 150uu of floor between each endpoint and the wall face it stands beside, which is more than
    // three times the body radius the field admits.
    private const float LinkStartOffsetX = 100.0;
    private const float LinkEndOffsetX = 500.0;
    private const float LinkOffsetY = 400.0;

    private const float LinkClearanceUu = 100.0;
    private const float LinkMultiplier = 1.0;

    // Well away from the route and from the link, on floor the field covers.
    private const float PaintOffsetX = -700.0;
    private const float PaintOffsetY = -600.0;
    private const float PaintHalfXY = 150.0;
    private const float PaintHalfZ = 200.0;

    // Slack around an equality - see the header. Not a search radius.
    private const float EndpointToleranceUu = 1.0;

    private const float AgentRadius = 42.0;
    private const float CellHeightUu = 10.0;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 SettleFrameBudget = 3600;
    private const int32 PathFrameBudget = 1800;

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _WallEntity;
    private FCk_Handle _PlannerEntity;
    private FCk_Handle _LinkEntity;

    private FCk_Handle_JoltBody _WallBody;
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

    private int32 _PathRequests = 0;
    private int32 _PathCompletions = 0;

    private int32 _LinkCompletions = 0;
    private ECk_Request_OperationResult _LastLinkResult = ECk_Request_OperationResult::Failed;

    private int32 _ReleaseCompletions = 0;
    private ECk_Request_OperationResult _LastReleaseResult = ECk_Request_OperationResult::Failed;

    private ECk_GroundNav_PathStatus _BlockedStatus = ECk_GroundNav_PathStatus::InProgress;
    private ECk_GroundNav_PathStatus _LinkedStatus = ECk_GroundNav_PathStatus::InProgress;
    private ECk_GroundNav_PathStatus _DisabledStatus = ECk_GroundNav_PathStatus::InProgress;

    private TArray<FVector> _LinkedWaypoints;

    //------------------------------------------------------------------------
    // Samples taken across the link window, and at the FIRST poll that answers
    // settled. What the pin is about is the state of the surface at the moment
    // the wait let go, not at the moment the next step read it out.
    //------------------------------------------------------------------------

    private int32 _TileCountBeforeLink = -1;
    private int32 _TileCountDuringLink = -1;

    // Latched, not read once: a bake that started and finished inside the window, or a tile count that
    // moved and moved back, would leave no trace in a reading taken after the wait let go.
    private bool _BuildingSeenDuringLink = false;
    private bool _TileCountMovedDuringLink = false;

    private bool _LinkSampled = false;
    private bool _LinkLiveAtSettled = false;
    private bool _MarkupLiveAtSettled = false;
    private int32 _LinkSettledFrames = -1;

    private bool _DisableSampled = false;
    private bool _LinkLiveAfterDisable = true;
    private int32 _DisableSettledFrames = -1;

    private bool _ReleaseSampled = false;
    private int32 _RecordsAfterRelease = -1;
    private int32 _ReleaseSettledFrames = -1;

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

        Add_Step(          "stand a wall across the origin floor",              n"Step_StageWall");
        Add_Step_WaitUntil("the wall reaches the Jolt static world",            n"Check_WallBodyAdded",       BodyFrameBudget);
        Add_Step(          "stage a GroundNav field over the origin floor",     n"Step_StageField");
        Add_Step_WaitUntil("the origin field reports itself built",             n"Check_OriginFieldBuilt",    BuildFrameBudget);
        Add_Step(          "switch the world onto GroundNav",                   n"Step_SwitchProvider");
        Add_Step_WaitUntil("the surface settles after the provider switch",     n"Check_SurfaceSettled",      SurfaceFrameBudget);
        Add_Step(          "plan across the wall with no link authored",        n"Step_PlanBaseline");
        Add_Step_WaitUntil("the baseline route is answered",                    n"Check_PathAnswered",        PathFrameBudget);
        Add_Step(          "the wall leaves no route across",                   n"Step_AssertBaselineBlocked");
        Add_Step(          "author the link and paint a cost area in one frame", n"Step_LinkAndPaintAtOnce");
        Add_Step_WaitUntil("the surface settles after the link",                n"Check_SettledAfterLink",    SettleFrameBudget);
        Add_Step(          "the link and the paint are both live, with no re-bake", n"Step_AssertLinkLiveAtSettle");
        Add_Step(          "the volume reads back the record that was authored", n"Step_AssertRecordReadBack");
        Add_Step(          "plan again now the link is live",                   n"Step_PlanAcrossLink");
        Add_Step_WaitUntil("the linked route is answered",                      n"Check_PathAnswered",        PathFrameBudget);
        Add_Step(          "the route steps through both link endpoints",       n"Step_AssertRouteUsesLink");
        Add_Step(          "disable the link and kick the settle counter",      n"Step_DisableLink");
        Add_Step_WaitUntil("the surface settles after the link was disabled",   n"Check_SettledAfterDisable", SettleFrameBudget);
        Add_Step(          "the disabled link is not live, and re-plan",        n"Step_AssertNotLiveAndPlan");
        Add_Step_WaitUntil("the route over the disabled link is answered",      n"Check_PathAnswered",        PathFrameBudget);
        Add_Step(          "the wall blocks the route again",                   n"Step_AssertBlockedAgain");
        Add_Step(          "release the link and kick the settle counter",      n"Step_ReleaseLink");
        Add_Step_WaitUntil("the surface settles after the release",             n"Check_SettledAfterRelease", SettleFrameBudget);
        Add_Step(          "the volume holds no link record",                   n"Step_AssertRecordsEmpty");
        Add_Step(          "hand the world back",                               n"Step_Cleanup");

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
        _WallEntity.Set_DebugName(n"AutoTest_GroundNav_LinkWall");

        // The floor readers are only valid after staging, and staging is the step after this one, so
        // the wall is placed against the LEVEL's own floor actor rather than against the fixture.
        // Both resolve to the same ground; this one is available a step earlier.
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
    private void Step_SwitchProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Kicked before the mutation, so the number reported afterwards measures THIS switch rather
        // than every poll since staging.
        _Field.Request_KickSettleCount();

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
        _ProviderSwapped = true;

        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::GroundNav,
            f"the world must report the provider it was told to answer on (got {ProviderNow})");

        _PlannerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _PlannerEntity.Request_OverrideToSelf();
        _PlannerEntity.Set_DebugName(n"AutoTest_GroundNav_LinkPlanner");

        auto PathParams = FCk_Fragment_GroundNavPath_ParamsData(float32(AgentRadius));
        PathParams.Set_VerticalToleranceUu(float32(CellHeightUu * 4.0));

        _Planner = utils_ground_nav_path::Add(_PlannerEntity, PathParams);

        Assert_True(ck::IsValid(_Planner), "Add() must return a valid GroundNav path handle");
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);
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
    // condition counting a single further completion would fire on the cancellation.
    UFUNCTION()
    private void Check_PathAnswered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PathCompletions >= _PathRequests
            && utils_ground_nav_path::Get_HasFreshResult(_Planner));
    }

    UFUNCTION()
    private void Step_PlanBaseline(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Request_Route();
    }

    UFUNCTION()
    private void Step_AssertBaselineBlocked(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_ground_nav_path::Get_Result(_Planner);

        _BlockedStatus = Result.Get_Status();

        const auto Waypoints = Result.Get_Waypoints().Num();

        ck::nav::Display(f"[GROUNDNAV-LINK] baseline: status={_BlockedStatus} waypoints={Waypoints}");

        // The NEGATIVE the whole file rests on. Without it, a route that was Ready before the link
        // was ever authored would make every assertion after the link about nothing at all.
        Assert_True(_BlockedStatus != ECk_GroundNav_PathStatus::Ready,
            f"the wall spans further in Y than the field does, so with no link authored there is no route from one side of it to the other and the search must not answer Ready (got {_BlockedStatus})");
    }

    //------------------------------------------------------------------------
    // The link, and the paint that travels beside it
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_LinkAndPaintAtOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Volume = _Field.Get_OriginVolume();

        Assert_True(ck::IsValid(Volume),
            "the fixture must hand back a valid volume before a link can be authored against it");

        // Read BEFORE the request, so the sample taken during the wait has something to be compared
        // against that no derive could have moved.
        _TileCountBeforeLink = utils_ground_nav_volume::Get_BuiltTileCount(Volume);

        _LinkEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _LinkEntity.Request_OverrideToSelf();
        _LinkEntity.Set_DebugName(n"AutoTest_GroundNav_LinkOverTheWall");

        utils_ground_nav_volume::Request_Link(Volume, Get_LinkRequest(ECk_EnableDisable::Enable),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinkCompleted"));

        // Cost-only, and deliberately in the SAME frame - see the header. A walkability paint would
        // owe a repair, and the no-re-bake claim below would then be untestable.
        auto PaintRequest = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(PaintHalfXY, PaintHalfXY, PaintHalfZ))),
            utils_gameplay_tag::ResolveGameplayTag(n"Nav.Area.Restricted"));
        PaintRequest.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_PaintCentre(), FVector::OneVector));

        _Markup = utils_nav_surface::Request_AreaMarkup(PaintRequest);

        Assert_True(ck::IsValid(_Markup),
            "Request_AreaMarkup hands back the handle the caller needs to observe and release the paint - an invalid one leaves the cost record unreachable");

        // The markup entity is parented to the WORLD, not to this runner, so the harness's own
        // subtree teardown never reaches it - registering it here is what unpaints it.
        Track_ForCleanup(FCk_Handle(_Markup));

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void OnLinkCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LinkCompletions += 1;
        _LastLinkResult = InResult;
    }

    UFUNCTION()
    private void OnReleaseCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _ReleaseCompletions += 1;
        _LastReleaseResult = InResult;
    }

    // The wait is on SETTLED. The no-re-bake evidence is gathered on EVERY poll, because a build that
    // started and finished inside the window would leave no trace in a reading taken afterwards.
    UFUNCTION()
    private void Check_SettledAfterLink(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Volume = _Field.Get_OriginVolume();

        if (utils_ground_nav_volume::Get_IsBuilding(Volume))
        { _BuildingSeenDuringLink = true; }

        _TileCountDuringLink = utils_ground_nav_volume::Get_BuiltTileCount(Volume);

        if (_TileCountDuringLink != _TileCountBeforeLink)
        { _TileCountMovedDuringLink = true; }

        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);

        if (utils_shared_bool::Get(OutResult) == false)
        { return; }

        if (_LinkSampled)
        { return; }

        _LinkSampled = true;
        _LinkLiveAtSettled = utils_ground_nav_volume::Get_IsLinkLive(_LinkEntity);
        _MarkupLiveAtSettled = utils_nav_surface::Get_IsMarkupLive(_Markup);
        _LinkSettledFrames = _Field.Get_SettledFrames();
    }

    UFUNCTION()
    private void Step_AssertLinkLiveAtSettle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Frames = _LinkSettledFrames;
        const auto LinkLive = _LinkLiveAtSettled;
        const auto MarkupLive = _MarkupLiveAtSettled;
        const auto TilesBefore = _TileCountBeforeLink;
        const auto TilesDuring = _TileCountDuringLink;

        ck::nav::Display(f"[GROUNDNAV-LINK] link: settledFrames={Frames} linkLiveAtSettled={LinkLive} markupLiveAtSettled={MarkupLive} builtTilesBefore={TilesBefore} builtTilesDuring={TilesDuring}");

        Assert_Equals_Int(_LinkCompletions, 1,
            "the link request's completion delegate must fire exactly once");

        Assert_True(_LastLinkResult == ECk_Request_OperationResult::Succeeded,
            f"both endpoints lie inside the volume, both multipliers are 1.0 and the clearance admits an agent, so admission must complete Succeeded (got {_LastLinkResult})");

        // The no-re-bake claim, asserted first because it is the one a derive that quietly turned into
        // a rebuild would break while every liveness reading still came out true.
        Assert_False(_BuildingSeenDuringLink,
            "a link change is a DERIVE: it copies the published field, re-resolves the records and republishes. The volume reported itself BUILDING at some point between the request and the settle, which means authoring a link re-baked ground instead.");

        Assert_False(_TileCountMovedDuringLink,
            f"a link derive publishes the same tiles it was handed, so the count of built tiles cannot move at any point between the request and the settle. It read {TilesBefore} before the request and moved from it (last reading {TilesDuring}), which means the derive re-baked rather than re-resolved.");

        // The ordering proof. Both were requested in one frame and travel different derives; a single
        // settle is the caller's whole contract, so both must hold at the first poll that answers it.
        Assert_True(MarkupLive,
            "a cost-only paint and a link were requested in the SAME frame and the surface then reported itself settled, so the paint must already be live at that moment. It is not, which means a settled surface can still be waiting on cost work.");

        Assert_True(LinkLive,
            "the link was authored over ground the field already carries and the surface then reported itself SETTLED, so Get_IsLinkLive must ALREADY answer true at that same moment with no further wait. A settled surface that has not resolved an authored link makes settled the weaker condition of the two.");
    }

    UFUNCTION()
    private void Step_AssertRecordReadBack(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Records = utils_ground_nav_volume::Get_LinkRecords(_Field.Get_OriginVolume());

        Assert_Equals_Int(Records.Num(), 1,
            "one link was authored against this volume, so the reflected read-back must carry exactly one record");

        if (Records.Num() != 1)
        { return; }

        auto Record = Records[0];

        const auto RecordId = Record.Get_Id();
        const auto StartDriftUu = (Record.Get_Start() - Get_LinkStart()).Size();
        const auto EndDriftUu = (Record.Get_End() - Get_LinkEnd()).Size();

        ck::nav::Display(f"[GROUNDNAV-LINK] record: id={RecordId} startDrift={StartDriftUu}uu endDrift={EndDriftUu}uu direction={Record.Get_Direction()} clearance={Record.Get_ClearanceUu()}uu");

        // Ids are assigned by the volume and never reused, so the only thing an author may assert is
        // that it got one - not which one.
        Assert_True(RecordId >= 0,
            f"the volume assigns a link its id at admission, so a record read back must carry a real one (got {RecordId})");

        Assert_True(StartDriftUu <= EndpointToleranceUu,
            f"a link record stores the two world points it was authored with and never a projection of them, so the start must read back where it was written ({StartDriftUu}uu away)");

        Assert_True(EndDriftUu <= EndpointToleranceUu,
            f"a link record stores the two world points it was authored with and never a projection of them, so the end must read back where it was written ({EndDriftUu}uu away)");

        Assert_True(Record.Get_Direction() == ECk_GroundNav_LinkDirection::Bidirectional,
            f"the record was authored Bidirectional and must read back as such (got {Record.Get_Direction()})");

        Assert_Equals_Float(Record.Get_CostMultiplierForward(), LinkMultiplier, 0.001,
            "the forward multiplier must read back the value it was authored with");

        Assert_Equals_Float(Record.Get_CostMultiplierBackward(), LinkMultiplier, 0.001,
            "the backward multiplier must read back the value it was authored with");

        Assert_Equals_Float(Record.Get_ClearanceUu(), LinkClearanceUu, 0.001,
            "the clearance must read back the value it was authored with - it is what admission prices an agent against");

        Assert_True(Record.Get_Enable() == ECk_EnableDisable::Enable,
            f"the record was authored enabled and must read back as such (got {Record.Get_Enable()})");
    }

    //------------------------------------------------------------------------
    // The route across the link
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PlanAcrossLink(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_ground_nav_volume::Get_IsLinkLive(_LinkEntity),
            "the wait resolved on the surface being settled, so the link must still read live when the route is planned against it");

        Request_Route();
    }

    UFUNCTION()
    private void Step_AssertRouteUsesLink(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_ground_nav_path::Get_Result(_Planner);

        _LinkedStatus = Result.Get_Status();
        _LinkedWaypoints = Result.Get_Waypoints();

        const auto Waypoints = _LinkedWaypoints.Num();
        const auto CrossingIndex = Get_LinkCrossingIndex(_LinkedWaypoints);

        ck::nav::Display(f"[GROUNDNAV-LINK] linked route: status={_LinkedStatus} waypoints={Waypoints} linkEnteredAtWaypoint={CrossingIndex}");

        Assert_True(_LinkedStatus == ECk_GroundNav_PathStatus::Ready,
            f"the same query answered {_BlockedStatus} with no link and the only thing that changed is one live link over the wall, so it must now be Ready (got {_LinkedStatus})");

        // The discriminating half: Ready alone would also be satisfied by a route that got across some
        // other way, and there is no other way only because the wall says so.
        Assert_True(CrossingIndex >= 0,
            f"the route must step through the link's start and then its end as CONSECUTIVE waypoints - a link crossing is carried through the funnel as two degenerate portals, and a corner exactly on a link endpoint is emitted where it is. No such pair is in the {Waypoints} waypoints answered, so the route reached the far side without traversing the link.");
    }

    //------------------------------------------------------------------------
    // Disabling, then releasing
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_DisableLink(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Volume = _Field.Get_OriginVolume();

        // The SAME entity: identity is the entity, so this updates the record in place and keeps the
        // id the link was first admitted under rather than retiring it for a new one.
        utils_ground_nav_volume::Request_Link(Volume, Get_LinkRequest(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinkCompleted"));

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void Check_SettledAfterDisable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);

        if (utils_shared_bool::Get(OutResult) == false)
        { return; }

        if (_DisableSampled)
        { return; }

        _DisableSampled = true;
        _LinkLiveAfterDisable = utils_ground_nav_volume::Get_IsLinkLive(_LinkEntity);
        _DisableSettledFrames = _Field.Get_SettledFrames();
    }

    UFUNCTION()
    private void Step_AssertNotLiveAndPlan(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Frames = _DisableSettledFrames;
        const auto Live = _LinkLiveAfterDisable;

        ck::nav::Display(f"[GROUNDNAV-LINK] disabled: settledFrames={Frames} linkLiveAtSettled={Live}");

        Assert_Equals_Int(_LinkCompletions, 2,
            "the disabling request is a second link request against the same entity and owes its own completion");

        Assert_True(_LastLinkResult == ECk_Request_OperationResult::Succeeded,
            f"disabling a link is an update to a record that already passed admission, so it must complete Succeeded (got {_LastLinkResult})");

        Assert_False(Live,
            "live means IN EFFECT: a disabled record the field has already processed decides nothing, so Get_IsLinkLive must answer false once the surface has settled across the change.");

        Request_Route();
    }

    UFUNCTION()
    private void Step_AssertBlockedAgain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_ground_nav_path::Get_Result(_Planner);

        _DisabledStatus = Result.Get_Status();

        const auto Waypoints = Result.Get_Waypoints().Num();

        ck::nav::Display(f"[GROUNDNAV-LINK] route over the disabled link: status={_DisabledStatus} waypoints={Waypoints}");

        Assert_True(_DisabledStatus != ECk_GroundNav_PathStatus::Ready,
            f"a disabled link is invisible to search and to reachability once the publish that disabled it has landed, so the wall leaves no route again and the search must not answer Ready (got {_DisabledStatus})");
    }

    UFUNCTION()
    private void Step_ReleaseLink(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Volume = _Field.Get_OriginVolume();

        utils_ground_nav_volume::Request_ReleaseLink(Volume,
            FCk_Request_GroundNavVolume_ReleaseLink(_LinkEntity),
            FCk_Delegate_Request_OnCompleted(this, n"OnReleaseCompleted"));

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void Check_SettledAfterRelease(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);

        if (utils_shared_bool::Get(OutResult) == false)
        { return; }

        if (_ReleaseSampled)
        { return; }

        _ReleaseSampled = true;
        _RecordsAfterRelease = utils_ground_nav_volume::Get_LinkRecords(_Field.Get_OriginVolume()).Num();
        _ReleaseSettledFrames = _Field.Get_SettledFrames();
    }

    UFUNCTION()
    private void Step_AssertRecordsEmpty(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Frames = _ReleaseSettledFrames;
        const auto Records = _RecordsAfterRelease;
        const auto LinkedWaypoints = _LinkedWaypoints.Num();

        ck::nav::Display(f"[GROUNDNAV-LINK] released: settledFrames={Frames} recordsAtSettled={Records} linkedRouteWaypoints={LinkedWaypoints}");

        Assert_Equals_Int(_ReleaseCompletions, 1,
            "the release request owes exactly one completion");

        Assert_True(_LastReleaseResult == ECk_Request_OperationResult::Succeeded,
            f"releasing a record the volume holds must complete Succeeded (got {_LastReleaseResult})");

        Assert_Equals_Int(Records, 0,
            "releasing a link drops the record the entity owned, so the volume's reflected read-back must be empty once the surface has settled across it");
    }

    //------------------------------------------------------------------------
    // The request, built once so the enabled and disabled forms cannot drift
    //------------------------------------------------------------------------

    // The id is -1 because the VOLUME assigns it: the record's identity carries no setter,
    // and an update keeps the id the entity was first admitted under whatever is written here.
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

    private FVector Get_StartPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + StartOffsetX, Centre.Y, _Field.Get_FloorTopZ());
    }

    private FVector Get_GoalPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + GoalOffsetX, Centre.Y, _Field.Get_FloorTopZ());
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

    private FVector Get_PaintCentre()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + PaintOffsetX, Centre.Y + PaintOffsetY, _Field.Get_FloorTopZ());
    }

    // The index of the waypoint that is the link's START and is immediately followed by its END, or
    // -1 when the route carries no such pair. Consecutive rather than merely present: a route that
    // touched both points on separate legs never traversed the link.
    private int32 Get_LinkCrossingIndex(const TArray<FVector>& InWaypoints)
    {
        const auto LinkStart = Get_LinkStart();
        const auto LinkEnd = Get_LinkEnd();

        for (int32 Index = 0; Index + 1 < InWaypoints.Num(); Index++)
        {
            if ((InWaypoints[Index] - LinkStart).Size() > EndpointToleranceUu)
            { continue; }

            if ((InWaypoints[Index + 1] - LinkEnd).Size() > EndpointToleranceUu)
            { continue; }

            return Index;
        }

        return -1;
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

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. Three things here outlive this
    // test's own subtree: the provider is a WORLD selection every later fixture in this map reads,
    // the markup entity hangs off the world, and the fixture's field - plus any floor body it pushed
    // into the Jolt static world - would otherwise stay staged for the rest of the lane. The wall is
    // inside this runner's subtree and would be cascaded anyway; it is dropped here so the ground is
    // whole again before the next test in the shared PIE world looks at it.
    private void Teardown()
    {
        if (_Reported == false)
        {
            _Reported = true;
            _Field.Do_ReportCrossover("Link_AuthoredLinkIsLiveAndRoutesAcross", _Verdict);
        }

        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_Markup))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup));
            _Markup = FCk_Handle_NavSurfaceMarkup();
        }

        if (ck::IsValid(_LinkEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_LinkEntity);
            _LinkEntity = FCk_Handle();
        }

        if (ck::IsValid(_PlannerEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_PlannerEntity);
            _PlannerEntity = FCk_Handle();
        }

        _Field.Request_ReleaseOriginField();

        if (ck::IsValid(_WallEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_WallEntity);
            _WallEntity = FCk_Handle();
        }
    }
}
