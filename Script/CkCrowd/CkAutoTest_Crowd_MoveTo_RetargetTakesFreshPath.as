// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: RE-TARGET TAKES THE FRESH PATH (stale-result race)
//============================================================================
//
// Regression pin for the stale-path-install race: a MoveTo issued while the
// PREVIOUS move's FFragment_Nav_PathResult is still Ready must NOT consume
// that stale result as its own answer.
//
// FProcessor_CrowdAgent_OnPathResolved deliberately runs after HandleRequests
// (same frame, explicit RunAfter). Without HandleRequests parking the nav slot
// at Pending before enqueueing the new FindPath (FCk_Nav_Algorithm::
// MarkPathPending - the guard the follower branch always had), OnPathResolved
// sees PathPending + the old Ready result and installs the OLD corridor: the
// agent walks back to the PREVIOUS goal, "arrives", and the fresh result is
// never consumed (the agent is no longer PathPending).
//
// Shape: walk to goal A, arrive, then re-target to goal B on the opposite
// side. With the race, the agent re-installs the A-corridor, instantly
// re-arrives at A, and never walks to B - OnGoalReached fires with the agent
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
    private const int32 ClaimedGoalACorrelation = 202;
    private const int32 GoalBCorrelation = 303;

    // Generous: arrival radius (30) + body + a settle drift margin.
    private const float NearDistanceCm = 150.0;

    private bool _ReachedA = false;
    private bool _SameGoalReissueQueued = false;
    private bool _SameGoalNoOpVerified = false;
    private int32 _EpisodeA = 0;
    private int32 _EpisodeBeforeB = 0;

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

        Assert_False(utils_crowd_agent::Get_HasReachedActiveGoal(_Agent),
            "fresh agent has no retained successful goal completion");
        Assert_True(utils_crowd_agent::Get_ActiveMoveEpisode(_Agent) == 0,
            "fresh agent has no accepted MoveTo episode");
        Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(_Agent) == 0,
            "fresh agent has no accepted MoveTo correlation");

        // Both requests land before HandleRequests drains its snapshot. The second
        // caller explicitly claims the same coordinates with a different identity,
        // so it must own a fresh episode rather than inheriting the first request.
        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(GoalA));
        auto ClaimedGoalA = FCk_Request_CrowdAgent_MoveTo(GoalA);
        ClaimedGoalA.Set_CorrelationId(ClaimedGoalACorrelation);
        utils_crowd_agent::Request_MoveTo(_Agent, ClaimedGoalA);
        Assert_False(utils_crowd_agent::Get_HasReachedActiveGoal(_Agent),
            "queued MoveTo invalidates any retained completion before request drain");

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.01));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPollWalking"));
    }

    UFUNCTION()
    private void OnPollWalking(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished() || _SameGoalReissueQueued ||
            utils_crowd_agent::Get_MovementState(_Agent) != ECk_CrowdAgent_MovementState::Walking)
        { return; }

        _EpisodeA = utils_crowd_agent::Get_ActiveMoveEpisode(_Agent);
        Assert_True(_EpisodeA > 0,
            "accepted goal A movement has a nonzero episode");
        Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(_Agent) == ClaimedGoalACorrelation,
            "later queued same-goal claimant owns the accepted movement episode");
        _SameGoalReissueQueued = true;
        // Legacy/default callers must never steal or restart a correlated same-goal walk.
        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(GoalA));
        auto SameClaim = FCk_Request_CrowdAgent_MoveTo(GoalA);
        SameClaim.Set_CorrelationId(ClaimedGoalACorrelation);
        utils_crowd_agent::Request_MoveTo(
            _Agent, SameClaim,
            FCk_Delegate_Request_OnCompleted(this, n"OnSameGoalReissueCompleted"));
    }

    UFUNCTION()
    private void OnSameGoalReissueCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"same-goal request must drain successfully (got {InResult})");
        Assert_True(InRequestOwner == FCk_Handle(_Agent),
            "same-goal completion reports the CrowdAgent request owner");
        Assert_True(utils_crowd_agent::Get_ActiveMoveEpisode(_Agent) == _EpisodeA,
            "default and same-correlation reissues do not claim a fresh movement episode");
        Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(_Agent) == ClaimedGoalACorrelation,
            "default and same-correlation reissues retain the accepted caller correlation");
        _SameGoalNoOpVerified = true;
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

            Assert_True(utils_crowd_agent::Get_HasReachedActiveGoal(InAgent),
                "goal A callback observes retained successful completion");
            Assert_True(_SameGoalNoOpVerified,
                "same-goal no-op was verified before goal A completed");
            Assert_True(utils_crowd_agent::Get_ActiveMoveEpisode(InAgent) == _EpisodeA,
                "goal A callback retains the accepted episode, not the ignored reissue");
            Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(InAgent) == ClaimedGoalACorrelation,
                "goal A callback belongs to the later queued same-goal claimant");

            const auto DistToA = float((Pos - GoalA).Size2D());
            Assert_True(DistToA <= NearDistanceCm,
                f"first arrival is at goal A ({DistToA}cm away)");

            // THE MOMENT UNDER TEST: re-target while the previous move's path
            // result is still Ready on the entity.
            _EpisodeBeforeB = utils_crowd_agent::Get_ActiveMoveEpisode(_Agent);
            auto MoveB = FCk_Request_CrowdAgent_MoveTo(GoalB);
            MoveB.Set_CorrelationId(GoalBCorrelation);
            utils_crowd_agent::Request_MoveTo(_Agent, MoveB);
            Assert_False(utils_crowd_agent::Get_HasReachedActiveGoal(_Agent),
                "queued retarget hides the stale goal A completion immediately");
            return;
        }

        // Second arrival: with the stale-result race, the agent "re-arrives" on the
        // old A-corridor while standing at A - 600cm from B.
        const auto DistToB = float((Pos - GoalB).Size2D());
        Assert_True(DistToB <= NearDistanceCm,
            f"STALE PATH: second arrival must be at goal B, but the agent stands {DistToB}cm from B - the re-target consumed the previous move's Ready path and walked the OLD corridor.");
        Assert_True(utils_crowd_agent::Get_HasReachedActiveGoal(InAgent),
            "goal B callback observes retained successful completion");
        Assert_True(utils_crowd_agent::Get_ActiveMoveEpisode(InAgent) > _EpisodeBeforeB,
            "accepted goal B retarget owns a fresh movement episode");
        Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(InAgent) == GoalBCorrelation,
            "goal B callback retains its caller correlation");

        utils_crowd_agent::Request_Stop(_Agent,
            FCk_Delegate_Request_OnCompleted(this, n"OnStopCompleted"));
        Assert_False(utils_crowd_agent::Get_HasReachedActiveGoal(_Agent),
            "queued Stop hides the retained goal B completion immediately");
    }

    UFUNCTION()
    private void OnStopCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"Stop must complete successfully (got {InResult})");
        Assert_True(InRequestOwner == FCk_Handle(_Agent),
            "Stop completion reports the CrowdAgent request owner");
        Assert_False(utils_crowd_agent::Get_HasReachedActiveGoal(_Agent),
            "drained Stop clears the retained successful completion");
        Assert_True(utils_crowd_agent::Get_ActiveMoveEpisode(_Agent) > _EpisodeBeforeB,
            "Stop leaves the last accepted MoveTo episode identity intact");
        Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(_Agent) == GoalBCorrelation,
            "Stop leaves the last accepted MoveTo correlation intact");

        FinishSuccess();
    }
}

class ACk_AutoTest_Crowd_MoveTo_RetargetTakesFreshPath_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_MoveTo_RetargetTakesFreshPath;
    default _TimeoutSeconds = 20.0f;
}
