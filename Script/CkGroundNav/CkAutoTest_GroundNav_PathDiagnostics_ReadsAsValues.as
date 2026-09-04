// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: PATH DIAGNOSTICS READ AS VALUES
//============================================================================
//
// The third environment for the per-agent diagnostics fragment. The stamp and
// every column on it are pinned at Layer 1 from C++ over a bare world; this is
// the same value read through the same UFUNCTION from AngelScript, against a
// world that actually ticks, so a binding that compiled but never reached the
// agent is caught here rather than in a debugger.
//
// The shape is one field, one planner and one route:
//
//   a GroundNav field over the origin floor, and the world switched onto it
//   -> a planner with no crowd agent on it plans one route across the floor
//   -> its diagnostics name the provider, the profile, the route and the date.
//
//----------------------------------------------------------------------------
// WHY THE PLANNER CARRIES NO CROWD AGENT
//----------------------------------------------------------------------------
//
// The fragment carries what GROUNDNAV owns and stops there. How far along the
// route a body has walked is the crowd's cursor and lives on the crowd agent,
// so an entity with no crowd agent on it is the case that proves the columns
// below need nothing from one - a planner that had to be steered to read its
// own diagnostics would be a fragment that is not really per-planner at all.
//
//----------------------------------------------------------------------------
// THE TWO COLUMNS THE C++ LAYER CANNOT ASSERT
//----------------------------------------------------------------------------
//
//   1. THE DATE. The Layer 1 fixture's world never ticks, so its time seconds
//      never leave zero and the only claim available there is that the column
//      is the world's clock rather than the platform one. Here the world runs,
//      so the date is asserted to be PAST zero - which is the whole of what a
//      "when was this planned" column is for.
//
//   2. THE PROVIDER, resolved through the live per-world selection this test
//      makes rather than through a mirror a test wrote by hand.
//
// The corridor's link ids are asserted EMPTY, and that is a statement about
// this scene: the origin floor carries no authored links, so a route across it
// crosses none, and an id appearing here would be a corridor from somewhere
// else.
//
// The provider is a WORLD selection every later fixture in this map reads, so
// the previous value is captured before the swap and handed back on every exit
// path including DoEndPlay - the engine TimeLimit path never runs the finish
// path.
//============================================================================

class UCk_AutoTest_GroundNav_PathDiagnostics_ReadsAsValues : UCk_AutoTest_Base
{
    // One 16-tile bake, one settle and one path episode, each on its own budgeted
    // condition. Deliberately slack: a contract that expires on the harness's
    // anonymous TimesUp names nothing.
    default _TimeoutSeconds = 300.0f;

    //------------------------------------------------------------------------
    // Geometry, as offsets from the floor's own centre and top face. Both ends
    // sit well inside the field's 1000uu half-extent, so the route is a plain
    // crossing of open ground and never a question about the field's edge.
    //------------------------------------------------------------------------

    private const float StartOffsetX = -600.0;
    private const float GoalOffsetX = 600.0;
    private const float OffsetY = 200.0;

    private const float AgentRadius = 42.0;
    private const float CellHeightUu = 10.0;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 PathFrameBudget = 1800;

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _PlannerEntity;

    private FCk_Handle_GroundNavPath _Planner;

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

        Add_Step(          "stage a GroundNav field over the origin floor", n"Step_StageField");
        Add_Step_WaitUntil("the origin field reports itself built",         n"Check_OriginFieldBuilt", BuildFrameBudget);
        Add_Step(          "switch the world onto GroundNav",               n"Step_SwitchProvider");
        Add_Step_WaitUntil("the surface settles after the provider switch", n"Check_SurfaceSettled",   SurfaceFrameBudget);
        Add_Step(          "the unplanned agent carries no route yet",      n"Step_AssertNothingPlanned");
        Add_Step(          "plan one route across the origin floor",        n"Step_PlanRoute");
        Add_Step_WaitUntil("the route is answered",                         n"Check_PathAnswered",     PathFrameBudget);
        Add_Step(          "the diagnostics name what was planned",         n"Step_AssertDiagnostics");
        Add_Step(          "hand the world back",                           n"Step_Cleanup");

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

        // No crowd agent, deliberately - see the header. The planner is the whole entity.
        _PlannerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _PlannerEntity.Request_OverrideToSelf();
        _PlannerEntity.Set_DebugName(n"AutoTest_GroundNav_DiagnosticsPlanner");

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
    // The baseline, taken before anything is planned
    //------------------------------------------------------------------------

