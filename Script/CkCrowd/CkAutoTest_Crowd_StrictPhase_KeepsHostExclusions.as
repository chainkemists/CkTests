// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: THE STRICT PHASE KEEPS THE AGENT'S OWN EXCLUSIONS
//============================================================================
//
// Two-phase planning plans every route first in a STRICT phase that treats standing crowds as
// walls. That phase adds an exclusion - it must not replace the agent's own filter. When it plans
// under a crowd-only filter instead, every area the host filter excludes becomes walkable the
// moment a crowd stands in the way: BusterBlock shoppers, whose filter excludes each door's
// boundary slab, walked out of one door and back in through the next to get around a crowd.
//
// Shape (Recast; painted over the level's own navmesh):
//
//        y=+400  ================= impassable ================
//                lane N:   [ box painted Nav.Area.Restricted ]
//        y=+60                    [divider]
//        y=-60   walker ->        (impassable)         -> goal
//                lane S:   pickets standing across the lane
//        y=-400  ================= impassable ================
//
// The walker plans with Nav.Filter.CkTests.ExcludeRestricted (excludes the box) and no strict tag -
// the framework's default path. The only crowd-free route runs through the box; the only box-free
// route runs through the standing crowd. Fixture checks (sync path queries) prove both before the
// walker moves. Contract: no point of the walker's installed route enters the box - a strict phase
// that keeps the host filter finds no crowd-free route and falls back to the crowd-toll route.
//============================================================================

