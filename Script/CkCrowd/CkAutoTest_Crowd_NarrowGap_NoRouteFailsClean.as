// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: NO ROUTE AT ALL MUST FAIL CLEANLY AND BOUNDEDLY
//
// The no-progress ladder's crowd-regime contract - and its dedicated test
// instrument (the BunchUp budget cannot contain approach + window + block, so
// the ladder needs a scenario where it is the ONLY rescue).
//
// Shape: full-width UNavArea_Null slabs leave a single 110cm gap, a parked
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
    default _TimeoutSeconds = 45.0f;

    private const float GapHalfWidthUu = 55.0;
    private const float WallHalfX = 50.0;
    private const float WallHalfY = 2000.0;     // spans the whole play space - no detour exists
    private const float WallHalfZ = 200.0;
    private const float ApproachX = 500.0;
    private const float FailDeadlineSec = 35.0;
    private const int32 MaxReversalsWhilePressing = 4;

    private UCk_NavAreaMarkup_UE _SlabPosY = nullptr;
    private UCk_NavAreaMarkup_UE _SlabNegY = nullptr;
    private FCk_Handle_CrowdAgent _Blocker;
    private FCk_Handle_CrowdAgent _Walker;
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
            _SlabPosY = utils_nav_area_markup::Request_Create(SelfHandle,
                FTransform(FRotator::ZeroRotator, FVector(0.0, CentreY, _FloorZ), FVector::OneVector),
                FVector(WallHalfX, WallHalfY, WallHalfZ),
                UNavArea_Null);
            _SlabNegY = utils_nav_area_markup::Request_Create(SelfHandle,
                FTransform(FRotator::ZeroRotator, FVector(0.0, -CentreY, _FloorZ), FVector::OneVector),
                FVector(WallHalfX, WallHalfY, WallHalfZ),
                UNavArea_Null);
            utils_nav::Request_NavigationRebuild_ForTesting(SelfHandle);
            return;
        }

        if (_BlockerSpawned == false)
        {
            _Blocker = Spawn_Agent(SelfHandle, FVector(0.0, 0.0, _FloorZ + 100.0));
            _BlockerSpawned = true;
            return;
        }

        if (_WalkerDispatched == false)
        {
            if (utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Blocker) == false)
            { return; }

            const auto SpawnLoc = FVector(-ApproachX, 0.0, _FloorZ + 100.0);
            const auto GoalLoc  = FVector(ApproachX, 0.0, _FloorZ + 100.0);
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
            utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(GoalLoc));
            _WalkerDispatched = true;
            return;
        }

        _PressElapsedSec += 0.5;
        if (_PressElapsedSec >= FailDeadlineSec)
        {
            const auto BlockedHold = utils_crowd_agent::Get_IsGoalBlocked(_Walker);
            FinishFailure(f"UNBOUNDED: {FailDeadlineSec}s elapsed with no OnGoalFailed (goalBlockedHold={BlockedHold}). An agent with NO physically walkable route must terminate boundedly - this is the no-progress ladder failing to escalate against a crowd plug.");
        }
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
        if (_SlabPosY != nullptr) { utils_nav_area_markup::Request_Destroy(_SlabPosY); _SlabPosY = nullptr; }
        if (_SlabNegY != nullptr) { utils_nav_area_markup::Request_Destroy(_SlabNegY); _SlabNegY = nullptr; }
    }

    UFUNCTION()
    private void OnWalkerReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        FinishFailure("the walker REACHED a goal that is physically unreachable - it walked through the parked blocker's body");
    }

    UFUNCTION()
    private void OnWalkerFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }

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
    default _TimeoutSeconds = 45.0f;
}
