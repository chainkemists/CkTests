// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: A BLOCKED GAP IS DETOURED, NOT PRESSED
//
// Two-phase planning (_PlanAroundStandingCrowds): a stationary agent parked in
// a 110cm gap paints markup that the STRICT phase treats as impassable, so a
// walker whose goal lies past the gap routes around the wall ends instead of
// discovering with its body that the toll-priced through-route cannot
// physically be walked.
//
// Shape: two UNavArea_Null slabs (short enough that a detour around their ends
// exists), one parked blocker in the gap, one walker crossing. Contract: the
// walker ARRIVES, the blocker is NOT displaced, and the walker never comes
// anywhere near contact with it.
//============================================================================

class UCk_AutoTest_Crowd_NarrowGap_BlockedDetours : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private const float GapHalfWidthUu = 55.0;
    private const float WallHalfX = 50.0;
    private const float WallHalfY = 300.0;      // slab ends at |y| = 655 — the detour route
    private const float WallHalfZ = 200.0;
    private const float ApproachX = 500.0;
    private const float MaxBlockerDriftUu = 15.0;
    private const float MinWalkerClearanceUu = 55.0;

    private UCk_NavAreaMarkup_UE _SlabPosY = nullptr;
    private UCk_NavAreaMarkup_UE _SlabNegY = nullptr;
    private FCk_Handle_CrowdAgent _Blocker;
    private FCk_Handle_CrowdAgent _Walker;
    private FVector _BlockerSpawnLoc = FVector::ZeroVector;
    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _BlockerSpawned = false;
    private bool _WalkerDispatched = false;
    private bool _WalkerReached = false;

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
            _BlockerSpawnLoc = FVector(0.0, 0.0, _FloorZ + 100.0);
            _Blocker = Spawn_Agent(SelfHandle, _BlockerSpawnLoc);
            _BlockerSpawned = true;
            return;
        }

        if (_WalkerDispatched == false)
        {
            // The blocker's disc must actually be ON the rebuilt mesh before the walker plans —
            // an unpainted blocker is invisible to the strict phase and the test measures nothing.
            if (utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Blocker) == false)
            { return; }

            const auto SpawnLoc = FVector(-ApproachX, 0.0, _FloorZ + 100.0);
            const auto GoalLoc  = FVector(ApproachX, 0.0, _FloorZ + 100.0);
            _Walker = Spawn_Agent(SelfHandle, SpawnLoc);

            utils_crowd_agent::BindTo_OnGoalReached(_Walker,
                FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerReached"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);
            utils_crowd_agent::BindTo_OnGoalFailed(_Walker,
                FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerFailed"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);

            utils_crowd_agent_diag::Track(_Walker, SpawnLoc, GoalLoc);
            utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(GoalLoc));
            _WalkerDispatched = true;
            return;
        }

        if (_WalkerReached == false)
        { return; }

        const auto BlockerLoc = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Blocker)));
        auto DriftDelta = BlockerLoc - _BlockerSpawnLoc;
        DriftDelta.Z = 0.0;
        const auto BlockerDrift = float(DriftDelta.Size());
        Assert_True(BlockerDrift <= MaxBlockerDriftUu,
            f"SHOVED: the parked blocker drifted {BlockerDrift}uu (ceiling {MaxBlockerDriftUu}). A detouring walker must not displace the body it routes around.");

        const auto Recorder = utils_crowd_agent_diag::Get_RecorderData(_Walker);
        Assert_True(Recorder.Get_MinSepAcrossCycle() >= MinWalkerClearanceUu,
            f"PRESSED: the walker came within {Recorder.Get_MinSepAcrossCycle()}uu of the blocker (need {MinWalkerClearanceUu}+). The route went through the gap, not around the wall ends.");

        FinishSuccess();
    }

    // Tests share one PIE world and run seconds apart — GC teardown is far too late for a navmesh
    // carve, so the slabs come down on every exit path including the engine TimeLimit one.
    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        if (_SlabPosY != nullptr) { utils_nav_area_markup::Request_Destroy(_SlabPosY); _SlabPosY = nullptr; }
        if (_SlabNegY != nullptr) { utils_nav_area_markup::Request_Destroy(_SlabNegY); _SlabNegY = nullptr; }
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

    UFUNCTION()
    private void OnWalkerReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        _WalkerReached = true;
    }

    UFUNCTION()
    private void OnWalkerFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        FinishFailure(f"the walker FAILED although a detour around the wall ends exists (reason={InInfo.Get_Reason()}, crowdFree={InInfo.Get_NoCrowdFreeRouteExisted()})");
    }
}

class ACk_AutoTest_Crowd_NarrowGap_BlockedDetours_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_NarrowGap_BlockedDetours;
    default _TimeoutSeconds = 30.0f;
}
