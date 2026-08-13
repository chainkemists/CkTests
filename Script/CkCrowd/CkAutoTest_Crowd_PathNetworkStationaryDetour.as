// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: PATH-NETWORK ROUTE LOCALLY DETOURS A STATIONARY LINE
//
// A PathNetwork is a route preference, not a movement boundary. Stationary-agent
// markup must therefore be allowed to bend the installed CrowdAgent path outside
// a sidewalk ribbon, after which the path rejoins the remaining corridor.
//
// The fixture also forces the route-install-before-markup ordering that occurs in
// live play:
//
//  1. Install the follower's straight route before the pickets exist.
//  2. Spawn the pickets and wait until their markup is confirmed on the navmesh.
//  3. Prove plain Recast detours, then require the already
//     walking PathNetwork agent to refresh, leave the ribbon, and rejoin it.
//  4. Retire that walker, then spawn a new PathNetwork follower inside two confirmed
//     markup discs. Its raw preferred route still crosses the line, but its installed
//     nav plan must start outside the overlap and detour around it.
//
// Red behavior includes failing to invalidate the already-installed straight route
// when the picket markup reaches the mesh.
//============================================================================

class UCk_AutoTest_Crowd_PathNetworkStationaryDetour : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 60.0f;

    private const float StartX = -450.0;
    private const float GoalX = 450.0;
    private const int32 PicketCount = 5;
    private const float PicketSpacingUu = 100.0;
    private const float MinClearanceUu = 50.0;
    private const float RibbonHalfWidthUu = 100.0;
    private const float MinOffRibbonY = 150.0;
    private const int32 MaxInstalledPathPolls = 100;
    private const float AgentRadiusUu = 42.0;
    private const float StationaryMarkupRadiusUu = 84.0;
    // Matches production: markup radius + moving-agent radius + endpoint margin.
    private const float ExpandedMarkupRadiusUu =
        StationaryMarkupRadiusUu + AgentRadiusUu + 1.0;
    // The downstream PathNetwork splice avoids the painted 84uu markup itself; this separate
    // threshold keeps a small observable margin without conflating it with the egress envelope.
    private const float InsideRouteMinClearanceUu = 90.0;
    // y = -150 is the seam between the -200 and -100 pickets: 50uu from each
    // centre, inside both stationary-markup discs and their expanded physical union.
    private const float InsideSpawnY = -150.0;
    private const int32 MaxInsidePlanPolls = 150;
    private const int32 MaxFirstWalkerRetirePolls = 20;

    private TArray<FVector> _PicketLocations;
    private TArray<FCk_Handle_CrowdAgent> _Pickets;
    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_CrowdAgent _Walker;
    private FCk_Handle _WalkerEntity;
    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _ProbeDetoured = false;
    private bool _WalkerSpawned = false;
    private bool _RouteReady = false;
    private bool _SawPreConfirmationStraightInstall = false;
    private int32 _InstalledPathPolls = 0;
    private float _LastInstalledClearance = -1.0;
    private float _RouteClearance = -1.0;
    private FCk_Handle_CrowdAgent _InsideWalker;
    private FCk_Handle _InsideWalkerEntity;
    private bool _FirstWalkerRetiring = false;
    private int32 _FirstWalkerRetirePolls = 0;
    private bool _InsideWalkerSpawned = false;
    private bool _InsideRawRouteReady = false;
    private bool _InsideInstalledPlanEscaped = false;
    private int32 _InsidePlanPolls = 0;
    private float _InsideRawClearance = -1.0;
    private float _InsideInstalledClearance = -1.0;
    private float _InsideExitWaypointClearance = -1.0;
    private bool _InsideExitWaypointIsLateralEscape = false;
    private float _InsideBodyClearance = -1.0;
    private float _InsideDistanceMoved = 0.0;
    private FVector _InsideSpawnLocation;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(
            LocalHandle,
            FTransform(
                FRotator::ZeroRotator,
                FVector(StartX, 0.0, 100.0),
                FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.1));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    UFUNCTION()
    private void OnPoll(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto SelfHandle = DoGet_ScriptEntity();

        if (_MeshFound == false)
        {
            FVector OriginOnMesh;
            FVector StartOnMesh;
            FVector GoalOnMesh;
            if (utils_nav::Try_ProjectOntoNavmesh(
                    SelfHandle,
                    FVector::ZeroVector,
                    100.0f,
                    OriginOnMesh,
                    300.0f) == false ||
                utils_nav::Try_ProjectOntoNavmesh(
                    SelfHandle,
                    FVector(StartX, 0.0, 0.0),
                    100.0f,
                    StartOnMesh,
                    300.0f) == false ||
                utils_nav::Try_ProjectOntoNavmesh(
                    SelfHandle,
                    FVector(GoalX, 0.0, 0.0),
                    100.0f,
                    GoalOnMesh,
                    300.0f) == false)
            {
                return;
            }

            _MeshFound = true;
            _FloorZ = float(OriginOnMesh.Z);
            BuildStraightNetwork(SelfHandle);
            return;
        }

        if (utils_path_network::Get_IsBuilt(_Network) == false)
        { return; }

        if (_FirstWalkerRetiring)
        { return; }

        if (_InsideWalkerSpawned)
        {
            PollInsideOverlapPhase();
            return;
        }

        if (_WalkerSpawned == false)
        {
            SpawnWalker(SelfHandle);
            return;
        }

        if (_SawPreConfirmationStraightInstall == false)
        {
            if (_RouteReady == false ||
                utils_nav::Get_PathStatus(_WalkerEntity) != ECk_Nav_PathStatus::Ready)
            { return; }

            // Create the blockers only after the route is installed. This removes
            // dependence on observing an async paint-before-confirm frame while still
            // proving that later confirmation invalidates and bends an active route.
            SpawnPicketLine(SelfHandle);
            const auto InitialResult = utils_nav::Get_PathResult(_WalkerEntity);
            const auto InitialClearance = Compute_WorstClearance(
                InitialResult.Get_Waypoints(),
                FVector(StartX, 0.0, _FloorZ));
            _RouteClearance = InitialClearance;
            if (InitialClearance >= MinClearanceUu ||
                LeavesAndRejoinsRibbon(InitialResult.Get_Waypoints()))
            {
                FinishFailure(
                    f"fixture requires a straight pre-confirmation sidewalk install; clearance was {InitialClearance}uu");
                return;
            }

            _SawPreConfirmationStraightInstall = true;
            return;
        }

        for (auto Picket : _Pickets)
        {
            if (utils_crowd_agent::Get_IsStationaryMarkupConfirmed(Picket) == false)
            { return; }
        }

        if (_ProbeDetoured == false)
        {
            if (utils_nav::Get_PathStatus(SelfHandle) == ECk_Nav_PathStatus::Ready)
            {
                const auto ProbeResult = utils_nav::Get_PathResult(SelfHandle);
                const auto ProbeClearance = Compute_WorstClearance(
                    ProbeResult.Get_Waypoints(),
                    FVector(StartX, 0.0, _FloorZ));
                if (ProbeClearance >= MinClearanceUu)
                {
                    _ProbeDetoured = true;
                    return;
                }
            }

            utils_nav::Request_FindPath(
                SelfHandle,
                FCk_Request_Nav_FindPath(FVector(GoalX, 0.0, _FloorZ)));
            return;
        }

        if (utils_nav::Get_PathStatus(_WalkerEntity) == ECk_Nav_PathStatus::Ready)
        {
            const auto Result = utils_nav::Get_PathResult(_WalkerEntity);
            const auto Waypoints = Result.Get_Waypoints();
            _LastInstalledClearance = Compute_WorstClearance(
                Waypoints,
                utils_transform::Get_EntityCurrentLocation(
                    utils_transform::DoCastChecked(_WalkerEntity)));

            if (_LastInstalledClearance >= MinClearanceUu &&
                LeavesAndRejoinsRibbon(Waypoints))
            {
                BeginInsideOverlapPhase();
                return;
            }
        }

        _InstalledPathPolls += 1;
        if (_InstalledPathPolls > MaxInstalledPathPolls)
        {
            FinishFailure(
                f"a straight route installed before markup confirmation and plain Recast later detoured, but the PathNetwork-backed CrowdAgent never refreshed, left, and rejoined its ribbon after {MaxInstalledPathPolls} polls; installed clearance {_LastInstalledClearance}uu, raw route clearance {_RouteClearance}uu");
        }
    }

    private void BeginInsideOverlapPhase()
    {
        if (ck::Is_NOT_Valid(_WalkerEntity))
        {
            FinishFailure("first walker became invalid before the inside-overlap phase could retire it");
            return;
        }

        _FirstWalkerRetiring = true;
        FCk_Handle WalkerToDestroy = _WalkerEntity;
        utils_entity_lifetime::Request_DestroyEntity(WalkerToDestroy);
        WaitOneFrame(n"OnFirstWalkerDestroySettled");
    }

    UFUNCTION()
    private void OnFirstWalkerDestroySettled(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (ck::IsValid(_WalkerEntity))
        {
            _FirstWalkerRetirePolls += 1;
            if (_FirstWalkerRetirePolls > MaxFirstWalkerRetirePolls)
            {
                FinishFailure(
                    f"first walker remained valid for {MaxFirstWalkerRetirePolls} frames after its deferred destroy request");
                return;
            }

            WaitOneFrame(n"OnFirstWalkerDestroySettled");
            return;
        }

        _FirstWalkerRetiring = false;
        auto SelfHandle = DoGet_ScriptEntity();
        SpawnWalkerInsideOverlap(SelfHandle);
    }

    private void PollInsideOverlapPhase()
    {
        if (ck::Is_NOT_Valid(_InsideWalkerEntity) ||
            ck::Is_NOT_Valid(_InsideWalker))
        {
            FinishFailure(
                "inside-overlap walker became invalid before completing its protected egress");
            return;
        }

        const auto BodyLocation =
            utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(_InsideWalkerEntity));
        _InsideBodyClearance = Compute_PointClearance(BodyLocation);
        auto Body2D = BodyLocation;
        auto Spawn2D = _InsideSpawnLocation;
        Body2D.Z = 0.0;
        Spawn2D.Z = 0.0;
        _InsideDistanceMoved = float((Body2D - Spawn2D).Size());

        if (_InsideInstalledPlanEscaped == false &&
            _InsideRawRouteReady &&
            utils_nav::Get_PathStatus(_InsideWalkerEntity) == ECk_Nav_PathStatus::Ready)
        {
            const auto Result = utils_nav::Get_PathResult(_InsideWalkerEntity);
            const auto Waypoints = Result.Get_Waypoints();
            if (Waypoints.Num() >= 1)
            {
                // Recast retains the projected start as the first protected waypoint. Find the
                // first point that actually exits the expanded markup union, then require that
                // short egress to be lateral and the remaining route never to re-enter.
                auto FirstClearedIndex = -1;
                for (auto Index = 0; Index < Waypoints.Num(); ++Index)
                {
                    if (Compute_PointClearance(Waypoints[Index]) >=
                        ExpandedMarkupRadiusUu)
                    {
                        FirstClearedIndex = Index;
                        break;
                    }
                }

                if (FirstClearedIndex >= 0 &&
                    FirstClearedIndex < Waypoints.Num() - 1)
                {
                    const auto FirstClearedWaypoint =
                        Waypoints[FirstClearedIndex];
                    auto RemainingWaypoints = TArray<FVector>();
                    for (auto Index = FirstClearedIndex + 1;
                         Index < Waypoints.Num();
                         ++Index)
                    {
                        RemainingWaypoints.Add(Waypoints[Index]);
                    }

                    _InsideInstalledClearance = Compute_WorstClearance(
                        RemainingWaypoints,
                        FirstClearedWaypoint);
                    _InsideExitWaypointClearance =
                        Compute_PointClearance(FirstClearedWaypoint);
                    _InsideExitWaypointIsLateralEscape =
                        Math::Abs(FirstClearedWaypoint.Y - InsideSpawnY) <= 60.0;
                    _InsideInstalledPlanEscaped =
                        _InsideInstalledClearance >= InsideRouteMinClearanceUu &&
                        _InsideExitWaypointClearance >= ExpandedMarkupRadiusUu &&
                        _InsideExitWaypointIsLateralEscape &&
                        PathExitsExpandedUnionOnce(
                            Waypoints,
                            FirstClearedIndex);
                }
            }
        }

        if (_InsideInstalledPlanEscaped)
        {
            if (_InsideBodyClearance >= ExpandedMarkupRadiusUu &&
                _InsideDistanceMoved >= MinClearanceUu)
            {
                FinishSuccess();
                return;
            }
        }

        _InsidePlanPolls += 1;
        if (_InsidePlanPolls > MaxInsidePlanPolls)
        {
            FinishFailure(
                f"inside-overlap PathNetwork follower never installed and physically followed an escape after {MaxInsidePlanPolls} polls; raw clearance {_InsideRawClearance}uu, installed clearance {_InsideInstalledClearance}uu (need {InsideRouteMinClearanceUu}uu), exit-waypoint clearance {_InsideExitWaypointClearance}uu, lateral escape {_InsideExitWaypointIsLateralEscape}, body clearance {_InsideBodyClearance}uu, moved {_InsideDistanceMoved}uu (need {ExpandedMarkupRadiusUu}uu expanded-union clearance)");
        }
    }

    UFUNCTION()
    private void OnRouteReady(
        FCk_Handle_PathNetworkFollower InFollower,
        FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        // The first route resolves before pickets are created; its crossing is
        // asserted from the installed path immediately after blocker creation.
        _RouteReady = true;
    }

    UFUNCTION()
    private void OnInsideRouteReady(
        FCk_Handle_PathNetworkFollower InFollower,
        FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        _InsideRawClearance = Compute_WorstClearance(
            InResult.Get_CompiledWaypoints(),
            FVector(0.0, InsideSpawnY, _FloorZ));
        Assert_True(
            _InsideRawClearance < MinClearanceUu,
            f"inside-overlap fixture requires the PathNetwork route itself to remain straight through the picket line; route clearance was {_InsideRawClearance}uu");
        _InsideRawRouteReady = true;
    }

    UFUNCTION()
    private void OnUnexpectedRouteFailed(
        FCk_Handle_PathNetworkFollower InFollower)
    {
        if (IsFinished()) { return; }

        const auto Result =
            utils_path_network_follower::Get_RouteResult(InFollower);
        FinishFailure(
            f"straight fixture route unexpectedly failed: {Result.Get_FailReason()}");
    }

    UFUNCTION()
    private void OnUnexpectedGoalFailed(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        FinishFailure("walker goal failed before a local stationary-markup detour installed");
    }

    private float Compute_WorstClearance(
        const TArray<FVector>& InWaypoints,
        FVector InStart)
    {
        if (InWaypoints.Num() == 0)
        { return -1.0; }

        auto Points = TArray<FVector>();
        Points.Add(InStart);
        for (auto Waypoint : InWaypoints)
        { Points.Add(Waypoint); }

        auto WorstClearance = -1.0;
        for (auto PicketLoc : _PicketLocations)
        {
            auto Closest = -1.0;
            for (auto Index = 1; Index < Points.Num(); ++Index)
            {
                const auto Distance = Dist2D_PointToSegment(
                    PicketLoc,
                    Points[Index - 1],
                    Points[Index]);
                if (Closest < 0.0 || Distance < Closest)
                { Closest = Distance; }
            }
            if (WorstClearance < 0.0 || Closest < WorstClearance)
            { WorstClearance = Closest; }
        }
        return float(WorstClearance);
    }

    private float Compute_PointClearance(FVector InPoint)
    {
        auto WorstClearance = -1.0;
        auto Point = InPoint;
        Point.Z = 0.0;
        for (auto PicketLocation : _PicketLocations)
        {
            auto PicketPoint = PicketLocation;
            PicketPoint.Z = 0.0;
            const auto Clearance = (Point - PicketPoint).Size();
            if (WorstClearance < 0.0 || Clearance < WorstClearance)
            { WorstClearance = Clearance; }
        }
        return float(WorstClearance);
    }

    private bool PathExitsExpandedUnionOnce(
        const TArray<FVector>& InWaypoints,
        int32 InLastWaypointIndex)
    {
        if (InLastWaypointIndex < 0 ||
            InLastWaypointIndex >= InWaypoints.Num())
        { return false; }

        const auto Epsilon = 0.0001;
        const auto RadiusSquared =
            ExpandedMarkupRadiusUu * ExpandedMarkupRadiusUu;
        auto HasExitedUnion = false;
        auto SegmentStart = _InsideSpawnLocation;
        SegmentStart.Z = 0.0;

        for (auto WaypointIndex = 0;
             WaypointIndex <= InLastWaypointIndex;
             ++WaypointIndex)
        {
            auto SegmentEnd = InWaypoints[WaypointIndex];
            SegmentEnd.Z = 0.0;
            const auto Segment = SegmentEnd - SegmentStart;
            const auto SegmentLengthSquared = Segment.SizeSquared();
            auto Breakpoints = TArray<float>();
            Breakpoints.Add(0.0f);
            Breakpoints.Add(1.0f);

            if (SegmentLengthSquared > Epsilon)
            {
                for (auto PicketLocation : _PicketLocations)
                {
                    auto PicketPoint = PicketLocation;
                    PicketPoint.Z = 0.0;
                    const auto FromCenter = SegmentStart - PicketPoint;
                    const auto B = 2.0 * FromCenter.DotProduct(Segment);
                    const auto C =
                        FromCenter.SizeSquared() - RadiusSquared;
                    const auto Discriminant =
                        B * B - 4.0 * SegmentLengthSquared * C;
                    if (Discriminant < 0.0)
                    { continue; }

                    const auto Root =
                        Math::Sqrt(Math::Max(0.0, Discriminant));
                    const auto Denominator =
                        2.0 * SegmentLengthSquared;
                    const auto EnterT =
                        Math::Clamp((-B - Root) / Denominator, 0.0, 1.0);
                    const auto ExitT =
                        Math::Clamp((-B + Root) / Denominator, 0.0, 1.0);
                    if (EnterT <= ExitT)
                    {
                        Breakpoints.Add(float(EnterT));
                        Breakpoints.Add(float(ExitT));
                    }
                }
            }

            // The circle roots partition this segment into regions whose inside-union state is
            // constant. A tiny insertion sort keeps the proof deterministic for this five-disc
            // fixture without relying on an AngelScript comparator delegate.
            for (auto Index = 1; Index < Breakpoints.Num(); ++Index)
            {
                auto Cursor = Index;
                while (Cursor > 0 &&
                       Breakpoints[Cursor] < Breakpoints[Cursor - 1])
                {
                    const auto Temp = Breakpoints[Cursor - 1];
                    Breakpoints[Cursor - 1] = Breakpoints[Cursor];
                    Breakpoints[Cursor] = Temp;
                    --Cursor;
                }
            }

            if (SegmentLengthSquared <= Epsilon)
            {
                const auto Inside =
                    Compute_PointClearance(SegmentStart) <
                    ExpandedMarkupRadiusUu;
                if (Inside && HasExitedUnion) { return false; }
                if (Inside == false) { HasExitedUnion = true; }
            }
            else
            {
                for (auto Index = 1; Index < Breakpoints.Num(); ++Index)
                {
                    const auto IntervalStart = Breakpoints[Index - 1];
                    const auto IntervalEnd = Breakpoints[Index];
                    if (IntervalEnd - IntervalStart <= Epsilon)
                    { continue; }

                    const auto Midpoint = SegmentStart + Segment *
                        ((IntervalStart + IntervalEnd) * 0.5);
                    const auto Inside =
                        Compute_PointClearance(Midpoint) <
                        ExpandedMarkupRadiusUu;
                    if (Inside && HasExitedUnion) { return false; }
                    if (Inside == false) { HasExitedUnion = true; }
                }
            }

            SegmentStart = SegmentEnd;
        }

        return HasExitedUnion;
    }

    private float Dist2D_PointToSegment(
        FVector InPoint,
        FVector InA,
        FVector InB)
    {
        auto Point = InPoint;
        auto A = InA;
        auto B = InB;
        Point.Z = 0.0;
        A.Z = 0.0;
        B.Z = 0.0;

        const auto AB = B - A;
        const auto LengthSquared = AB.SizeSquared();
        if (LengthSquared < 0.0001)
        { return float((Point - A).Size()); }

        auto T = (Point - A).DotProduct(AB) / LengthSquared;
        T = Math::Clamp(T, 0.0, 1.0);
        return float((Point - (A + AB * T)).Size());
    }

    private bool LeavesAndRejoinsRibbon(const TArray<FVector>& InWaypoints)
    {
        auto LeftRibbon = false;
        for (auto Waypoint : InWaypoints)
        {
            if (Math::Abs(Waypoint.Y) >= MinOffRibbonY)
            {
                LeftRibbon = true;
                continue;
            }

            if (LeftRibbon &&
                Math::Abs(Waypoint.Y) <= RibbonHalfWidthUu &&
                Waypoint.X > 100.0)
            {
                return true;
            }
        }
        return false;
    }

    private void SpawnPicketLine(FCk_Handle& InOwner)
    {
        const auto HalfSpan =
            float(PicketCount - 1) * PicketSpacingUu * 0.5;
        for (auto Index = 0; Index < PicketCount; ++Index)
        {
            const auto Location = FVector(
                0.0,
                float(Index) * PicketSpacingUu - HalfSpan,
                _FloorZ + 100.0);
            auto Params =
                FCk_Fragment_CrowdAgent_ParamsData(AgentRadiusUu, 192.0f);
            auto PicketEntity =
                utils_entity_lifetime::Request_CreateEntity(InOwner);
            auto PicketTransform = utils_transform::Add(
                PicketEntity,
                FTransform(
                    FRotator::ZeroRotator,
                    Location,
                    FVector::OneVector),
                ECk_Replication::DoesNotReplicate);
            auto Picket = utils_crowd_agent::Add(
                PicketTransform,
                Params);
            _PicketLocations.Add(Location);
            _Pickets.Add(Picket);
        }
    }

    private void BuildStraightNetwork(FCk_Handle& InOwner)
    {
        auto Points = TArray<FCk_PathNetwork_RibbonPoint>();
        Points.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(-400.0, 0.0, _FloorZ),
                RibbonHalfWidthUu));
        Points.Add(
            FCk_PathNetwork_RibbonPoint(
                FVector(400.0, 0.0, _FloorZ),
                RibbonHalfWidthUu));

        auto Ribbons = TArray<FCk_PathNetwork_Ribbon>();
        Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        _Network = utils_path_network::Add(
            InOwner,
            FCk_Fragment_PathNetwork_ParamsData(Ribbons));
    }

    private void SpawnWalker(FCk_Handle& InOwner)
    {
        _WalkerEntity =
            utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto WalkerTransform = utils_transform::Add(
            _WalkerEntity,
            FTransform(
                FRotator::ZeroRotator,
                FVector(StartX, 0.0, _FloorZ + 100.0),
                FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto AgentParams =
            FCk_Fragment_CrowdAgent_ParamsData(AgentRadiusUu, 192.0f);
        AgentParams.Set_MaxSpeed(60.0f)
                   .Set_BlockedPolicy(
                       ECk_CrowdAgent_BlockedPolicy::FailMove);
        _Walker = utils_crowd_agent::Add(
            WalkerTransform,
            AgentParams);

        utils_velocity::Add(
            _WalkerEntity,
            FCk_Fragment_Velocity_ParamsData(
                ECk_LocalWorld::World,
                FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(
            _WalkerEntity,
            FCk_Fragment_Acceleration_ParamsData(
                ECk_LocalWorld::World,
                FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_WalkerEntity);

        auto FollowerParams =
            FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_SideKeepingFraction(0.0f);
        FollowerParams.Set_CorridorWaypointSpacing(100.0f);
        auto Follower = utils_path_network_follower::Add(
            _WalkerEntity,
            FollowerParams);

        utils_path_network_follower::BindTo_OnRouteReady(
            Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(
                this,
                n"OnRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_path_network_follower::BindTo_OnRouteFailed(
            Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(
                this,
                n"OnUnexpectedRouteFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(
            _Walker,
            FCk_Delegate_CrowdAgent_OnGoalFailed(
                this,
                n"OnUnexpectedGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        _WalkerSpawned = true;
        utils_crowd_agent::Request_MoveTo(
            _Walker,
            FCk_Request_CrowdAgent_MoveTo(
                FVector(GoalX, 0.0, _FloorZ)));
    }

    private void SpawnWalkerInsideOverlap(FCk_Handle& InOwner)
    {
        _InsideSpawnLocation = FVector(0.0, InsideSpawnY, _FloorZ);
        _InsideWalkerEntity =
            utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto WalkerTransform = utils_transform::Add(
            _InsideWalkerEntity,
            FTransform(
                FRotator::ZeroRotator,
                _InsideSpawnLocation + FVector(0.0, 0.0, 100.0),
                FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto AgentParams =
            FCk_Fragment_CrowdAgent_ParamsData(AgentRadiusUu, 192.0f);
        AgentParams.Set_MaxSpeed(120.0f)
                   .Set_BlockedPolicy(
                       ECk_CrowdAgent_BlockedPolicy::HoldAndRetry);
        _InsideWalker = utils_crowd_agent::Add(
            WalkerTransform,
            AgentParams);

        utils_velocity::Add(
            _InsideWalkerEntity,
            FCk_Fragment_Velocity_ParamsData(
                ECk_LocalWorld::World,
                FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(
            _InsideWalkerEntity,
            FCk_Fragment_Acceleration_ParamsData(
                ECk_LocalWorld::World,
                FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_InsideWalkerEntity);

        auto FollowerParams =
            FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_SideKeepingFraction(0.0f);
        FollowerParams.Set_CorridorWaypointSpacing(100.0f);
        auto Follower = utils_path_network_follower::Add(
            _InsideWalkerEntity,
            FollowerParams);

        utils_path_network_follower::BindTo_OnRouteReady(
            Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(
                this,
                n"OnInsideRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_path_network_follower::BindTo_OnRouteFailed(
            Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteFailed(
                this,
                n"OnUnexpectedRouteFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(
            _InsideWalker,
            FCk_Delegate_CrowdAgent_OnGoalFailed(
                this,
                n"OnUnexpectedGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        _InsideWalkerSpawned = true;
        utils_crowd_agent::Request_MoveTo(
            _InsideWalker,
            FCk_Request_CrowdAgent_MoveTo(
                FVector(GoalX, 0.0, _FloorZ)));
    }
}

class ACk_AutoTest_Crowd_PathNetworkStationaryDetour_Actor
    : ACk_AutoTestRunner
{
    default _TestEntityScriptClass =
        UCk_AutoTest_Crowd_PathNetworkStationaryDetour;
    default _TimeoutSeconds = 60.0f;
}
