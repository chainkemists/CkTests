// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A NEIGHBOUR ON ITS OWN, DIFFERENT GOAL IS NOT A HOLD
//
// Pins the cluster rule's goal-region term (Get_AnchorQualifyingDepth,
// CkCrowdAgent_BlockDetect_Processor.cpp:178-181). The region is currently
// SelfR + NbrR + ArrivalRadius + ContactPad = 42+42+30+10 = 124uu, which is
// WIDER than a body: any settled agent within 124uu of my destination, touching
// me, and nearer my destination than I am, is read as "my goal is crowded" -
// DoBlock then strips Walking (:604-665) and a crowd hold never re-checks its
// way out (BlockedRecheck :748-770). A queue neighbour parked on its OWN goal
// one slot ahead is exactly that shape, and it holds the agent behind it
// forever. The term must be SelfR + NbrR - ArrivalRadius + ContactPad = 64uu:
// "close enough that I could not stand where it stands and still be short of my
// arrival tolerance". This fixture parks A on its own goal 120uu from B's -
// inside 124, outside 64 - so it is RED on the wide bound and GREEN on the
// narrow one.
//
// JoltNav comparison: JoltNav infers no occupancy from proximity at all - only a
// stationary footprint that actually covers the goal blocks it.
//
// No slabs and no own field: the C++ runner stages the origin field over the
// shared floor (_AutoStageOriginField left at its default), so this runs
// unchanged on either provider.
//============================================================================

