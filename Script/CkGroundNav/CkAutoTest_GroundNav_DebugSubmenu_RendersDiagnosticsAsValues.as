// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: DEBUG SUBMENU RENDERS DIAGNOSTICS AS VALUES
//============================================================================
//
// The gameplay-debugger submenu, read the only way a test can read one: by the
// rows it builds. The base class owns the canvas and the submenu only decides
// what text to hand it, so Get_DebugRows is the whole surface under test and
// needs no debugger session, no player controller and no canvas to answer.
//
// The shape is one field, one planner and one route:
//
//   a GroundNav field over the origin floor, and the world switched onto it
//   -> a planner with no crowd agent on it plans one route across the floor
//   -> the submenu's rows for that planner carry the fragment's own values.
//
//----------------------------------------------------------------------------
// WHAT THIS PINS THAT THE FRAGMENT'S OWN TEST DOES NOT
//----------------------------------------------------------------------------
//
// That the SUBMENU reaches the fragment. The diagnostics are already pinned as
// values elsewhere; what is new here is the path from an entity handle to a
// row of text - the feature check, the handle conversion, the stamped gate,
// and each column's rendering. A submenu that compiled but read the wrong
// entity, or gated on the wrong flag, is caught here and nowhere else.
//
// Every row assertion compares against the value read off the fragment in the
// same step rather than against a literal, so a row that carries a plausible
// number the planner never produced still fails.
//
//----------------------------------------------------------------------------
// THE TWO NEGATIVES, AND WHY THEY COME FIRST
//----------------------------------------------------------------------------
//
// An invalid handle and an entity with no planner on it must each answer with
// a REASON row rather than an empty list: on a canvas, a panel with nothing in
// it and a panel that was never reached look the same. Both are asserted
// before the route is planned, so a submenu that answers with rows no matter
// what it was handed cannot pass the positive that follows.
//
// The crowd column is asserted ABSENT. This planner carries no crowd agent,
// and the waypoint cursor belongs to the crowd rather than to GroundNav - a
// row appearing here would be a column reading something it does not own.
//
// The provider is a WORLD selection every later fixture in this map reads, so
// the previous value is captured before the swap and handed back on every exit
// path including DoEndPlay - the engine TimeLimit path never runs the finish
// path.
//============================================================================

