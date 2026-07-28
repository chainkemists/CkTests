// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: PATH-NETWORK ROUTE LOCALLY DETOURS A STATIONARY LINE
//
// A PathNetwork is a route preference, not a movement boundary. Stationary-agent
// markup must therefore be allowed to bend the installed CrowdAgent path outside
// a sidewalk ribbon, after which the path rejoins the remaining corridor.
//
// The fixture also forces the async paint-to-confirm ordering that occurs in live
// play:
//
//  1. Wait until every picket has painted but NONE is confirmed on the navmesh.
//  2. Install the follower's straight route through the still-unconfirmed line.
//  3. Wait for confirmation, prove plain Recast detours, then require the already
//     walking PathNetwork agent to refresh, leave the ribbon, and rejoin it.
//
// Red behavior includes stamping the pre-confirmation route as though it had seen
// the painted areas; confirmation then never invalidates that straight path.
//============================================================================

class UCk_AutoTest_Crowd_PathNetworkStationaryDetour : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private const float StartX = -450.0;
    private const float GoalX = 450.0;
    private const int32 PicketCount = 5;
    private const float PicketSpacingUu = 100.0;
    private const float MinClearanceUu = 50.0;
    private const float RibbonHalfWidthUu = 100.0;
    private const float MinOffRibbonY = 150.0;
    private const int32 MaxInstalledPathPolls = 100;

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
            SpawnPicketLine(SelfHandle);
            BuildStraightNetwork(SelfHandle);
            return;
        }

        if (utils_path_network::Get_IsBuilt(_Network) == false)
        { return; }

        if (_WalkerSpawned == false)
        {
            auto AnyConfirmed = false;
            for (auto Picket : _Pickets)
            {
                if (utils_crowd_agent::Get_IsStationaryMarkupPainted(Picket) == false)
                { return; }
                AnyConfirmed =
                    AnyConfirmed ||
                    utils_crowd_agent::Get_IsStationaryMarkupConfirmed(Picket);
            }

            if (AnyConfirmed)
            {
                FinishFailure(
                    "fixture missed the painted-but-unconfirmed window before spawning the walker");
                return;
            }

            SpawnWalker(SelfHandle);
            return;
        }

        if (_SawPreConfirmationStraightInstall == false)
        {
            for (auto Picket : _Pickets)
            {
                if (utils_crowd_agent::Get_IsStationaryMarkupConfirmed(Picket))
                {
                    FinishFailure(
                        "fixture did not install the initial sidewalk route before markup confirmation");
                    return;
                }
            }

            if (_RouteReady == false ||
                utils_nav::Get_PathStatus(_WalkerEntity) != ECk_Nav_PathStatus::Ready)
            { return; }

            const auto InitialResult = utils_nav::Get_PathResult(_WalkerEntity);
            const auto InitialClearance = Compute_WorstClearance(
                InitialResult.Get_Waypoints(),
                FVector(StartX, 0.0, _FloorZ));
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
                FinishSuccess();
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

    UFUNCTION()
    private void OnRouteReady(
        FCk_Handle_PathNetworkFollower InFollower,
        FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        _RouteClearance = Compute_WorstClearance(
            InResult.Get_CompiledWaypoints(),
            FVector(StartX, 0.0, _FloorZ));
        Assert_True(
            _RouteClearance < MinClearanceUu,
            f"fixture requires the preferred sidewalk corridor itself to cross the picket line; " +
            f"route clearance was {_RouteClearance}uu");
        _RouteReady = true;
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
                FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
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
            FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
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
}

class ACk_AutoTest_Crowd_PathNetworkStationaryDetour_Actor
    : ACk_AutoTestRunner
{
    default _TestEntityScriptClass =
        UCk_AutoTest_Crowd_PathNetworkStationaryDetour;
    default _TimeoutSeconds = 25.0f;
}
