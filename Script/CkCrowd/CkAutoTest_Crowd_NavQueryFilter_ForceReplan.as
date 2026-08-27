// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: NAV-QUERY POLICY FORCE-REPLAN
//============================================================================
//
// A policy-only SetNavQueryFilter must replace the active navigation request,
// without replacing the movement episode that owns its goal, arrival radius,
// or caller correlation. The nav result's request revision is the observable
// ownership token: each replacement must advance it, and a prior result must
// never become the installed Ready result after a newer revision is active.
//
// The final phase queues SetNavQueryFilter + MoveTo in one request batch. The
// policy prepass must apply before dispatching MoveTo, but ForceReplan must not
// also start a redundant route: the result revision advances exactly once.
//============================================================================

class UCk_AutoTest_Crowd_NavQueryFilter_ForceReplan : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle_CrowdAgent _Agent;

    private const FVector Spawn = FVector(0.0, 0.0, 0.0);
    private const FVector GoalA = FVector(900.0, 0.0, 0.0);
    private const FVector GoalB = FVector(-700.0, 0.0, 0.0);
    private const int32 CorrelationA = 6101;
    private const int32 CorrelationB = 6102;
    private const float32 ArrivalA = 61.0f;
    private const float32 ArrivalB = 73.0f;
    private const float ArrivalTolerance = 110.0f;

    private int32 _EpisodeA = 0;
    private int32 _RouteRevisionA = 0;
    private int32 _RouteRevisionAfterForce = 0;
    private int32 _PollsAwaitingReplacement = 0;
    private bool _ForceReplanQueued = false;
    private bool _SameBatchQueued = false;
    private FGameplayTag _InitialPolicy;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        LocalHandle.Set_DebugName(n"NavQueryFilterForceReplan_Agent");

        auto AgentTransform = utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        _InitialPolicy = utils_gameplay_tag::ResolveGameplayTag(n"Nav.Filter.Customer");
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        Params.Set_NavQueryFilter(_InitialPolicy);
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
        utils_crowd_agent::BindTo_OnGoalFailed(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnUnexpectedGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalBlocked(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalBlocked(this, n"OnUnexpectedGoalBlocked"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        auto MoveA = FCk_Request_CrowdAgent_MoveTo(GoalA);
        MoveA.Set_ArrivalRadiusOverrideMode(ECk_Override::Override)
             .Set_ArrivalRadiusOverrideValue(ArrivalA)
             .Set_CorrelationId(CorrelationA);
        utils_crowd_agent::Request_MoveTo(_Agent, MoveA);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.02));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const auto Status = utils_nav::Get_PathStatus(_Agent);
        if (Status == ECk_Nav_PathStatus::Failed
            || Status == ECk_Nav_PathStatus::Partial)
        {
            FinishFailure(f"force-replan route returned unexpected terminal nav status {Status}");
            return;
        }
        if (Status != ECk_Nav_PathStatus::Ready)
        { return; }

        const auto Result = utils_nav::Get_PathResult(_Agent);
        const auto Revision = Result.Get_RequestRevision();
        if (Revision <= 0)
        {
            FinishFailure(f"CkNavigation returned Ready without a nonzero request revision ({Revision}); policy replan results cannot reject stale completions without that ownership token.");
            return;
        }

        if (_ForceReplanQueued == false)
        {
            _ForceReplanQueued = true;
            _EpisodeA = utils_crowd_agent::Get_ActiveMoveEpisode(_Agent);
            _RouteRevisionA = Revision;

            Assert_True(_EpisodeA > 0, "initial MoveTo accepted a nonzero movement episode");
            Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(_Agent) == CorrelationA,
                "initial route retains its caller correlation");
            Assert_True(utils_crowd_agent::Get_ActiveGoal(_Agent).Equals(GoalA, 1.0f),
                "initial route owns goal A before policy replacement");
            Assert_True(utils_crowd_agent::Get_NavQueryFilter(_Agent) == _InitialPolicy,
                "initial route exposes the configured non-default policy");

            // Empty is a valid framework-independent policy: it resolves to the
            // default nav query filter, while still exercising the public policy
            // request/replan contract without any BusterBlock tag mapping.
            auto Policy = FCk_Request_CrowdAgent_SetNavQueryFilter(FGameplayTag());
            Policy.Set_ForceReplan(ECk_EnableDisable::Enable);
            utils_crowd_agent::Request_SetNavQueryFilter(_Agent, Policy);
            _PollsAwaitingReplacement = 0;
            return;
        }

        if (_SameBatchQueued == false)
        {
            if (Revision == _RouteRevisionA)
            {
                _PollsAwaitingReplacement += 1;
                if (_PollsAwaitingReplacement > 250)
                {
                    FinishFailure(f"STALE RESULT INSTALLED: policy ForceReplan never replaced Ready revision {_RouteRevisionA}; a prior result remained installable after the newer policy request.");
                }
                return;
            }

            _RouteRevisionAfterForce = Revision;
            Assert_True(Revision == _RouteRevisionA + 1,
                f"policy-only ForceReplan advances navigation revision once (old={_RouteRevisionA}, new={Revision})");
            Assert_True(utils_crowd_agent::Get_ActiveMoveEpisode(_Agent) == _EpisodeA,
                "policy-only ForceReplan preserves the active movement episode");
            Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(_Agent) == CorrelationA,
                "policy-only ForceReplan preserves caller correlation");
            Assert_True(utils_crowd_agent::Get_ActiveGoal(_Agent).Equals(GoalA, 1.0f),
                "policy-only ForceReplan preserves active goal");
            Assert_True(utils_crowd_agent::Get_NavQueryFilter(_Agent) == FGameplayTag(),
                "policy-only ForceReplan applied the requested policy before installing its route");

            _SameBatchQueued = true;
            auto Policy = FCk_Request_CrowdAgent_SetNavQueryFilter(FGameplayTag());
            Policy.Set_ForceReplan(ECk_EnableDisable::Enable);
            utils_crowd_agent::Request_SetNavQueryFilter(_Agent, Policy);

            auto MoveB = FCk_Request_CrowdAgent_MoveTo(GoalB);
            MoveB.Set_ArrivalRadiusOverrideMode(ECk_Override::Override)
                 .Set_ArrivalRadiusOverrideValue(ArrivalB)
                 .Set_CorrelationId(CorrelationB);
            utils_crowd_agent::Request_MoveTo(_Agent, MoveB);
            _PollsAwaitingReplacement = 0;
            return;
        }

        if (Revision == _RouteRevisionAfterForce)
        {
            _PollsAwaitingReplacement += 1;
            if (_PollsAwaitingReplacement > 250)
            {
                FinishFailure(f"STALE RESULT INSTALLED: same-batch policy + MoveTo never replaced revision {_RouteRevisionAfterForce}; the new movement episode has no installed route.");
            }
            return;
        }

        // One batch containing SetPolicy + MoveTo is one dispatch. A sequential
        // policy replan followed by MoveTo would advance twice and allow an old
        // result to race the new episode; the prepass makes the result revision
        // exactly the next one and the returned route belongs to B.
        Assert_True(Revision == _RouteRevisionAfterForce + 1,
            f"same-batch SetPolicy + MoveTo dispatches exactly one new navigation request (afterForce={_RouteRevisionAfterForce}, installed={Revision})");
        Assert_True(utils_crowd_agent::Get_ActiveMoveEpisode(_Agent) == _EpisodeA + 1,
            "same-batch MoveTo claims exactly one fresh movement episode");
        Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(_Agent) == CorrelationB,
            "same-batch MoveTo retains its caller correlation");
        Assert_True(utils_crowd_agent::Get_ActiveGoal(_Agent).Equals(GoalB, 1.0f),
            "installed post-policy route belongs to goal B, not stale goal A");
        Assert_True(utils_crowd_agent::Get_NavQueryFilter(_Agent) == FGameplayTag(),
            "same-batch route retained the requested policy");
    }

    UFUNCTION()
    private void OnGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        if (_SameBatchQueued == false)
        {
            FinishFailure("agent reached goal A before the force-replan and same-batch policy scenario completed");
            return;
        }

        const auto Pos = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Agent)));
        const auto DistToB = float((Pos - GoalB).Size2D());
        Assert_True(DistToB <= ArrivalTolerance,
            f"final arrival respects the second MoveTo's arrival contract (distance={DistToB}, tolerance={ArrivalTolerance})");
        Assert_True(utils_crowd_agent::Get_ActiveMoveCorrelationId(_Agent) == CorrelationB,
            "final arrival still belongs to goal B's caller correlation");
        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        FinishFailure("policy replacement emitted an unexpected OnGoalFailed terminal callback");
    }

    UFUNCTION()
    private void OnUnexpectedGoalBlocked(
        FCk_Handle_CrowdAgent InAgent,
        FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        if (IsFinished()) { return; }
        FinishFailure("policy replacement emitted an unexpected OnGoalBlocked terminal callback");
    }
}

class ACk_AutoTest_Crowd_NavQueryFilter_ForceReplan_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_NavQueryFilter_ForceReplan;
    default _TimeoutSeconds = 20.0f;
}