class UCk_AutoTest_GroundNav_DebugSubmenu_RendersDiagnosticsAsValues : UCk_AutoTest_Base
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
    private const float OffsetY = -200.0;

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

    // The subject. Built with NewObject rather than pulled off a profile: what is under test is the
    // submenu's own row building, and reaching it through a loaded debug profile would put a
    // maintainer's project-settings selection in the middle of the assertion.
    private UCk_GroundNav_DebugSubmenu _Submenu;

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
        Add_Step(          "nothing to show is said, never left blank",     n"Step_AssertNothingToShowIsSaid");
        Add_Step(          "plan one route across the origin floor",        n"Step_PlanRoute");
        Add_Step_WaitUntil("the route is answered",                         n"Check_PathAnswered",     PathFrameBudget);
        Add_Step(          "the rows carry the diagnostics values",         n"Step_AssertRows");
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
        _PlannerEntity.Set_DebugName(n"AutoTest_GroundNav_SubmenuPlanner");

        auto PathParams = FCk_Fragment_GroundNavPath_ParamsData(float32(AgentRadius));
        PathParams.Set_VerticalToleranceUu(float32(CellHeightUu * 4.0));

        _Planner = utils_ground_nav_path::Add(_PlannerEntity, PathParams);

        Assert_True(ck::IsValid(_Planner), "Add() must return a valid GroundNav path handle");

        _Submenu = Cast<UCk_GroundNav_DebugSubmenu>(NewObject(this, UCk_GroundNav_DebugSubmenu));

        Assert_True(ck::IsValid(_Submenu), "the submenu under test must construct");
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);
    }

    //------------------------------------------------------------------------
    // The negatives, taken before anything is planned
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertNothingToShowIsSaid(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto NoEntityRows = _Submenu.Get_DebugRows(FCk_Handle());

        Assert_True(NoEntityRows.Num() > 0,
            "an invalid handle must be answered with a row saying so - an empty panel and a panel nothing reached read alike on a canvas");

        Assert_True(Do_Get_RowContaining(NoEntityRows, "no entity").IsEmpty() == false,
            "and that row must say there is no entity behind the selected actor");

        // The runner's own entity is a real entity with no planner on it, which is the case a
        // debugger points at far more often than an invalid handle.
        const auto NoPlannerRows = _Submenu.Get_DebugRows(_SelfHandle);

        Assert_True(Do_Get_RowContaining(NoPlannerRows, "no GroundNav planner").IsEmpty() == false,
            "an entity without the Path feature must be answered with a row saying so");

        Assert_True(Do_Get_RowContaining(NoPlannerRows, "provider").IsEmpty(),
            "and it must not print columns it never read");
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
    //
    // The second half is the STAMP rather than the fresh-result flag, because the stamp is what the
    // rows below are read from: the diagnostics pass runs after the slot publishes, so a plan that
    // has landed and a plan the pass has copied are one tick apart and waiting on the earlier of the
    // two would read a fragment nobody had written yet.
    UFUNCTION()
    private void Check_PathAnswered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_PathCompletions >= _PathRequests
            && utils_ground_nav_path::Get_Diagnostics(_Planner).Get_HasBeenStamped());
    }

    //------------------------------------------------------------------------
    // The claim
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertRows(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Diagnostics = utils_ground_nav_path::Get_Diagnostics(_Planner);

        // Redundant with the wait above, and kept: a wait that stopped settling on the stamp would
        // otherwise turn every assertion below into a claim about initialisers.
        Assert_True(Diagnostics.Get_HasBeenStamped(),
            "the pass must have visited this planner before its rows can be about anything");

        const auto Rows = _Submenu.Get_DebugRows(_PlannerEntity);

        const auto Provider = Diagnostics.Get_Provider();
        const auto Waypoints = Diagnostics.Get_PublishedWaypointCount();
        const auto Epoch = Diagnostics.Get_CorridorEpoch();
        const auto PlannedAt = Diagnostics.Get_LastPlanWorldTime().Get_Seconds();

        const auto ProviderRow = Do_Get_RowContaining(Rows, "provider");
        const auto ProfileRow = Do_Get_RowContaining(Rows, "profile tag");
        const auto StatusRow = Do_Get_RowContaining(Rows, "path status");
        const auto WaypointsRow = Do_Get_RowContaining(Rows, "waypoints");
        const auto LinksRow = Do_Get_RowContaining(Rows, "corridor links");
        const auto EpochRow = Do_Get_RowContaining(Rows, "corridor epoch");
        const auto RepathRow = Do_Get_RowContaining(Rows, "repath required");
        const auto PlannedAtRow = Do_Get_RowContaining(Rows, "last plan at");

        ck::nav::Display(f"[GROUNDNAV-DEBUG-SUBMENU] rows={Rows.Num()} provider={ProviderRow} status={StatusRow} waypoints={WaypointsRow} links={LinksRow} epoch={EpochRow} repath={RepathRow} plannedAt={PlannedAtRow}");

        Assert_True(ProviderRow.Contains(f"{Provider}"),
            f"the provider row must carry the provider the fragment named (row was '{ProviderRow}', fragment said {Provider})");

        Assert_True(ProfileRow.Contains("untagged default"),
            f"the request named no profile, so the profile row must say the corridor was planned over the volume's untagged default (row was '{ProfileRow}')");

        Assert_True(StatusRow.Contains(f"{ECk_GroundNav_PathStatus::Ready}"),
            f"the origin floor is open ground between the two ends, so the status row must say Ready (row was '{StatusRow}')");

        Assert_True(Waypoints > 0,
            f"a Ready route publishes waypoints to walk, and without one the row below would assert nothing (got {Waypoints})");

        Assert_True(WaypointsRow.Contains(f"{Waypoints}"),
            f"the waypoint row must carry the count the fragment published (row was '{WaypointsRow}', fragment said {Waypoints})");

        Assert_True(LinksRow.Contains("(none)"),
            f"the origin floor carries no authored links, so the corridor row must say the route crosses none (row was '{LinksRow}')");

        Assert_True(Epoch > 0,
            f"the corridor was found on a field a build published, so its epoch must be one a build reached (got {Epoch})");

        Assert_True(EpochRow.Contains(f"{Epoch}"),
            f"and the epoch row must carry it (row was '{EpochRow}', fragment said {Epoch})");

        Assert_True(RepathRow.Contains("false"),
            f"nothing has rebuilt ground under this route since it was planned, so the repath row must read false (row was '{RepathRow}')");

        Assert_True(PlannedAt > 0.0,
            f"the plan was made in a world that has been running for frames, so it must be dated past zero (got {PlannedAt})");

        Assert_True(PlannedAtRow.IsEmpty() == false,
            "and the date must reach a row");

        // The column that is the crowd's, on a planner that has no crowd agent.
        Assert_True(Do_Get_RowContaining(Rows, "waypoint index").IsEmpty(),
            "this planner carries no crowd agent, so the waypoint cursor - which is the crowd's - must not be printed at all");
    }

    //------------------------------------------------------------------------
    // Rows
    //------------------------------------------------------------------------

    // The first row carrying InNeedle, or an empty string when none does. Every column label below
    // is unique among the rows, so matching on the label is how a row is addressed without the
    // assertions depending on the order or the padding the submenu prints with.
    private FString Do_Get_RowContaining(const TArray<FText>&in InRows, const FString&in InNeedle)
    {
        for (int32 Index = 0; Index < InRows.Num(); Index++)
        {
            const auto RowText = InRows[Index].ToString();

            if (RowText.Contains(InNeedle))
            { return RowText; }
        }

        return "";
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
            _Field.Do_ReportCrossover("DebugSubmenu_RendersDiagnosticsAsValues", _Verdict);
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
