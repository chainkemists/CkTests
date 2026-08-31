// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: NARROW GAP TRAVERSES CLEANLY
//
// The corridor stand-down (_CorridorStandDown): a 110cm gap between two
// impassable-markup slabs is walkable for a 42cm agent, but between opposing walls
// the sampler penalises inward candidates from both sides and oscillates under
// neighbour pressure. With the stand-down, path-follow + the navmesh clamp
// carry agents through in single file.
//
// Shape: three walkers funnel through the gap to mirrored goals. The contract
// is arrival WITHOUT direction churn: every walker reaches, and no walker's
// actual-velocity heading reverses more than twice across the whole transit.
//============================================================================

class UCk_AutoTest_Crowd_NarrowGap_TraverseCalm : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private const float GapHalfWidthUu = 55.0;     // 110cm gap
    private const float WallHalfX = 50.0;
    private const float WallHalfY = 500.0;
    private const float WallHalfZ = 200.0;
    private const float ApproachX = 500.0;
    private const int32 WalkerCount = 3;
    private const int32 MaxReversalsPerWalker = 2;

    // Small enough that a projection inside a 100uu-thick slab cannot snap to the mesh just
    // outside it and report a false "still walkable".
    private const float32 SlabProbeHalfExtentUu = 20.0f;
    private const float32 ProbeVerticalExtentUu = 300.0f;

    private FCk_Handle_NavSurfaceMarkup _SlabPosY;
    private FCk_Handle_NavSurfaceMarkup _SlabNegY;
    private TArray<FCk_Handle_CrowdAgent> _Walkers;
    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _WalkersDispatched = false;
    private int32 _ReachedCount = 0;

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
            Paint_Slabs();
            utils_nav::Request_NavigationRebuild_ForTesting(SelfHandle);
            return;
        }

        if (_WalkersDispatched == false)
        {
            // The carve must be ON the rebuilt tiles before anyone plans. Probe inside each slab
            // and require the mesh to have gone - the bake is async, so how many poll beats it
            // takes is not something this fixture can budget for.
            if (Slabs_AreSealed(SelfHandle) == false)
            { return; }

            Spawn_Walkers(SelfHandle);
            _WalkersDispatched = true;
            return;
        }

        if (_ReachedCount < WalkerCount)
        { return; }

        for (int32 i = 0; i < _Walkers.Num(); ++i)
        {
            const auto Recorder = utils_crowd_agent_diag::Get_RecorderData(_Walkers[i]);
            Assert_True(Recorder.Get_DirReversalCount() <= MaxReversalsPerWalker,
                f"CHURN: walker {i} reversed direction {Recorder.Get_DirReversalCount()} times through the gap (ceiling {MaxReversalsPerWalker}). A clean single-file traversal does not oscillate between the walls.");
        }

        Destroy_Slabs();
        FinishSuccess();
    }

    // Tests share one PIE world and run seconds apart - GC teardown is far too late for a navmesh
    // carve. Every exit path destroys the slabs explicitly or the next test inherits a severed
    // world, including the one where the engine TimeLimit kills the test before OnPoll can react.
    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Destroy_Slabs();
    }

    private void Destroy_Slabs()
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

    private void Paint_Slabs()
    {
        const auto CentreY = GapHalfWidthUu + WallHalfY;
        _SlabPosY = Paint_Slab(FVector(0.0, CentreY, _FloorZ));
        _SlabNegY = Paint_Slab(FVector(0.0, -CentreY, _FloorZ));
    }

    private FCk_Handle_NavSurfaceMarkup Paint_Slab(FVector InCentre)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(FVector(WallHalfX, WallHalfY, WallHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(FTransform(FRotator::ZeroRotator, InCentre, FVector::OneVector));

        return utils_nav_surface::Request_ImpassableBox(Request);
    }

    private bool Slabs_AreSealed(FCk_Handle& InSelf)
    {
        const auto CentreY = GapHalfWidthUu + WallHalfY;
        FVector Unused;

        if (utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector(0.0, CentreY, _FloorZ),
                SlabProbeHalfExtentUu, Unused, ProbeVerticalExtentUu))
        { return false; }

        return utils_nav::Try_ProjectOntoNavmesh(InSelf, FVector(0.0, -CentreY, _FloorZ),
            SlabProbeHalfExtentUu, Unused, ProbeVerticalExtentUu) == false;
    }

    private void Spawn_Walkers(FCk_Handle& InOwner)
    {
        for (int32 i = 0; i < WalkerCount; ++i)
        {
            // Staggered starts so arrivals at the pinch are sequential, not simultaneous.
            const auto SlotY = (float(i) - 1.0) * 120.0;
            const auto SpawnLoc = FVector(-ApproachX - (float(i) * 100.0), SlotY, _FloorZ + 100.0);
            const auto GoalLoc  = FVector(ApproachX, SlotY, _FloorZ + 100.0);

            auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
            auto WalkerEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
            auto AgentTransform = utils_transform::Add(WalkerEntity,
                FTransform(FRotator::ZeroRotator, SpawnLoc, FVector::OneVector),
                ECk_Replication::DoesNotReplicate);
            auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

            utils_velocity::Add(WalkerEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
            utils_acceleration::Add(WalkerEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
            utils_euler_integrator::Request_Start(WalkerEntity);

            utils_crowd_agent::BindTo_OnGoalReached(Agent,
                FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerReached"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);
            utils_crowd_agent::BindTo_OnGoalFailed(Agent,
                FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerFailed"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);

            utils_crowd_agent_diag::Track(Agent, SpawnLoc, GoalLoc);
            utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(GoalLoc));

            _Walkers.Add(Agent);
        }
    }

    UFUNCTION()
    private void OnWalkerReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        _ReachedCount += 1;
    }

    UFUNCTION()
    private void OnWalkerFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        Destroy_Slabs();
        FinishFailure(f"a walker FAILED to cross a 110cm gap it geometrically fits through (reason={InInfo.Get_Reason()}, crowdFree={InInfo.Get_NoCrowdFreeRouteExisted()})");
    }
}

class ACk_AutoTest_Crowd_NarrowGap_TraverseCalm_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_NarrowGap_TraverseCalm;
    default _TimeoutSeconds = 25.0f;
}