    // The NEGATIVE the assertions after the plan rest on. Without it, columns that were never stamped
    // at all could carry the values below by accident of their own initialisers.
    UFUNCTION()
    private void Step_AssertNothingPlanned(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Diagnostics = utils_ground_nav_path::Get_Diagnostics(_Planner);

        const auto Waypoints = Diagnostics.Get_PublishedWaypointCount();
        const auto PlannedAt = Diagnostics.Get_LastPlanWorldTime().Get_Seconds();

        ck::nav::Display(f"[GROUNDNAV-PATH-DIAG] before: waypoints={Waypoints} plannedAt={PlannedAt}");

        Assert_Equals_Int(Waypoints, 0,
            "an agent that has never planned publishes no waypoints, so the count it reads back must be zero");

        Assert_True(PlannedAt == 0.0,
            f"and no plan has been dated on it yet (got {PlannedAt})");
    }

    //------------------------------------------------------------------------
    // The path episode
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PlanRoute(FCk_Handle InHandle, FInstancedStruct InPayload)
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

    //------------------------------------------------------------------------
    // The claim
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertDiagnostics(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_ground_nav_path::Get_Result(_Planner);
        const auto Diagnostics = utils_ground_nav_path::Get_Diagnostics(_Planner);

        const auto Status = Diagnostics.Get_PathStatus();
        const auto Provider = Diagnostics.Get_Provider();
        const auto Waypoints = Diagnostics.Get_PublishedWaypointCount();
        const auto LinkIds = Diagnostics.Get_CorridorLinkIds().Num();
        const auto Epoch = Diagnostics.Get_CorridorEpoch();
        const auto Repath = Diagnostics.Get_RepathRequired();
        const auto PlannedAt = Diagnostics.Get_LastPlanWorldTime().Get_Seconds();

        ck::nav::Display(f"[GROUNDNAV-PATH-DIAG] provider={Provider} status={Status} waypoints={Waypoints} links={LinkIds} epoch={Epoch} repath={Repath} plannedAt={PlannedAt}");

        Assert_True(Status == ECk_GroundNav_PathStatus::Ready,
            f"the origin floor is open ground between the two ends, so the route must answer Ready (got {Status})");

        Assert_True(Provider == ECk_NavSurface_Provider::GroundNav,
            f"the world was switched onto GroundNav before this route was planned, so the provider column must name it (got {Provider})");

        Assert_False(Diagnostics.Get_ProfileTag().IsValid(),
            "the request named no profile, so the corridor was planned over the volume's untagged default and the profile column must be empty");

        // Both halves: the column is the route's own size AND that size is not zero. Equality alone
        // would pass on a stamp that copied nothing over a plan that published nothing.
        Assert_Equals_Int(Waypoints, Result.Get_Waypoints().Num(),
            "the waypoint count is a copy of the published route's own size, so the two must agree");

        Assert_True(Waypoints > 0,
            f"and a Ready route publishes waypoints to walk (got {Waypoints})");

        Assert_Equals_Int(LinkIds, 0,
            "the origin floor carries no authored links, so a route across it crosses none and the corridor's link ids must be empty");

        Assert_True(Epoch > 0,
            f"the corridor was found on a field a build published, so its epoch must be one a build reached (got {Epoch})");

        Assert_False(Repath,
            "nothing has rebuilt ground under this route since it was planned, so the agent must not stand flagged for a repath");

        // The column the Layer 1 fixture cannot make this claim about: its world never ticks. Here
        // the world runs, so a date still sitting at zero is a stamp that never read the clock.
        Assert_True(PlannedAt > 0.0,
            f"the plan was made in a world that has been running for frames, so it must be dated past zero (got {PlannedAt})");
    }

    //------------------------------------------------------------------------
    // Geometry
    //------------------------------------------------------------------------

    private FVector Get_StartPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + StartOffsetX, Centre.Y + OffsetY, _Field.Get_FloorTopZ());
    }

    private FVector Get_GoalPoint()
    {
        const auto Centre = _Field.Get_FloorCentre();
        return FVector(Centre.X + GoalOffsetX, Centre.Y + OffsetY, _Field.Get_FloorTopZ());
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
            _Field.Do_ReportCrossover("PathDiagnostics_ReadsAsValues", _Verdict);
        }

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

        _Field.Request_ReleaseOriginField();
    }
}
