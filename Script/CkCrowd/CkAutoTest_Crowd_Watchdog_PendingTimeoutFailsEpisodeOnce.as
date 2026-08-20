// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: A NEVER-ANSWERED EPISODE TIMES OUT, ONCE
//============================================================================
//
// Pending had no bound anywhere before this. CkNavigation force-fails its own
// deferral queue at ck.Nav.MaxDeferralSeconds, but that only covers queries
// that reached ITS queue — the PathNetwork and VoxelNav branches never enqueue
// one, and neither module carries a timeout. A provider that simply never
// answered left the agent waiting forever with nothing in the system able to
// report it.
//
// The fixture holds a genuinely un-answerable episode (a navmesh rebuild in
// flight makes the start point unbakeable, so the FindPath defers) and then
// backdates only the CLOCK. The episode, the tags, the revision and the real
// threshold are all production state — nothing about the failure path is faked.
//
// "Once" is half the assertion: the watchdog writes the status and leaves the
// transition to OnPathResolved precisely so the terminal cannot double-fire.
//
// Known narrow race: the state this fixture holds is a DEFERRED CkNavigation
// query, which production independently force-fails with NoNavData at
// ck.Nav.MaxDeferralSeconds (5s) — under the watchdog's 10s threshold. Normal
// margin is a few frames, but a >5s hitch between parking and the watchdog tick
// would let NoNavData win and red the reason assert. It fails loud rather than
// silently asserting the wrong thing. The watchdog's production-relevant
// branches (a sidewalk or voxel provider that never answers) carry no bound of
// their own and cannot be stalled on demand at all — which is precisely why the
// seams exist.
//============================================================================

class UCk_AutoTest_Crowd_Watchdog_PendingTimeoutFailsEpisodeOnce : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle_CrowdAgent _Agent;
    private int32 _GoalFailedCount = 0;

    // Far above any navmesh in the fixture level: the start point cannot be projected, so the
    // FindPath is DEFERRED rather than answered, which is what holds the episode at Pending long
    // enough to be a subject at all. Nothing about the failure path is faked by this.
    private const FVector Spawn = FVector(0.0, 0.0, 100000.0);
    private const FVector Goal = FVector(300.0, 0.0, 0.0);

    // Comfortably past the 10s default without depending on its exact value.
    private const float AgeBySeconds = 30.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step(           "dispatch an episode that cannot be answered yet", n"Step_Arrange");
        Add_Step_WaitUntil( "the episode is genuinely parked at Pending",      n"Check_SlotIsPending");
        Add_Step(           "backdate only its clock past the threshold",      n"Step_AgePastTimeout");
        Add_Step_WaitFrames("let the watchdog and the transition run",         30);
        Add_Step(           "the stall is reported as a bounded failure, exactly once",
                            n"Step_AssertFailedOnce");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        LocalHandle.Set_DebugName(n"WatchdogTimeout_Agent");

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

        utils_crowd_agent::BindTo_OnGoalFailed(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void Check_SlotIsPending(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav::Get_PathStatus(_Agent) == ECk_Nav_PathStatus::Pending);
    }

    UFUNCTION()
    private void Step_AgePastTimeout(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto AgentGeneric = FCk_Handle(_Agent);
        utils_nav::Request_AgePathPending_ForTesting(AgentGeneric, AgeBySeconds);
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        _GoalFailedCount += 1;
    }

    UFUNCTION()
    private void Step_AssertFailedOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Status = utils_nav::Get_PathStatus(_Agent);
        Assert_True(Status == ECk_Nav_PathStatus::Failed,
            f"an episode no provider answered must end as a reportable failure, not stay Pending — slot reads {Status}");

        const auto Reason = utils_nav::Get_PathResult(_Agent).Get_Diagnostics().Get_LastFailReason();
        Assert_True(Reason == ECk_Nav_PathFailReason::PendingTimeout,
            f"the failure must name the timeout as its cause, not inherit an unrelated reason — got {Reason}");

        Assert_True(_GoalFailedCount == 1,
            f"the terminal must reach the caller exactly once — OnGoalFailed fired {_GoalFailedCount} times (0 = reported to nobody, >1 = the watchdog duplicated a transition OnPathResolved already owns)");
    }
}

class ACk_AutoTest_Crowd_Watchdog_PendingTimeoutFailsEpisodeOnce_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 25.0f;
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Watchdog_PendingTimeoutFailsEpisodeOnce;

    // Both warnings ARE the behaviour under test: the watchdog naming the stalled provider, and
    // the transition reporting the bounded failure. Declare them rather than let the harness
    // auto-fail on the test's own deliberate output. Plain substring match, not regex.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("never answered");
        Out.Add("path failed: Pending Timeout");
        return Out;
    }
}
