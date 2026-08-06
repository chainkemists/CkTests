// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: PUSH-APART AGENT STAYS ON NAVMESH
//
// The invariant restored by FProcessor_CrowdAgent_ConstrainToNavmesh (dtCrowd's
// corridor movePosition, which the original port dropped): no force may displace
// an agent off the navmesh.
//
// Shape: locate the navmesh's +X edge by probing, park an idle agent A right at
// it, spawn a second idle agent B overlapping A from the inland side. Push-apart
// must resolve the overlap — but the shove that lands on A points OFF the mesh.
// With the constraint, A holds the edge and B absorbs the correction inland;
// without it (ECk_CrowdNavmeshConstraintMode::Disabled), A is displaced ~30cm+
// past the mesh boundary and the on-mesh assertion fails. Red-green proven by
// toggling that project setting.
//============================================================================

class UCk_AutoTest_Crowd_PushApart_AgentStaysOnNavmesh : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private const float32 ProbeExtentUu = 5.0f;
    private const float32 ProbeVerticalExtentUu = 300.0f;
    private const float CoarseStepUu = 250.0;
    private const float RefineStepUu = 5.0;
    private const float MaxProbeUu = 20000.0;
    private const float SettleSec = 2.5;
    private const float32 OnMeshAssertExtentUu = 15.0f;
    private const float MinFinalSeparationUu = 80.0;

    private FCk_Handle_CrowdAgent _AgentAtEdge;
    private FCk_Handle_CrowdAgent _AgentInland;
    private float _EdgeX = 0.0;
    private float _FloorZ = 0.0;
    private bool _MeshFound = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the navmesh: AutoTests_CkTests_Level has the fixture but the bake is lazy.
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        // Poll until the bake lands — the edge probe below is synchronous and needs a live mesh.
        auto TimerParams = FCk_Timer_Spec(FCk_Time(0.25));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPollMesh"));
    }

    UFUNCTION()
    private void OnPollMesh(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished() || _MeshFound) { return; }

        auto SelfHandle = DoGet_ScriptEntity();

        FVector OriginOnMesh;
        if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector::ZeroVector, 100.0f, OriginOnMesh, ProbeVerticalExtentUu) == false)
        { return; }   // bake not done yet — keep polling

        _MeshFound = true;
        _FloorZ = float(OriginOnMesh.Z);

        if (FindMeshEdge(SelfHandle) == false)
        {
            FinishFailure(f"navmesh +X edge not found within {MaxProbeUu}uu of origin — test level changed?");
            return;
        }

        const auto SpawnZ = _FloorZ + 100.0f;
        _AgentAtEdge = SpawnIdleAgent(SelfHandle, FVector(_EdgeX - 10.0f, 0.0f, SpawnZ));
        _AgentInland = SpawnIdleAgent(SelfHandle, FVector(_EdgeX - 22.0f, 0.0f, SpawnZ));

        auto SettleParams = FCk_Timer_Spec(FCk_Time(SettleSec));
        SettleParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto SettleTimer = utils_timer::Add(SelfHandle, SettleParams);
        SettleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSettled"));
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto SelfHandle = DoGet_ScriptEntity();

        const auto EdgeLoc = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(_AgentAtEdge)));
        const auto InlandLoc = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(_AgentInland)));

        auto PlanarSep = EdgeLoc - InlandLoc;
        PlanarSep.Z = 0.0;
        const auto FinalSeparation = float(PlanarSep.Size());
        Assert_True(FinalSeparation >= MinFinalSeparationUu,
            f"push-apart never resolved the overlap (separation {FinalSeparation}uu < {MinFinalSeparationUu}uu) — the shove this test guards against did not happen");

        AssertOnMesh(SelfHandle, EdgeLoc, "edge agent");
        AssertOnMesh(SelfHandle, InlandLoc, "inland agent");

        FinishSuccess();
    }

    private void AssertOnMesh(FCk_Handle& InSelfHandle, FVector InAgentLoc, FString InWho)
    {
        FVector OnMesh;
        const auto Projected = utils_nav::Try_ProjectOntoNavmesh(
            InSelfHandle, InAgentLoc, OnMeshAssertExtentUu, OnMesh, ProbeVerticalExtentUu);

        const auto AgentX = float(InAgentLoc.X);
        Assert_True(Projected,
            f"{InWho} ended OFF the navmesh at X={AgentX} (mesh edge X={_EdgeX}) — displacement was not constrained to the mesh");

        if (Projected == false) { return; }

        auto PlanarDelta = OnMesh - InAgentLoc;
        PlanarDelta.Z = 0.0;
        const auto DriftOffMesh = float(PlanarDelta.Size());
        Assert_True(DriftOffMesh <= 12.0f,
            f"{InWho} ended {DriftOffMesh}uu off the navmesh at X={AgentX} (mesh edge X={_EdgeX})");

        const auto VerticalDrift = Math::Abs(float(InAgentLoc.Z - OnMesh.Z));
        Assert_True(VerticalDrift <= 2.0f,
            f"{InWho}'s feet ended {VerticalDrift}uu above/below the navmesh surface — constrained movement passed free-space Z through");
    }

    private bool FindMeshEdge(FCk_Handle& InSelfHandle)
    {
        FVector Unused;

        float LastGoodX = 0.0f;
        float CoarseFailX = -1.0f;
        for (float X = CoarseStepUu; X <= MaxProbeUu; X += CoarseStepUu)
        {
            if (utils_nav::Try_ProjectOntoNavmesh(InSelfHandle, FVector(X, 0.0f, _FloorZ), ProbeExtentUu, Unused, ProbeVerticalExtentUu) == false)
            {
                CoarseFailX = X;
                break;
            }
            LastGoodX = X;
        }

        if (CoarseFailX < 0.0f)
        { return false; }

        for (float X = LastGoodX + RefineStepUu; X < CoarseFailX; X += RefineStepUu)
        {
            if (utils_nav::Try_ProjectOntoNavmesh(InSelfHandle, FVector(X, 0.0f, _FloorZ), ProbeExtentUu, Unused, ProbeVerticalExtentUu) == false)
            { break; }
            LastGoodX = X;
        }

        _EdgeX = LastGoodX;
        return true;
    }

    private FCk_Handle_CrowdAgent SpawnIdleAgent(FCk_Handle& InOwner, FVector InSpawn)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(FRotator::ZeroRotator, InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);
        return Agent;
    }
}

class ACk_AutoTest_Crowd_PushApart_AgentStaysOnNavmesh_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_PushApart_AgentStaysOnNavmesh;
    default _TimeoutSeconds = 12.0f;
}
