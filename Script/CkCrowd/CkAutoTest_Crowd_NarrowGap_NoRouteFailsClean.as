// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: NO ROUTE AT ALL MUST FAIL CLEANLY AND BOUNDEDLY
//
// The no-progress ladder's crowd-regime contract - and its dedicated test
// instrument (the BunchUp budget cannot contain approach + window + block, so
// the ladder needs a scenario where it is the ONLY rescue).
//
// Shape: full-width impassable-markup slabs leave a single 110cm gap, a parked
// agent plugs it, and the flanks are closed - there is NO route the walker can
// physically take. Strict planning fails honestly (no crowd-free route);
// the permissive toll path goes through a body that will never move.
//
// Contract: within the budget the walker reports OnGoalFailed carrying
// NoCrowdFreeRouteExisted=true - the clear message a queue manager or planner
// acts on - and it does NOT press against the blocker for the whole budget.
// An agent that is still Walking when the budget expires is the ladder-
// starvation defect this instrument exists to expose.
//============================================================================

class UCk_AutoTest_Crowd_NarrowGap_NoRouteFailsClean : UCk_AutoTest_Base
{
    // Budget sized with headroom over the no-progress ladder's measured run against a hard body
    // (~30s: a 3s no-progress window, two stall re-plans and three blocked rechecks), so a slow
    // frame cannot turn a bounded failure into a timeout.
    default _TimeoutSeconds = 75.0f;

    private const float GapHalfWidthUu = 55.0;
    private const float WallHalfX = 50.0;
    private const float WallHalfY = 2000.0;     // spans the whole play space - no detour exists
    private const float WallHalfZ = 200.0;
    private const float ApproachX = 500.0;
    private const float FailDeadlineSec = 60.0;
    private const float MaxBlockerDriftUu = 15.0;
    private const int32 MaxReversalsWhilePressing = 4;

