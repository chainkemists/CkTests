// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: STOP CANCELS A QUEUED NAV QUERY
//============================================================================
//
// The CkNavigation branch differs from the sidewalk/voxel ones: its processor
// writes the result slot independently of the crowd's tags, so a stopped agent
// there does not strand at Pending — it strands at a stale Ready instead, for
// a goal it has abandoned.
//
// Releasing the episode therefore has to do two things the Stop handler alone
// never did: drop the request that is still QUEUED (or it drains next tick and
// re-answers an episode nobody owns) and advance the revision (so anything
// already in the deferral queue is recognised as superseded when it lands).
//
// The fixture makes that deterministic instead of racy: MoveTo and Stop are
// issued in the SAME batch, so they drain in one pass — the dispatch enqueues
// a FindPath and the release must cancel it before the nav processor ever sees
// it. If the release does not, the slot comes back Ready and this reds.
//============================================================================

class UCk_AutoTest_Crowd_Stop_CancelsQueuedNavQuery : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle_CrowdAgent _Agent;
    private bool _MoveToAccepted = false;

    private const FVector Spawn = FVector(0.0, 0.0, 0.0);
    private const FVector Goal = FVector(300.0, 0.0, 0.0);

    // Long enough for a queued FindPath to have drained several times over had
    // the release failed to cancel it.
    private const int32 SettleFrames = 40;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step(           "dispatch and release a CkNavigation episode in one batch",
                            n"Step_MoveThenStop");
        Add_Step_WaitFrames("let any surviving query drain",
                            SettleFrames);
        Add_Step(           "the released episode was cancelled, not answered",
                            n"Step_AssertNoAnswer");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_MoveThenStop(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        LocalHandle.Set_DebugName(n"StopCancelsQueuedNavQuery_Agent");
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

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

        // No PathNetworkFollower and no VoxelNavPath, so this takes the
        // CkNavigation branch of RequestPathForActiveGoal.
        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal),
            FCk_Delegate_Request_OnCompleted(this, n"OnMoveToCompleted"));
        utils_crowd_agent::Request_Stop(_Agent);
    }

    UFUNCTION()
    private void OnMoveToCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _MoveToAccepted = InResult == ECk_Request_OperationResult::Succeeded;
    }

    UFUNCTION()
    private void Step_AssertNoAnswer(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Without this the test would pass vacuously if the MoveTo never dispatched at all: a
        // slot that was never parked also reads None.
        Assert_True(_MoveToAccepted,
            "the MoveTo must actually have been accepted and dispatched, or there was no queued query for the release to cancel and this test proves nothing");

        const auto Status = utils_nav::Get_PathStatus(_Agent);

        Assert_True(Status == ECk_Nav_PathStatus::None,
            f"a released episode must leave no answer behind — the slot reads {Status}, so the query the release should have cancelled was drained and answered for a goal the agent already abandoned");

        Assert_False(utils_nav::Has_Path(_Agent),
            "a released episode must not leave a usable path behind");
    }
}