class UCk_AutoTest_Crowd_StrictPhase_KeepsHostExclusions : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private const float AgentRadius = 42.0f;
    private const FVector Spawn = FVector(-700.0, 0.0, 0.0);
    private const FVector Goal = FVector(700.0, 0.0, 0.0);
    private const float CorridorHalfWidth = 400.0;
    private const float WallHalfExtent = 2000.0;
    private const FVector DividerHalfExtents = FVector(60.0, 60.0, 200.0);
    // The painted box spans lane N from the divider to the wall, overlapping both so no sliver of
    // lane N stays unpainted.
    private const FVector BoxCentre = FVector(0.0, 230.0, 0.0);
    private const FVector BoxHalfExtents = FVector(100.0, 190.0, 200.0);
    // The box as the assertion reads it: shrunk a little, so a route that only grazes its edge
    // does not count as entering it.
    private const float BoxAssertShrink = 5.0;
    private const float RouteSampleStep = 20.0;
    private const float ProbeHalfExtent = 15.0;

    private FCk_Handle_NavSurfaceMarkup _NorthWall;
    private FCk_Handle_NavSurfaceMarkup _SouthWall;
    private FCk_Handle_NavSurfaceMarkup _Divider;
    private FCk_Handle_NavSurfaceMarkup _Box;
    private TArray<FCk_Handle_CrowdAgent> _Pickets;
    private FCk_Handle_CrowdAgent _Walker;
    private FGameplayTag _HostFilter;
    private float _FloorZ = 0.0;
    private int32 _RevisionAtDispatch = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // The defect and the fix both live in the Recast strict-phase filter; GroundNav prices the
        // crowd and applies its strict verdict at install, so it never took this path.
        if (utils_nav_surface::Get_Provider() != ECk_NavSurface_Provider::Recast)
        {
            Assert_True(true, "not applicable: the strict-phase filter under test is the Recast provider's");
            FinishSuccess();
            return;
        }

        _HostFilter = utils_gameplay_tag::ResolveGameplayTag(n"Nav.Filter.CkTests.ExcludeRestricted");
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        Add_Step_WaitUntil( "the floor under the walker's spawn and goal projects",      n"Check_FloorFound", 0, 8.0f);
        Add_Step(           "paint the corridor, the divider and the excluded box",     n"Step_Paint");
        Add_Step_WaitUntil( "the paint is live and the host filter routes via lane S",  n"Check_PaintLiveAndHostAvoidsBox", 0, 10.0f);
        Add_Step(           "stand the pickets across lane S",                          n"Step_SpawnPickets");
        Add_Step_WaitUntil( "every picket is confirmed standing markup",                n"Check_PicketsConfirmed", 0, 8.0f);
        Add_Step(           "fixture: the only crowd-free route crosses the box",       n"Step_AssertFixture");
        Add_Step(           "the walker plans under its host filter, no strict tag",    n"Step_DispatchWalker");
        Add_Step_WaitUntil( "the walker's route is installed",                          n"Check_RouteInstalled", 0, 8.0f);
        Add_Step(           "no point of the installed route enters the box",           n"Step_AssertRouteAvoidsBox");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_FloorFound(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        const auto AtSpawn = Do_Project(Spawn + FVector(0.0, 0.0, 100.0), FVector(100.0, 100.0, 300.0));
        const auto AtGoal = Do_Project(Goal + FVector(0.0, 0.0, 100.0), FVector(100.0, 100.0, 300.0));
        if (AtSpawn.Get_Status() != ECk_NavSurface_QueryStatus::Success
            || AtGoal.Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            Res.Set(false);
            return;
        }
        _FloorZ = float(AtSpawn.Get_Location().Z);
        Res.Set(true);
    }

    UFUNCTION()
    private void Step_Paint(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        const auto WallCentreY = CorridorHalfWidth + WallHalfExtent;
        _NorthWall = Paint_Impassable(FVector(0.0, WallCentreY, _FloorZ),
            FVector(WallHalfExtent, WallHalfExtent, 200.0));
        _SouthWall = Paint_Impassable(FVector(0.0, -WallCentreY, _FloorZ),
            FVector(WallHalfExtent, WallHalfExtent, 200.0));
        _Divider = Paint_Impassable(FVector(0.0, 0.0, _FloorZ), DividerHalfExtents);

        auto BoxRequest = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(BoxHalfExtents)),
            utils_gameplay_tag::ResolveGameplayTag(n"Nav.Area.Restricted"));
        BoxRequest.Set_WorldTransform(FTransform(FRotator::ZeroRotator,
            FVector(BoxCentre.X, BoxCentre.Y, _FloorZ), FVector::OneVector));
        _Box = utils_nav_surface::Request_AreaMarkup(BoxRequest);

        // Markups are parented to the world, outside this runner's teardown subtree.
        Track_ForCleanup(FCk_Handle(_NorthWall));
        Track_ForCleanup(FCk_Handle(_SouthWall));
        Track_ForCleanup(FCk_Handle(_Divider));
        Track_ForCleanup(FCk_Handle(_Box));

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }

    // Impassable paint removes the polygons Get_IsMarkupLive samples, so its consequence is the
    // condition: a point inside each impassable box no longer projects.
    UFUNCTION()
    private void Check_PaintLiveAndHostAvoidsBox(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        const auto Probe = FVector(ProbeHalfExtent, ProbeHalfExtent, 150.0);
        const bool WallsLive =
            Do_Project(FVector(0.0, CorridorHalfWidth + 60.0, _FloorZ), Probe).Get_Status() != ECk_NavSurface_QueryStatus::Success
            && Do_Project(FVector(0.0, -CorridorHalfWidth - 60.0, _FloorZ), Probe).Get_Status() != ECk_NavSurface_QueryStatus::Success;
        const bool DividerLive =
            Do_Project(FVector(0.0, 0.0, _FloorZ), Probe).Get_Status() != ECk_NavSurface_QueryStatus::Success;
        const bool BoxLive = utils_nav_surface::Get_IsMarkupLive(_Box);
        if (WallsLive == false || DividerLive == false || BoxLive == false)
        {
            Res.Set(false);
            return;
        }
        // The host filter alone must avoid the box - through lane S, the only other way across.
        const auto HostPath = Do_FindPath(_HostFilter, false);
        Res.Set(HostPath.Get_Status() == ECk_NavSurface_QueryStatus::Success
            && Get_RouteEntersBox(HostPath.Get_Waypoints()) == false
            && Get_RouteCrossesLaneS(HostPath.Get_Waypoints()));
    }

    UFUNCTION()
    private void Step_SpawnPickets(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = InHandle;
        // Each picket paints a box twice its radius; 110uu apart they seal lane S end to end.
        for (int32 i = 0; i < 3; ++i)
        {
            const float Y = -120.0 - 110.0 * float(i);
            _Pickets.Add(Spawn_Agent(Owner, FVector(0.0, Y, _FloorZ + 100.0), FGameplayTag()));
        }
    }

    UFUNCTION()
    private void Check_PicketsConfirmed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        for (auto Picket : _Pickets)
        {
            if (utils_crowd_agent::Get_IsStationaryMarkupConfirmed(Picket) == false)
            {
                Res.Set(false);
                return;
            }
        }
        Res.Set(true);
    }

    // Without these two facts the assertion below cannot tell a strict phase that kept the host
    // filter from one that dropped it.
    UFUNCTION()
    private void Step_AssertFixture(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        const auto HostStrict = Do_FindPath(_HostFilter, true);
        const auto CrowdOnly = Do_FindPath(FGameplayTag(), true);
        const FString Diag = f" [DIAG hostStrict={HostStrict.Get_Status()} {Dump(HostStrict.Get_Waypoints())} crowdOnly={CrowdOnly.Get_Status()} {Dump(CrowdOnly.Get_Waypoints())}]";

        Assert_False(HostStrict.Get_Status() == ECk_NavSurface_QueryStatus::Success
                && Get_RouteEntersBox(HostStrict.Get_Waypoints()) == false,
            "fixture: no route avoids both the standing crowd and the box" + Diag);
        Assert_True(CrowdOnly.Get_Status() == ECk_NavSurface_QueryStatus::Success
                && Get_RouteEntersBox(CrowdOnly.Get_Waypoints()),
            "fixture: a crowd-free route exists, and it crosses the box" + Diag);
    }

    UFUNCTION()
    private void Step_DispatchWalker(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }
        auto Owner = InHandle;
        _Walker = Spawn_Agent(Owner, Spawn + FVector(0.0, 0.0, _FloorZ + 100.0), _HostFilter);
        utils_crowd_agent::BindTo_OnGoalFailed(_Walker,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        _RevisionAtDispatch = utils_nav::Get_PathResult(_Walker).Get_RequestRevision();
        utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(Goal + FVector(0.0, 0.0, _FloorZ)));
    }

    UFUNCTION()
    private void Check_RouteInstalled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav::Get_PathStatus(_Walker) == ECk_Nav_PathStatus::Ready
            && utils_nav::Get_PathResult(_Walker).Get_RequestRevision() > _RevisionAtDispatch);
    }

    UFUNCTION()
    private void Step_AssertRouteAvoidsBox(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Route = TArray<FVector>();
        Route.Add(utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(_Walker))));
        Route.Append(utils_nav::Get_PathResult(_Walker).Get_Waypoints());
        const FString Filter = utils_crowd_agent::Get_NavQueryFilter(_Walker).ToString();
        const FString Diag = f" [DIAG filter={Filter} route={Dump(Route)}]";

        Assert_True(utils_crowd_agent::Get_NavQueryFilter(_Walker) == _HostFilter,
            "the walker plans under the host filter it was given" + Diag);
        Assert_False(Get_RouteEntersBox(Route),
            "STRICT LEAK: the installed route enters the area the agent's own filter excludes - the strict phase planned around the crowd under a filter that dropped the host's exclusions" + Diag);
        FinishSuccess();
    }

    UFUNCTION()
    private void OnWalkerFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        FinishFailure(f"the walker's goal FAILED although the crowd-toll route through lane S exists (reason={InInfo.Get_Reason()}, crowdFree={InInfo.Get_NoCrowdFreeRouteExisted()})");
    }

    //------------------------------------------------------------------------
    // Helpers
    //------------------------------------------------------------------------

    private FCk_NavSurface_PathResult Do_FindPath(FGameplayTag InFilter, bool InExcludeStandingCrowds) const
    {
        auto Query = FCk_NavSurface_PathQuery(
            Spawn + FVector(0.0, 0.0, _FloorZ), Goal + FVector(0.0, 0.0, _FloorZ));
        Query.Set_QueryFilter(InFilter);
        Query.Set_AgentRadiusUu(AgentRadius);
        if (InExcludeStandingCrowds)
        {
            auto Overlay = FCk_Nav_QueryFilterOverlay();
            auto Excluded = TArray<FGameplayTag>();
            Excluded.Add(utils_gameplay_tag::ResolveGameplayTag(n"Nav.Area.Crowd.Agent"));
            Overlay.Set_ExcludedAreaTags(Excluded);
            Query.Set_QueryFilterOverlay(Overlay);
        }
        return utils_nav_surface::Try_FindPathSync(Query);
    }

    private FCk_NavSurface_ProjectionResult Do_Project(FVector InPoint, FVector InSearchHalfExtents) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(InSearchHalfExtents);
        return utils_nav_surface::Try_ProjectPoint(Query);
    }

    private FCk_Handle_NavSurfaceMarkup Paint_Impassable(FVector InCentre, FVector InHalfExtents)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(InHalfExtents)), FGameplayTag());
        Request.Set_WorldTransform(FTransform(FRotator::ZeroRotator, InCentre, FVector::OneVector));
        return utils_nav_surface::Request_ImpassableBox(Request);
    }

    private FCk_Handle_CrowdAgent Spawn_Agent(FCk_Handle& InOwner, FVector InLoc, FGameplayTag InFilter)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(AgentRadius, 192.0f);
        Params.Set_NavQueryFilter(InFilter);
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, InLoc, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);
        return Agent;
    }

    // Walks the polyline in RouteSampleStep steps, so a segment that crosses the box between two
    // waypoints outside it still counts.
    private bool Get_RouteEntersBox(const TArray<FVector>& InRoute) const
    {
        const float MinX = BoxCentre.X - BoxHalfExtents.X + BoxAssertShrink;
        const float MaxX = BoxCentre.X + BoxHalfExtents.X - BoxAssertShrink;
        const float MinY = BoxCentre.Y - BoxHalfExtents.Y + BoxAssertShrink;
        const float MaxY = BoxCentre.Y + BoxHalfExtents.Y - BoxAssertShrink;
        for (int32 i = 0; i < InRoute.Num(); ++i)
        {
            const auto From = i == 0 ? InRoute[0] : InRoute[i - 1];
            const auto To = InRoute[i];
            const float Length = float((To - From).Size2D());
            const int32 Samples = Math::Max(1, Math::CeilToInt(Length / RouteSampleStep));
            for (int32 s = 0; s <= Samples; ++s)
            {
                const auto P = From + (To - From) * (float(s) / float(Samples));
                if (P.X > MinX && P.X < MaxX && P.Y > MinY && P.Y < MaxY)
                { return true; }
            }
        }
        return false;
    }

    // True when the route crosses x=0 south of the divider.
    private bool Get_RouteCrossesLaneS(const TArray<FVector>& InRoute) const
    {
        auto Previous = Spawn;
        for (auto Point : InRoute)
        {
            if (Previous.X <= 0.0 && Point.X >= 0.0)
            {
                const float T = Math::Abs(Point.X - Previous.X) < 0.001
                    ? 0.0 : float(-Previous.X / (Point.X - Previous.X));
                const float Y = float(Previous.Y + (Point.Y - Previous.Y) * T);
                return Y < -DividerHalfExtents.Y;
            }
            Previous = Point;
        }
        return false;
    }

    private FString Dump(const TArray<FVector>& InRoute) const
    {
        auto Text = FString("");
        for (auto Point : InRoute)
        { Text += f"({Math::RoundToInt(float32(Point.X))},{Math::RoundToInt(float32(Point.Y))}) "; }
        return Text;
    }
}

class ACk_AutoTest_Crowd_StrictPhase_KeepsHostExclusions_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_StrictPhase_KeepsHostExclusions;
    default _TimeoutSeconds = 30.0f;
}
