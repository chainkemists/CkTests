// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: STOP RELEASES THE SIDEWALK ROUTE TOO
//============================================================================
//
// The shared nav slot is only half of what an episode acquires. Every provider
// exposes a way to START a query (Request_FindRoute / Request_FindPath) and,
// before this fix, none exposed a way to END one — so a stopped agent left the
// follower still holding a Pending corridor and still computing a route that
// nothing would ever consume.
//
// The sibling of Stop_TerminatesPendingPathEpisode: that one pins the shared
// nav slot, this one pins the PROVIDER's own result. Both must be released by
// the same single episode-end seam, or the fix is only half applied.
//============================================================================

class UCk_AutoTest_Crowd_Stop_ReleasesSidewalkRoute : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_PathNetworkFollower _Follower;
    private FCk_Handle_PathNetwork _Network;

    private const FVector Spawn = FVector(-300.0, 0.0, 0.0);
    private const FVector Goal = FVector(300.0, 0.0, 0.0);
    private const int32 SettleFrames = 30;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step(           "compose a sidewalk-following agent and route it", n"Step_Arrange");
        Add_Step_WaitUntil( "the follower owns a route episode",               n"Check_RouteEpisodeExists");
        Add_Step(           "stop the agent mid-route",                        n"Step_Stop");
        Add_Step_WaitFrames("let the release drain",                           SettleFrames);
        Add_Step(           "the follower's own route is released, not just the nav slot",
                            n"Step_AssertRouteReleased");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        LocalHandle.Set_DebugName(n"StopReleasesSidewalkRoute_Agent");
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto Points = TArray<FCk_PathNetwork_RibbonPoint>();
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-400.0, 0.0, 0.0), 100.0));
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 0.0, 0.0), 100.0));
        auto Ribbons = TArray<FCk_PathNetwork_Ribbon>();
        Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        _Network = utils_path_network::Add(LocalHandle, FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        auto AgentTransform = utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        AgentParams.Set_MaxSpeed(60.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, AgentParams);

        utils_velocity::Add(LocalHandle,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(LocalHandle,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(LocalHandle);

        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        _Follower = utils_path_network_follower::Add(LocalHandle, FollowerParams);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    // Pending is not reliably observable: the follower can drain its request in the same frame
    // the crowd dispatched it, so the corridor may go straight to Ready. Either state means an
    // episode exists, which is all this test needs before stopping it.
    UFUNCTION()
    private void Check_RouteEpisodeExists(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto Status = utils_path_network_follower::Get_RouteResult(_Follower).Get_Status();
        auto Res = OutResult;
        Res.Set(Status == ECk_PathNetwork_RouteStatus::Pending
             || Status == ECk_PathNetwork_RouteStatus::Ready);
    }

    UFUNCTION()
    private void Step_Stop(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_crowd_agent::Request_Stop(_Agent);
    }

    UFUNCTION()
    private void Step_AssertRouteReleased(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto RouteStatus = utils_path_network_follower::Get_RouteResult(_Follower).Get_Status();
        Assert_True(RouteStatus == ECk_PathNetwork_RouteStatus::None,
            f"stopping the agent must RELEASE the sidewalk route it acquired, not only the shared nav slot — the follower still reports {RouteStatus}");
    }
}
