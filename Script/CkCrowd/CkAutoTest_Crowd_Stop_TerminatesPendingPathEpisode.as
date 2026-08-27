// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: STOP TERMINATES THE PENDING PATH EPISODE
//============================================================================
//
// Regression pin for the orphaned nav-path slot.
//
// All three path providers (VoxelNav / PathNetwork / CkNavigation) park the
// SAME shared FFragment_Nav_PathResult at Pending via MarkPathPending. On the
// PathNetwork and VoxelNav branches no CkNavigation request is ever enqueued,
// so MarkPathPending is that slot's only writer, and the ONLY code that can
// move it off Pending is FProcessor_CrowdAgent_OnRouteResolved - whose gate
// requires the agent to still hold PathPending or Walking.
//
// Request_Stop drops both of those tags. So a Stop landing while a sidewalk
// route is in flight leaves the slot reading Pending for the entity's whole
// life: the route result that lands afterwards is refused by the gate, and
// nothing else ever writes it. Every consumer of Get_PathStatus is then told
// a query is in flight, forever, and the in-world path-trouble overlay draws
// a permanent "UNREAL NAV: Pending" marker over a stopped agent.
//
// Shape: compose a sidewalk follower, MoveTo along it, wait until the slot is
// genuinely parked at Pending, Stop, then let any late route result land. The
// slot must NOT still read Pending.
//
// RED at the time of writing - it is the A/B proof that the defect is real.
//============================================================================

class UCk_AutoTest_Crowd_Stop_TerminatesPendingPathEpisode : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_PathNetwork _Network;

    private const FVector Spawn = FVector(-300.0, 0.0, 0.0);
    private const FVector Goal = FVector(300.0, 0.0, 0.0);
    private const float RibbonHalfWidthUu = 100.0f;

    // The stop is deferred, the abandon it triggers is deferred, and a late
    // corridor result may still be in flight behind both. Settle past all of
    // it so the assertion reads the resting state, not a transient.
    private const int32 SettleFrames = 30;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step(           "compose a sidewalk-following agent and send it down the ribbon",
                            n"Step_Arrange");
        Add_Step_WaitUntil( "the shared nav slot parks at Pending for the sidewalk route",
                            n"Check_SlotIsPending");
        Add_Step(           "stop the agent while that route is still in flight",
                            n"Step_Stop");
        Add_Step_WaitFrames("let the stop drain and any late route result land",
                            SettleFrames);
        Add_Step(           "the episode is terminated, not orphaned at Pending",
                            n"Step_AssertEpisodeTerminated");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        LocalHandle.Set_DebugName(n"StopTerminatesPendingEpisode_Agent");

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto Points = TArray<FCk_PathNetwork_RibbonPoint>();
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-400.0, 0.0, 0.0), RibbonHalfWidthUu));
        Points.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 0.0, 0.0), RibbonHalfWidthUu));
        auto Ribbons = TArray<FCk_PathNetwork_Ribbon>();
        Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        _Network = utils_path_network::Add(
            LocalHandle, FCk_Fragment_PathNetwork_ParamsData(Ribbons));

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

        // Composing the follower is what routes MoveTo down the PathNetwork
        // branch of RequestPathForActiveGoal - the branch that enqueues no
        // CkNavigation request and therefore cannot self-heal the slot.
        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(_Network);
        utils_path_network_follower::Add(LocalHandle, FollowerParams);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void Check_SlotIsPending(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav::Get_PathStatus(_Agent) == ECk_Nav_PathStatus::Pending);
    }

    UFUNCTION()
    private void Step_Stop(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_crowd_agent::Request_Stop(_Agent);
    }

    UFUNCTION()
    private void Step_AssertEpisodeTerminated(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Status = utils_nav::Get_PathStatus(_Agent);

        Assert_True(Status != ECk_Nav_PathStatus::Pending,
            f"a stopped agent must not be left claiming a path query is in flight - the shared nav slot still reads {Status} {SettleFrames} frames after Request_Stop, so every Get_PathStatus consumer is told a query is pending forever");

        Assert_False(utils_nav::Has_Path(_Agent),
            f"a stopped agent must not retain a usable path either (status {Status})");
    }
}