class UCk_AutoTest_Crowd_DistinctGoals_NeighbourOnOwnGoalDoesNotHold : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    // Two walkers on one line, one queue slot apart. A parks ON its own goal; B's goal is
    // GoalSeparationUu beyond it on the same line.
    //
    //   A: spawn X 400 -> goal X 500        B: spawn X 200 -> goal X 620
    //
    // A's leg is 100uu. Ramping to 192cm/s at the default 480cm/s^2 takes 0.40s and covers 38uu;
    // the remaining 62uu at 192 takes 0.32s. OnGoalReached fires on ENTERING the 30uu arrival ring
    // (70uu travelled, ~0.56s) and braking from 192 covers 192^2/(2*480) = 38uu, so A comes to rest
    // at X ~500-510 - on its goal or just past it, never short of X 470. A counts as SETTLED from
    // the instant it reaches (Get_HasReachedActiveGoal, CkCrowdAgent_Settled_Algorithm.h:26-38),
    // which is 1.5s (_StationaryMarkupDelaySeconds) before its stationary markup can paint.
    //
    // B is in CONTACT with A at centre distance SelfR + NbrR + ContactPad = 94uu, i.e. X ~406.
    // From X 200 that is 206uu: 38uu of ramp (0.40s) + 168uu at 192 (0.87s) ~= 1.27s after dispatch.
    // That lands AFTER A settles (0.56s) and BEFORE A's markup paints (~2.06s), so the contact is
    // body-to-body, not markup-to-markup. The cluster detector samples every 0.5s
    // (_BlockDetectionInterval), so the block, if it comes, lands by ~1.8s.
    //
    // Contact is not left to the avoidance sampler to grant: the final-approach envelope grows by
    // the settled pack's own extent (CkCrowdAgent_AvoidanceSample_Processor.cpp:102-127), here
    // ArrivalRadius 30 + Suppression 90 + A's 120uu offset from B's goal = ~240uu, and B is 214uu
    // from its goal at contact. Predictive avoidance is already suppressed; B follows path-follow
    // straight into A.
    //
    // At that instant every one of the cluster rule's four conditions is met on the CURRENT bound:
    //   A is 120uu from B's goal          -> inside 124, outside 64
    //   centre distance 94                -> <= 42 + 42 + 10
    //   A is 120 from B's goal, B is 214  -> A is strictly nearer
    //   A is dead ahead of B              -> dot 1.0, inside the +/-60 degree cone
    private const float SpawnAX = 400.0;
    private const float GoalAX  = 500.0;
    private const float SpawnBX = 200.0;
    private const float GoalBX  = 620.0;   // GoalAX + GoalSeparationUu
    private const float GoalSeparationUu = 120.0;

    private const float SpawnHeightUu = 100.0;
    private const float PollIntervalSec = 0.5;

    // Both legs are short; B's whole trip is 420uu (~2.6s at speed) even if it has to work its way
    // around A. Anything past this is a hold, not slow going - report which agent is stuck.
    private const float DeadlineSec = 12.0;

    private FCk_Handle_CrowdAgent _WalkerA;   // arrives first, then stands ON ITS OWN goal
    private FCk_Handle_CrowdAgent _WalkerB;   // walks past A to a goal 120uu further on

    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _Dispatched = false;
    private bool _AReached = false;
    private bool _BReached = false;
    private float _ElapsedSinceDispatchSec = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(SpawnBX, 0.0, SpawnHeightUu), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(PollIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto SelfHandle = DoGet_ScriptEntity();

        if (_MeshFound == false)
        {
            const auto Projected = Do_ProjectOntoSurface(FVector::ZeroVector, FVector(100.0, 100.0, 300.0));
            if (Projected.Get_Status() != ECk_NavSurface_QueryStatus::Success)
            { return; }   // bake not done yet

            _MeshFound = true;
            _FloorZ = float(Projected.Get_Location().Z);
            return;
        }

        if (_Dispatched == false)
        {
            // Same poll for both, so A's head start is exactly the 200uu difference in leg length -
            // that is what puts B in contact inside A's 1.5s markup delay.
            Dispatch_Walkers(SelfHandle);
            _Dispatched = true;
            return;
        }

        _ElapsedSinceDispatchSec += PollIntervalSec;

        if (_AReached && _BReached)
        {
            FinishSuccess();
            return;
        }

        if (_ElapsedSinceDispatchSec >= DeadlineSec)
        {
            const auto BLoc = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_WalkerB)));
            const auto BDistToGoal = float((BLoc - Get_GoalB()).Size());

            FinishFailure(f"NOT ARRIVED after {DeadlineSec}s: A reached={_AReached}, B reached={_BReached}. B is still {BDistToGoal}uu from a goal {GoalSeparationUu}uu clear of anyone's body, blocked={utils_crowd_agent::Get_IsGoalBlocked(_WalkerB)}. A neighbour standing on a DIFFERENT goal must be walked around, not waited out.");
            return;
        }
    }

    private FVector Get_GoalA() const
    {
        return FVector(GoalAX, 0.0, _FloorZ + SpawnHeightUu);
    }

    private FVector Get_GoalB() const
    {
        return FVector(GoalBX, 0.0, _FloorZ + SpawnHeightUu);
    }

    private FCk_NavSurface_ProjectionResult Do_ProjectOntoSurface(FVector InPoint, FVector InSearchHalfExtents) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(InSearchHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query);
    }

    private void Dispatch_Walkers(FCk_Handle& InOwner)
    {
        const auto SpawnA = FVector(SpawnAX, 0.0, _FloorZ + SpawnHeightUu);
        const auto SpawnB = FVector(SpawnBX, 0.0, _FloorZ + SpawnHeightUu);

        _WalkerA = Spawn_Agent(InOwner, SpawnA, n"DistinctGoals_A_ParksOnOwnGoal");
        _WalkerB = Spawn_Agent(InOwner, SpawnB, n"DistinctGoals_B_WalksPast");

        utils_crowd_agent::BindTo_OnGoalReached(_WalkerA,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnAReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        // Diagnostic only: A's leg is 100uu of open floor. If it fails, the red must say so instead
        // of arriving as a bare deadline on B.
        utils_crowd_agent::BindTo_OnGoalFailed(_WalkerA,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnAFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalReached(_WalkerB,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnBReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(_WalkerB,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnBFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalBlocked(_WalkerB,
            FCk_Delegate_CrowdAgent_OnGoalBlocked(this, n"OnBBlocked"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_WalkerA, FCk_Request_CrowdAgent_MoveTo(Get_GoalA()));
        utils_crowd_agent::Request_MoveTo(_WalkerB, FCk_Request_CrowdAgent_MoveTo(Get_GoalB()));
    }

    private FCk_Handle_CrowdAgent Spawn_Agent(FCk_Handle& InOwner, FVector InLoc, FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, InLoc, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        return Agent;
    }

    UFUNCTION()
    private void OnAReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        _AReached = true;
    }

    UFUNCTION()
    private void OnAFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        FinishFailure(f"FIXTURE NEVER SET UP: A failed its own 100uu leg across open floor (reason={InInfo.Get_Reason()}, crowdFree={InInfo.Get_NoCrowdFreeRouteExisted()}), so the settled neighbour this test needs never existed.");
    }

    UFUNCTION()
    private void OnBReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        _BReached = true;
    }

    UFUNCTION()
    private void OnBFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        FinishFailure(f"B FAILED a goal {GoalSeparationUu}uu clear of the neighbour standing in its path (reason={InInfo.Get_Reason()}, crowdFree={InInfo.Get_NoCrowdFreeRouteExisted()}). Walking around one settled body is not a failure condition.");
    }

    UFUNCTION()
    private void OnBBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        if (IsFinished()) { return; }

        // The defect, named at the moment it happens rather than as a timeout 15s later. A crowd
        // hold never re-checks its way out, so the episode is over the instant this fires.
        FinishFailure(f"HELD BY A STRANGER: B was held behind a neighbour parked on a DIFFERENT goal {GoalSeparationUu}uu away (reason={InInfo.Get_Reason()}, distToGoal={InInfo.Get_DistanceToGoal()}). The cluster rule's goal region is SelfR + NbrR + ArrivalRadius + ContactPad = 124uu, wider than a body, so it swallows the queue slot ahead. It must be SelfR + NbrR - ArrivalRadius + ContactPad = 64uu - only a body I could not stand behind and still be inside my own arrival tolerance.");
    }
}

class ACk_AutoTest_Crowd_DistinctGoals_NeighbourOnOwnGoalDoesNotHold_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_DistinctGoals_NeighbourOnOwnGoalDoesNotHold;
    default _TimeoutSeconds = 15.0f;
}
