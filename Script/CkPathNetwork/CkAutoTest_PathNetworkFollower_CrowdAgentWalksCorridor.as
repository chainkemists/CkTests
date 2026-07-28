// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: CROWD AGENT WALKS A CORRIDOR
//============================================================================
//
// Full-stack integration of the CkCrowd seam: a crowd agent that carries the
// PathNetworkFollower feature routes its MoveTo THROUGH the network (the
// HandleRequests branch), the corridor installs via
// FCk_Nav_Algorithm::InstallExternalPath (the OnRouteResolved bridge), and
// the unchanged steering machinery walks the compiled waypoints to arrival.
//
//   network:  (100,0) ──► (450,0)      agent (0,0,0)   goal (480,0,0)
//
//   1. Compose a full crowd agent (transform/velocity/accel/integrator) as
//      a child of the test entity, plus the follower feature.
//   2. MoveTo (480,0,0). OnRouteReady must fire (proves the MoveTo was
//      routed through the network, not CkNavigation).
//   3. OnGoalReached must fire (proves the corridor was installed and the
//      steering machinery consumed it) with the agent's transform near the
//      goal.
//
// Geometry sits inside the AutoTests level's baked navmesh (±500cm) so the
// plan-time ramps validate honestly. Walking itself needs no navmesh.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_CrowdAgentWalksCorridor : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_PathNetwork _Network;
    private FCk_Handle_PathNetworkFollower _Follower;
    private FCk_Handle_CrowdAgent _Agent;
    private bool _RouteBecameReady = false;
    private const FVector Goal = FVector(480.0, 0.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto AgentTransform = utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        // The sidewalk: a straight ribbon just off the agent's spawn, ending just short of the goal.
        TArray<FCk_PathNetwork_RibbonPoint> Points;
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(100.0, 0.0, 0.0), 100.0));
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(450.0, 0.0, 0.0), 100.0));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(Points));

        _Network = utils_path_network::Add(LocalHandle, FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        // Full crowd-agent composition — this entity IS the agent (mirrors the CkCrowd tests).
        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, AgentParams);
        utils_velocity::Add(LocalHandle,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(LocalHandle,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(LocalHandle);

        // Opt the AGENT into network following — this is the activation switch the
        // MoveTo branch keys on.
        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        FollowerParams.Set_CorridorWaypointSpacing(100.0);
        _Follower = utils_path_network_follower::Add(LocalHandle, FollowerParams);

        utils_path_network_follower::BindTo_OnRouteReady(_Follower,
            FCk_Delegate_PathNetworkFollower_OnRouteReady(this, n"OnRouteReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalReached(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalFailed(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnUnexpectedGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Let the network build before the MoveTo's FindRoute drains against it.
        WaitOneFrame(n"OnReadyToMove");
    }

    UFUNCTION()
    private void OnReadyToMove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_path_network::Get_IsBuilt(_Network),
            "network must be built before the MoveTo");

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void OnRouteReady(FCk_Handle_PathNetworkFollower InFollower, FCk_PathNetwork_RouteResult InResult)
    {
        if (IsFinished()) { return; }

        // Fires ONLY when the MoveTo was routed through the network — plain CkNavigation
        // paths never touch the follower corridor.
        _RouteBecameReady = true;

        Assert_True(InResult.Get_CompiledWaypoints().Num() >= 3,
            f"corridor along the ribbon with 100cm spacing should compile >= 3 waypoints, got {InResult.Get_CompiledWaypoints().Num()}");

        // A route is only safe to install into the ordinary crowd navigator if every compiled
        // waypoint is already on the baked navmesh. This catches a corridor compiler emitting
        // a visually plausible point in empty space, before steering can walk it.
        const auto Waypoints = InResult.Get_CompiledWaypoints();
        for (int32 i = 0; i < Waypoints.Num(); ++i)
        {
            FVector ProjectedWaypoint;
            const auto ProjectsToNavmesh = utils_nav::Try_ProjectOntoNavmesh(
                FCk_Handle(InFollower), Waypoints[i], 25.0f, ProjectedWaypoint, 300.0f);
            Assert_True(ProjectsToNavmesh,
                f"compiled waypoint {i} must project onto the AutoTests navmesh: {Waypoints[i]}");
            if (!ProjectsToNavmesh) { return; }

            Assert_True((ProjectedWaypoint - Waypoints[i]).Size() <= 2.0f,
                f"compiled waypoint {i} must already lie on navmesh (projection delta {(ProjectedWaypoint - Waypoints[i]).Size()}cm): {Waypoints[i]}");
        }
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }

        Assert_True(_RouteBecameReady,
            "OnGoalReached fired but OnRouteReady never did — the MoveTo bypassed the path network");

        const auto AgentLocation = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Agent)));

        Assert_True((AgentLocation - Goal).Size() <= 100.0,
            f"agent should arrive near the goal; final location {AgentLocation}");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedGoalFailed(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_path_network_follower::Get_RouteResult(_Follower);
        FinishFailure(f"agent goal unexpectedly failed (route status {Result.Get_Status()}, fail reason {Result.Get_FailReason()})");
    }
}
