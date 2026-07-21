// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: RE-TARGET TAKES THE FRESH PATH (stale-result race)
//============================================================================
//
// Regression pin for the stale-path-install race: a MoveTo issued while the
// PREVIOUS move's FFragment_Nav_PathResult is still Ready must NOT consume
// that stale result as its own answer.
//
// FProcessor_CrowdAgent_OnPathResolved deliberately runs after HandleRequests
// (same frame, explicit RunAfter). Without HandleRequests parking the nav slot
// at Pending before enqueueing the new FindPath (FCk_Nav_Algorithm::
// MarkPathPending — the guard the follower branch always had), OnPathResolved
// sees PathPending + the old Ready result and installs the OLD corridor: the
// agent walks back to the PREVIOUS goal, "arrives", and the fresh result is
// never consumed (the agent is no longer PathPending).
//
// Shape: walk to goal A, arrive, then re-target to goal B on the opposite
// side. With the race, the agent re-installs the A-corridor, instantly
// re-arrives at A, and never walks to B — OnGoalReached fires with the agent
// standing at A. The assertion is therefore POSITIONAL: on the second arrival
// the agent must stand near B, not near A.
//============================================================================

class UCk_AutoTest_Crowd_MoveTo_RetargetTakesFreshPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle_CrowdAgent _Agent;

    private const FVector Spawn = FVector(0.0, 0.0, 0.0);
    private const FVector GoalA = FVector(300.0, 0.0, 0.0);
    private const FVector GoalB = FVector(-300.0, 0.0, 0.0);

    // Generous: arrival radius (30) + body + a settle drift margin.
    private const float NearDistanceCm = 150.0;

    private bool _ReachedA = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // This entity IS the agent.
        LocalHandle.Set_DebugName(n"RetargetFreshPath_Agent");
        auto AgentTransform = utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(LocalHandle,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(LocalHandle,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(LocalHandle);

        utils_crowd_agent::BindTo_OnGoalReached(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(GoalA));
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        const auto Pos = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Agent)));

        if (_ReachedA == false)
        {
            _ReachedA = true;

            const auto DistToA = float((Pos - GoalA).Size2D());
            Assert_True(DistToA <= NearDistanceCm,
                f"first arrival is at goal A ({DistToA}cm away)");

            // THE MOMENT UNDER TEST: re-target while the previous move's path
            // result is still Ready on the entity.
            utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(GoalB));
            return;
        }

        // Second arrival: with the stale-result race, the agent "re-arrives" on the
        // old A-corridor while standing at A — 600cm from B.
        const auto DistToB = float((Pos - GoalB).Size2D());
        Assert_True(DistToB <= NearDistanceCm,
            f"STALE PATH: second arrival must be at goal B, but the agent stands {DistToB}cm from B — the re-target consumed the previous move's Ready path and walked the OLD corridor.");

        FinishSuccess();
    }
}

class ACk_AutoTest_Crowd_MoveTo_RetargetTakesFreshPath_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_MoveTo_RetargetTakesFreshPath;
    default _TimeoutSeconds = 20.0f;
}