    private FCk_Handle_NavSurfaceMarkup _SlabPosY;
    private FCk_Handle_NavSurfaceMarkup _SlabNegY;
    private FCk_Handle_CrowdAgent _Blocker;
    private FCk_Handle_CrowdAgent _Walker;
    private FVector _BlockerSpawnLoc = FVector::ZeroVector;
    private FVector _GoalLoc = FVector::ZeroVector;
    private int32 _ReplanCount = 0;
    private float _NextLogAtSec = 0.0;
    private ECk_CrowdAgent_MovementState _LastState = ECk_CrowdAgent_MovementState::None;
    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _BlockerSpawned = false;
    private bool _WalkerDispatched = false;
    private float _PressElapsedSec = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(-ApproachX, 0.0, 100.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5));
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
            FVector OriginOnMesh;
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector::ZeroVector, 100.0f, OriginOnMesh, 300.0f) == false)
            { return; }

            _MeshFound = true;
            _FloorZ = float(OriginOnMesh.Z);

            const auto CentreY = GapHalfWidthUu + WallHalfY;
            _SlabPosY = Paint_Slab(FVector(0.0, CentreY, _FloorZ));
            _SlabNegY = Paint_Slab(FVector(0.0, -CentreY, _FloorZ));
            utils_nav::Request_NavigationRebuild_ForTesting(SelfHandle);
            return;
        }

        if (_BlockerSpawned == false)
        {
            _BlockerSpawnLoc = FVector(0.0, 0.0, _FloorZ + 100.0);
            _Blocker = Spawn_Agent(SelfHandle, _BlockerSpawnLoc);
            _BlockerSpawned = true;
            return;
        }

        if (_WalkerDispatched == false)
        {
            if (utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Blocker) == false)
            { return; }

            const auto SpawnLoc = FVector(-ApproachX, 0.0, _FloorZ + 100.0);
            const auto GoalLoc  = FVector(ApproachX, 0.0, _FloorZ + 100.0);
            _GoalLoc = GoalLoc;
            _Walker = Spawn_Agent(SelfHandle, SpawnLoc);

            utils_crowd_agent::BindTo_OnGoalFailed(_Walker,
                FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerFailed"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);
            utils_crowd_agent::BindTo_OnGoalReached(_Walker,
                FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerReached"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);

            utils_crowd_agent_diag::Track(_Walker, SpawnLoc, GoalLoc);
            ck::crowd::Display(f"[NARROWGAP] DISPATCH hardBodyMode={utils_crowd_settings::Get_StationaryHardBodyMode()} stationaryMarkupMode={utils_crowd_settings::Get_StationaryMarkupMode()}");
            utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(GoalLoc));
            _WalkerDispatched = true;
            return;
        }

        _PressElapsedSec += 0.5;

        const auto State = utils_crowd_agent::Get_MovementState(_Walker);
        if (State == ECk_CrowdAgent_MovementState::PathPending && _LastState != ECk_CrowdAgent_MovementState::PathPending)
        { _ReplanCount += 1; }
        _LastState = State;

        const auto BlockerDrift = Get_BlockerDrift();
        if (BlockerDrift > MaxBlockerDriftUu)
        {
            const auto Shoved = f"SHOVED: the parked blocker drifted {BlockerDrift}uu (ceiling {MaxBlockerDriftUu}) after {_PressElapsedSec}s of pressing. A walker with no route must not displace a stationary-markup-confirmed body.";
            Assert_True(false, Shoved);
            FinishFailure(Shoved);
            return;
        }

        if (_PressElapsedSec >= _NextLogAtSec)
        {
            _NextLogAtSec = _PressElapsedSec + 2.5;
            ck::crowd::Display(f"[NARROWGAP] t={_PressElapsedSec} blockerDrift={BlockerDrift} walkerDist={Get_WalkerDistToGoal()} state={State} goalBlockedHold={utils_crowd_agent::Get_IsGoalBlocked(_Walker)} wp={utils_crowd_agent::Get_CurrentWaypointIndex(_Walker)} replans={_ReplanCount} walkerSpeed={DoGet_Speed(_Walker)} walkerMarkupConfirmed={utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Walker)} blockerState={utils_crowd_agent::Get_MovementState(_Blocker)} blockerSpeed={DoGet_Speed(_Blocker)} blockerMarkupConfirmed={utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Blocker)}");
        }

        if (_PressElapsedSec >= FailDeadlineSec)
        {
            const auto BlockedHold = utils_crowd_agent::Get_IsGoalBlocked(_Walker);
            FinishFailure(f"UNBOUNDED: {FailDeadlineSec}s elapsed with no OnGoalFailed (goalBlockedHold={BlockedHold}). An agent with NO physically walkable route must terminate boundedly - this is the no-progress ladder failing to escalate against a crowd plug.");
        }
    }

    private float Get_BlockerDrift() const
    {
        if (ck::Is_NOT_Valid(_Blocker)) { return -1.0; }
        auto DriftDelta = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Blocker))) - _BlockerSpawnLoc;
        DriftDelta.Z = 0.0;
        return float(DriftDelta.Size());
    }

    private float DoGet_Speed(FCk_Handle_CrowdAgent InAgent) const
    {
        if (ck::Is_NOT_Valid(InAgent)) { return -1.0; }
        FCk_Handle Generic = InAgent;
        return float(utils_velocity::Get_CurrentVelocity(
            utils_velocity::DoCastChecked(Generic)).Size());
    }

    private float Get_WalkerDistToGoal() const
    {
        if (ck::Is_NOT_Valid(_Walker)) { return -1.0; }
        auto ToGoal = _GoalLoc - utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Walker)));
        ToGoal.Z = 0.0;
        return float(ToGoal.Size());
    }

    private FCk_Handle_CrowdAgent Spawn_Agent(FCk_Handle& InOwner, FVector InLoc)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, InLoc, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        return Agent;
    }

    // Tests share one PIE world and run seconds apart - GC teardown is far too late for a navmesh
    // carve, and THESE slabs span the whole play space. They come down on every exit path,
    // including the engine TimeLimit one.
    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        if (ck::IsValid(_SlabPosY))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_SlabPosY));
            _SlabPosY = FCk_Handle_NavSurfaceMarkup();
        }
        if (ck::IsValid(_SlabNegY))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_SlabNegY));
            _SlabNegY = FCk_Handle_NavSurfaceMarkup();
        }
    }

    private FCk_Handle_NavSurfaceMarkup Paint_Slab(FVector InCentre)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(FVector(WallHalfX, WallHalfY, WallHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(FTransform(FRotator::ZeroRotator, InCentre, FVector::OneVector));

        return utils_nav_surface::Request_ImpassableBox(Request);
    }

    UFUNCTION()
    private void OnWalkerReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }

        ck::crowd::Display(f"[NARROWGAP] REACHED t={_PressElapsedSec} blockerDrift={Get_BlockerDrift()} walkerDist={Get_WalkerDistToGoal()} state={utils_crowd_agent::Get_MovementState(_Walker)} goalBlockedHold={utils_crowd_agent::Get_IsGoalBlocked(_Walker)} wp={utils_crowd_agent::Get_CurrentWaypointIndex(_Walker)} replans={_ReplanCount} walkerSpeed={DoGet_Speed(_Walker)} walkerMarkupConfirmed={utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Walker)} blockerState={utils_crowd_agent::Get_MovementState(_Blocker)} blockerSpeed={DoGet_Speed(_Blocker)} blockerMarkupConfirmed={utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Blocker)}");

        FinishFailure("the walker REACHED a goal that is physically unreachable - it walked through the parked blocker's body");
    }

    UFUNCTION()
    private void OnWalkerFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

        ck::crowd::Display(f"[NARROWGAP] GOALFAILED t={_PressElapsedSec} blockerDrift={Get_BlockerDrift()} walkerDist={Get_WalkerDistToGoal()} state={utils_crowd_agent::Get_MovementState(_Walker)} goalBlockedHold={utils_crowd_agent::Get_IsGoalBlocked(_Walker)} wp={utils_crowd_agent::Get_CurrentWaypointIndex(_Walker)} replans={_ReplanCount} walkerSpeed={DoGet_Speed(_Walker)} walkerMarkupConfirmed={utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Walker)} blockerState={utils_crowd_agent::Get_MovementState(_Blocker)} blockerSpeed={DoGet_Speed(_Blocker)} blockerMarkupConfirmed={utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Blocker)} noCrowdFreeRoute={InInfo.Get_NoCrowdFreeRouteExisted()} reason={InInfo.Get_Reason()}");

        Assert_True(InInfo.Get_NoCrowdFreeRouteExisted(),
            "MESSAGE: OnGoalFailed fired but NoCrowdFreeRouteExisted was false - gameplay cannot tell 'blocked by standing bodies' from 'no route at all', which is the clear-message contract this payload exists for.");

        const auto Recorder = utils_crowd_agent_diag::Get_RecorderData(_Walker);
        Assert_True(Recorder.Get_DirReversalCount() <= MaxReversalsWhilePressing,
            f"CHURN: the walker reversed direction {Recorder.Get_DirReversalCount()} times before failing (ceiling {MaxReversalsWhilePressing}). A bounded failure must not look like a fidget fit.");

        FinishSuccess();
    }
}

class ACk_AutoTest_Crowd_NarrowGap_NoRouteFailsClean_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_NarrowGap_NoRouteFailsClean;
    default _TimeoutSeconds = 75.0f;
}
