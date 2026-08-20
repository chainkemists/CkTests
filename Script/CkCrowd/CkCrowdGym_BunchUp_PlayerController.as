// --------------------------------------------------------------------------------------------------------------------
// Crowd Bunch-Up Gym — PlayerController
//
// See CkCrowdGym_BunchUp_GameMode.as for the console surface.
//
// Layout mirrors the Diagnostic gym: one station registered via Get_RequiredStations, placed by the
// cycler grid layout, with the floor and every agent anchored to the station's actual placed
// transform through StationLocal_To_World — so wherever the cycler puts the station, the content
// follows.
//
// Spawn placement: a single ring at RingRadius for small counts. Past SingleRingMaxCount a single
// ring puts neighbouring agents inside each other's separation band before they have moved a step,
// which measures spawn overlap rather than goal contention — so larger counts split across two
// concentric rings with the inner ring rotated half a step so the spokes do not line up (the
// pattern CkAutoTest_Crowd_SteeringPerf uses for its 240-agent workload).
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_BunchUp_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _PcEntity;
    private FCk_Handle _StationHandle;
    private FCk_Handle _NavProbeEntity;
    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private bool _AutoSpawned = false;

    private const int32 AutoSpawnCount = 20;

    // Station-LOCAL +X is "in front of the alcove" (toward the player camera) after the cycler's
    // 180 degree rotation, so a local +X offset always lands in the visible play area.
    private const float SpawnZ           = 100.0;
    private const float StationFwdOffset = 800.0;
    private const float RingRadius       = 600.0;
    private const float InnerRingRadius  = 420.0;
    private const int32 DefaultCount     = 15;
    private const int32 SingleRingMaxCount = 12;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.BunchUp");
            Station.AutoSize = true;
            Station.Title = FText::FromString("CROWD BUNCH-UP (shared goal)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("20 agents auto-spawn on two rings, ALL commanded to the same centre point."));
            Description.Add(FText::FromString("Expected: one agent reaches it, the rest settle into a packed ring and stop."));
            Description.Add(FText::FromString("Defect: agents fidget against the pile forever, never learning the goal is taken."));
            Description.Add(FText::FromString("Console: Ck_GymCrowd_BunchUp_Spawn / _Reset / _Digest"));
            Description.Add(FText::FromString("Visuals: ck.Crowd.Debug 1  |  Data panel: ck.CrowdDebugger 1"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _PcEntity = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_PcEntity))
        {
            ck::crowd::Warning("BunchUp gym: PC entity invalid; cannot start");
            return;
        }

        _StationHandle = Get_StationHandle("Gym.Crowd.BunchUp");
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::crowd::Warning("BunchUp gym: station handle invalid at StartGym");
            return;
        }

        SpawnFloor();

        // AFTER the floor spawns, not before: Recast has to see the runtime floor before any agent
        // asks for a path, and the floor is spawned here rather than in BeginPlay because the
        // station transforms it anchors to only exist once the stations have settled.
        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);

        // Auto-spawn gate: a probe path from a real ring point through the centre proves the bake
        // finished (the same readiness pattern the BunchUp autotest uses); spawning on a timer
        // instead would race the async tile build and every MoveTo would fail.
        const auto Centre = Get_Centre();
        const auto ProbeStart = Centre + FVector(RingRadius, 0.0, 0.0);
        _NavProbeEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        utils_transform::Add(_NavProbeEntity,
            FTransform(FRotator::ZeroRotator, ProbeStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::BindTo_OnPathReady(_NavProbeEntity,
            FCk_Delegate_Nav_OnPathReady(this, n"OnNavProbeReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::BindTo_OnPathFailed(_NavProbeEntity,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnNavProbeFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::Request_FindPath(_NavProbeEntity, FCk_Request_Nav_FindPath(Centre));

        ck::crowd::Log(f"BunchUp gym started — auto-spawning {AutoSpawnCount} agents once the navmesh probe resolves. Ck_GymCrowd_BunchUp_Spawn re-runs manually.");
    }

    UFUNCTION()
    private void OnNavProbeReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (_AutoSpawned || _Agents.Num() > 0)
        { return; }

        _AutoSpawned = true;
        Ck_GymCrowd_BunchUp_Spawn(AutoSpawnCount);
    }

    UFUNCTION()
    private void OnNavProbeFailed(FCk_Handle InHandle)
    {
        ck::crowd::Log("BunchUp gym: navmesh probe failed — auto-spawn skipped; run Ck_GymCrowd_BunchUp_Spawn manually once the navmesh is visible.");
    }

    private void SpawnFloor()
    {
        // Single big floor at world origin — the cycler map's NavMeshBoundsVolume is centred at
        // origin, so a floor at origin lands fully inside it.
        //
        // Z SCALE MUST BE >= 0.5 — anything thinner and the navmesh bake silently produces no
        // walkable tiles on the surface.
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(75.0, 75.0, 0.5);   // 7500x7500x50cm

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::crowd::Warning("BunchUp gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);

        ck::crowd::Log(f"BunchUp gym: floor spawned at {FloorLocation} scale={FloorScale}");
    }

    // ---- Station-local -> world ------------------------------------------------------------------

    private FVector StationLocal_To_World(FString InStationTag, FVector InLocalOffset)
    {
        const auto StationXform = Get_StationAnchorTransform(InStationTag, ECk_GymStation_Anchor::FootprintCenter);
        return StationXform.TransformPosition(InLocalOffset);
    }

    private FVector Get_Centre()
    {
        return StationLocal_To_World("Gym.Crowd.BunchUp", FVector(StationFwdOffset, 0.0, SpawnZ));
    }

    // ---- Console commands --------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Crowd BunchUp - Spawn Agents On Shared Goal")
    void Ck_GymCrowd_BunchUp_Spawn(int32 InCount = 15)
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        const auto Count = InCount > 0 ? InCount : DefaultCount;
        const auto Centre = Get_Centre();

        // Every agent gets the SAME target. That is the condition under test: exactly one of them
        // can stand on it.
        if (Count <= SingleRingMaxCount)
        {
            SpawnRing(Centre, RingRadius, Count, 0, Count, 0.0);
        }
        else
        {
            const auto InnerCount = Math::IntegerDivisionTrunc(Count, 2);
            const auto OuterCount = Count - InnerCount;
            const auto InnerStep  = (2.0 * Math::PI) / float(InnerCount);
            SpawnRing(Centre, InnerRingRadius, InnerCount, 0, Count, 0.5 * InnerStep);
            SpawnRing(Centre, RingRadius, OuterCount, InnerCount, Count, 0.0);
        }

        ck::crowd::Log(f"BunchUp gym: dispatched {Count} agents to the shared centre {Centre}");
    }

    UFUNCTION(Exec, DisplayName="Crowd BunchUp - Reset (Destroy Agents)")
    void Ck_GymCrowd_BunchUp_Reset()
    {
        if (HasAuthority() == false)
        { return; }

        const auto Count = _Agents.Num();
        for (auto Agent : _Agents)
        {
            if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); }
        }
        _Agents.Empty();
        ck::crowd::Log(f"BunchUp gym: destroyed {Count} agents");
    }

    UFUNCTION(Exec, DisplayName="Crowd BunchUp - Emit Per-Agent Digest")
    void Ck_GymCrowd_BunchUp_Digest()
    {
        if (HasAuthority() == false)
        { return; }

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (ck::Is_NOT_Valid(_Agents[i])) { continue; }
            utils_crowd_agent_diag::EmitDigest_ForAgent(_Agents[i], 0, "BunchUp", i);
        }
        ck::crowd::Log(f"BunchUp gym: emitted digest for {_Agents.Num()} agents — grep [CrowdDiag]");
    }

    // ---- Agent factory ---------------------------------------------------------------------------

    private void SpawnRing(FVector InCentre, float InRadius, int32 InRingCount, int32 InColorIndexBase, int32 InColorTotal, float InAngleOffset)
    {
        const auto AngleStep = (2.0 * Math::PI) / float(InRingCount);
        for (int32 i = 0; i < InRingCount; ++i)
        {
            const auto Angle = InAngleOffset + AngleStep * float(i);
            const auto SpawnLoc = InCentre + FVector(InRadius * Math::Cos(Angle), InRadius * Math::Sin(Angle), 0.0);
            // Hue varies around the wheel across the WHOLE population (not per ring) so each agent
            // stays individually legible once they pile up at the centre.
            const auto HueDeg = (360.0 / float(InColorTotal)) * float(InColorIndexBase + i);
            const auto Color = FLinearColor::MakeFromHSV8(uint8(HueDeg * 255.0 / 360.0), 200, 220);
            _Agents.Add(SpawnAgent(SpawnLoc, InCentre, Color, FName(f"BunchUpAgent_{_Agents.Num()}")));
        }
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FVector InSpawnLoc, FVector InTargetLoc, FLinearColor InColor, FName InDebugName)
    {
        // Lifetime-OWNED BY the registry transient, not composed ONTO it: utils_crowd_agent::Add
        // permits one agent per entity, so passing the transient directly would put every agent on
        // the same entity and leave a "crowd" of exactly one.
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        AgentEntity.Set_DebugName(InDebugName);

        // Planar look direction — crowd agents are yaw-only, and FaceAngle's per-tick yaw lerp
        // cannot correct a pitch baked into the spawn rotation.
        const auto LookDir   = InTargetLoc - InSpawnLoc;
        const auto PlanarDir = FVector(LookDir.X, LookDir.Y, 0.0);
        const auto Rot       = PlanarDir.GetSafeNormal().Rotation();

        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(Rot, InSpawnLoc, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_crowd_agent::Set_DebugColor(Agent, InColor);

        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(InTargetLoc));

        // Opt into the diagnostic recorder so Ck_GymCrowd_BunchUp_Digest has data and the
        // breadcrumb-draw processor renders the trail in PIE.
        utils_crowd_agent_diag::Track(Agent, InSpawnLoc, InTargetLoc);

        return Agent;
    }
}
