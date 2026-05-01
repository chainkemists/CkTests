class ACk_CrowdGym_Locomotion_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _StationHandle;
    private FCk_Handle_CrowdAgent _Agent;
    private FVector _SpawnLocation = FVector::ZeroVector;
    private bool _AgentValid = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.Locomotion");
            Station.Title = FText::FromString("LOCOMOTION (2A)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Console: Ck_GymCrowd_Loco_Spawn / PrintPos / Stop"));
            Description.Add(FText::FromString("Sub-task 2A: ApplyOffset processor smoke test"));
            Description.Add(FText::FromString("After Spawn, agent should move +X at 100 cm/s"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        SpawnFloor();

        _StationHandle = Get_StationHandle("Gym.Crowd.Locomotion");
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::Warning("Locomotion gym: station handle invalid at StartGym");
            return;
        }

        ck::Trace("Locomotion gym started. Run Ck_GymCrowd_Loco_Spawn from the console.");
    }

    private void SpawnFloor()
    {
        // Mirrors the Pathfinding gym floor: 2000cm x 2000cm flat cube, top face at Z=0.
        // Covers the 500cm navmesh projection extent and gives the agent room to walk for
        // ~10 seconds at 100 cm/s. Sub-task 2A doesn't issue path queries, but 2B onward
        // will — keeping the floor here means the gym is ready for navmesh-backed moves.
        const auto FloorLocation = FVector(0.0, 0.0, -25.0);
        const auto FloorScale    = FVector(20.0, 20.0, 0.5);

        auto Floor = SpawnActor(ACk_CrowdGym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::Warning("Locomotion gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);

        ck::Trace(f"Locomotion gym: floor spawned at {FloorLocation} scale={FloorScale}");
    }

    UFUNCTION(Exec, DisplayName="Crowd Locomotion - Spawn Agent")
    void Ck_GymCrowd_Loco_Spawn()
    {
        if (HasAuthority() == false) { return; }

        if (ck::Is_NOT_Valid(_StationHandle))
        {
            _StationHandle = Get_StationHandle("Gym.Crowd.Locomotion");
        }

        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::Warning("Locomotion gym: station handle invalid; cannot spawn");
            return;
        }

        if (_AgentValid)
        {
            ck::Warning("Locomotion gym: an agent already exists. Run Ck_GymCrowd_Loco_Stop first.");
            return;
        }

        // Spawn the CrowdAgent as a child of the station.
        auto AgentParams = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        _Agent = utils_crowd_agent::Add(_StationHandle, AgentParams);

        // The CrowdAgent entity needs a Transform so Request_AddLocationOffset has somewhere to apply.
        // Initial transform: just above the station origin so we can see the entity in the world.
        const auto StationXform = Get_StationAnchorTransform("Gym.Crowd.Locomotion", ECk_GymStation_Anchor::FootprintCenter);
        _SpawnLocation = StationXform.GetLocation() + FVector(0.0, 0.0, 100.0);
        const auto InitialXform = FTransform(FRotator::ZeroRotator, _SpawnLocation, FVector::OneVector);

        // Cast back to a generic handle so we can call utils that take FCk_Handle&.
        FCk_Handle GenericAgent = _Agent;
        utils_transform::Add(GenericAgent, InitialXform, ECk_Replication::DoesNotReplicate);

        // Velocity feature with starting velocity (100, 0, 0) in world space.
        const auto VelocityStart = FVector(100.0, 0.0, 0.0);
        auto VelocityParams = FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, VelocityStart);
        utils_velocity::Add(GenericAgent, VelocityParams, ECk_Replication::DoesNotReplicate);

        // Acceleration feature with zero acceleration — required by the integrator's view.
        auto AccelParams = FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector);
        utils_acceleration::Add(GenericAgent, AccelParams, ECk_Replication::DoesNotReplicate);

        // Start the integrator so FFragment_EulerIntegrator_Current + FTag_EulerIntegrator_NeedsUpdate land
        // on the entity. The view of FProcessor_CrowdAgent_ApplyOffset is then satisfied each tick.
        utils_euler_integrator::Request_Start(GenericAgent);

        _AgentValid = true;

        ck::Trace(f"Locomotion gym: spawned agent at {_SpawnLocation} with velocity {VelocityStart}");
    }

    UFUNCTION(Exec, DisplayName="Crowd Locomotion - Print Position")
    void Ck_GymCrowd_Loco_PrintPos()
    {
        if (_AgentValid == false || ck::Is_NOT_Valid(_Agent))
        {
            ck::Trace("Locomotion gym: no agent. Run Ck_GymCrowd_Loco_Spawn first.");
            return;
        }

        FCk_Handle GenericAgent = _Agent;
        auto TransformHandle = utils_transform::DoCastChecked(GenericAgent);
        if (ck::Is_NOT_Valid(TransformHandle))
        {
            ck::Warning("Locomotion gym: agent has no Transform feature — cannot read position");
            return;
        }

        const auto CurrentLoc = utils_transform::Get_EntityCurrentLocation(TransformHandle);
        const auto Delta = CurrentLoc - _SpawnLocation;

        ck::Trace(f"Locomotion gym: pos={CurrentLoc}  delta_from_spawn={Delta}  (expect +X advancing at 100 cm/s)");
    }

    UFUNCTION(Exec, DisplayName="Crowd Locomotion - Stop / Destroy Agent")
    void Ck_GymCrowd_Loco_Stop()
    {
        if (HasAuthority() == false) { return; }

        if (_AgentValid == false || ck::Is_NOT_Valid(_Agent))
        {
            ck::Trace("Locomotion gym: no agent to stop");
            return;
        }

        FCk_Handle GenericAgent = _Agent;
        utils_entity_lifetime::Request_DestroyEntity(GenericAgent);
        _AgentValid = false;

        ck::Trace("Locomotion gym: agent destroyed");
    }
}
