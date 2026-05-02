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
            Station.Title = FText::FromString("LOCOMOTION (2A+2B+2C+2D)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Console: Spawn / RequestPath / PrintPos / PrintDesired / PrintYaw / Stop"));
            Description.Add(FText::FromString("Spawn -> cyan capsule (agent body) + orange cone (current facing)"));
            Description.Add(FText::FromString("RequestPath -> path waypoints; agent walks + cone rotates to track yaw"));
            Description.Add(FText::FromString("PrintYaw -> log current vs target yaw in degrees (FaceAngle progress)"));
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
            ck::crowd::Warning("Locomotion gym: station handle invalid at StartGym");
            return;
        }

        ck::crowd::Log("Locomotion gym started. Run Ck_GymCrowd_Loco_Spawn from the console.");
    }

    private void SpawnFloor()
    {
        // 2000cm x 2000cm flat cube centered at world origin (Z=0). Cube mesh is 100cm tall scaled
        // by 0.5 → 50cm tall, so the floor extends from Z=-25 to Z=+25. Stations sit with their
        // actor-Z=0 at world Z=0 (DefaultStationGridZ); after the Build_Alcove fix the station's
        // floor slab extends from actor-Z=-FT to 0, which lands inside the gym floor's volume —
        // visually flush with the gym floor's lower half rather than poking up through it.
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(20.0, 20.0, 0.5);

        auto Floor = SpawnActor(ACk_CrowdGym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::crowd::Warning("Locomotion gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);

        ck::crowd::Log(f"Locomotion gym: floor spawned at {FloorLocation} scale={FloorScale}");
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
            ck::crowd::Warning("Locomotion gym: station handle invalid; cannot spawn");
            return;
        }

        if (_AgentValid)
        {
            ck::crowd::Warning("Locomotion gym: an agent already exists. Run Ck_GymCrowd_Loco_Stop first.");
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

        // Velocity feature with zero starting velocity. Sub-task 2C's velocity-bridge processor
        // overwrites _CurrentVelocity from FFragment_CrowdAgent_DesiredVelocity every frame, so any
        // non-zero starting value would be wiped on the first tick anyway. The bridge is the source
        // of motion now; the agent stays put until a path request lands.
        const auto VelocityStart = FVector::ZeroVector;
        auto VelocityParams = FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, VelocityStart);
        utils_velocity::Add(GenericAgent, VelocityParams, ECk_Replication::DoesNotReplicate);

        // Acceleration feature with zero acceleration — required by the integrator's view.
        auto AccelParams = FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector);
        utils_acceleration::Add(GenericAgent, AccelParams, ECk_Replication::DoesNotReplicate);

        // Start the integrator so FFragment_EulerIntegrator_Current + FTag_EulerIntegrator_NeedsUpdate land
        // on the entity. The view of FProcessor_CrowdAgent_ApplyOffset is then satisfied each tick.
        utils_euler_integrator::Request_Start(GenericAgent);

        // Visualize the agent: cyan capsule sized to the agent's _Radius / _Height.
        //
        // We can't Add_Capsule on the agent itself — it does Add<FFragment_Transform>, not AddOrGet,
        // and the agent already has Transform from utils_transform::Add above → ENSURE.
        //
        // Instead, Create_Capsule spawns a SEPARATE child entity owned by the agent (so it
        // cascade-destroys with the agent), then SceneNode-parent the child's Transform to the
        // agent's Transform with a vertical offset of HalfHeight. The agent's Transform location is
        // its FEET (NPC convention); the capsule's local origin is its CENTER, so the offset puts
        // the capsule's bottom at the agent's feet rather than HalfHeight below them. SceneNode
        // propagation makes the capsule track the agent's apply-offset moves automatically — no
        // per-tick sync.
        const auto AgentColor = FLinearColor(0.42, 0.85, 1.0, 0.6);
        auto CapsuleHandle = utils_pmg_basic_shapes::Create_Capsule(
            GenericAgent,
            FTransform::Identity,
            42.0f,           // radius matches agent params (_Radius default)
            96.0f,           // half-height matches agent params (_Height / 2)
            16,              // segments
            8,               // rings
            ECk_Plane_Axis::XY,
            AgentColor,
            true,            // wireframe overlay
            2.0f,            // line thickness
            -1.0f);          // -1 = persist until the agent (and child) is destroyed

        FCk_Handle CapsuleGeneric = CapsuleHandle;
        auto CapsuleXform = utils_transform::DoCastChecked(CapsuleGeneric);
        auto AgentXform = utils_transform::DoCastChecked(GenericAgent);
        const auto CapsuleLocalOffset = FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 96.0), FVector::OneVector);
        utils_scene_node::Add(CapsuleXform, AgentXform, CapsuleLocalOffset);

        // Forward-direction indicator (Sub-task 2D): small orange cone in front of the capsule,
        // SceneNode-parented to the agent's Transform so it rotates with the FaceAngle processor's
        // yaw lerp. PMG's ECk_Plane_Axis::YZ rotates the cone's apex to point along -X local (per
        // the AxisRotation in CkPmg_Processor_BasicShapes.cpp), which is BACKWARD from agent's
        // forward. So we keep the default XY axis (apex along +Z = up in cone-local) and tilt the
        // cone forward via Pitch=-90 in the SceneNode local rotation: this maps cone-local +Z to
        // parent-local +X so the apex points where the agent is facing.
        const auto ForwardConeColor = FLinearColor(1.0, 0.55, 0.15, 0.7);
        auto ConeHandle = utils_pmg_basic_shapes::Create_Cone(
            GenericAgent,
            FTransform::Identity,
            15.0f,           // radius
            60.0f,           // height — small enough not to overlap the capsule
            12,              // segments
            ECk_Plane_Axis::XY,
            ForwardConeColor,
            true,
            1.5f,
            -1.0f);          // persist with the agent

        FCk_Handle ConeGeneric = ConeHandle;
        auto ConeXform = utils_transform::DoCastChecked(ConeGeneric);
        const auto ConeLocalOffset = FTransform(FRotator(-90.0, 0.0, 0.0), FVector(60.0, 0.0, 96.0), FVector::OneVector);
        utils_scene_node::Add(ConeXform, AgentXform, ConeLocalOffset);

        // Bind OnPathReady on the agent so we can draw the path overlay when navigation lands the result.
        utils_nav::BindTo_OnPathReady(GenericAgent,
            FCk_Delegate_Nav_OnPathReady(this, n"OnAgentPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        _AgentValid = true;

        ck::crowd::Log(f"Locomotion gym: spawned agent at {_SpawnLocation} (velocity={VelocityStart}, stationary until RequestPath)");
    }

    UFUNCTION()
    void OnAgentPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        // Draw a marker at each waypoint with PMG. Fire-and-forget; the spheres auto-destroy after 30s.
        // Lines between waypoints are drawn via UCk_Utils_DebugDraw_UE since PMG covers filled shapes only.
        const auto Waypoints = InResult.Get_Waypoints();
        const auto Color = FLinearColor(0.42, 0.85, 1.0, 0.7);
        const auto Duration = 30.0f;
        const auto SphereRadius = 15.0f;

        for (int32 i = 0; i < Waypoints.Num(); ++i)
        {
            utils_pmg_basic_shapes::DrawFilledSphere(
                Waypoints[i],
                SphereRadius,
                12,            // segments
                12,            // rings
                Color,
                true,          // wireframe overlay
                2.0f,          // line thickness
                ECk_Plane_Axis::XY,
                Duration);
        }

        for (int32 i = 0; i < Waypoints.Num() - 1; ++i)
        {
            UCk_Utils_DebugDraw_UE::DrawDebugLine(Waypoints[i], Waypoints[i + 1], Color, Duration, 4.0f);
        }

        ck::crowd::Log(f"Locomotion gym: OnPathReady — waypoints={Waypoints.Num()}, drew overlay (decays in {Duration}s)");
    }

    UFUNCTION(Exec, DisplayName="Crowd Locomotion - Print Position")
    void Ck_GymCrowd_Loco_PrintPos()
    {
        if (_AgentValid == false || ck::Is_NOT_Valid(_Agent))
        {
            ck::crowd::Log("Locomotion gym: no agent. Run Ck_GymCrowd_Loco_Spawn first.");
            return;
        }

        FCk_Handle GenericAgent = _Agent;
        auto TransformHandle = utils_transform::DoCastChecked(GenericAgent);
        if (ck::Is_NOT_Valid(TransformHandle))
        {
            ck::crowd::Warning("Locomotion gym: agent has no Transform feature — cannot read position");
            return;
        }

        const auto CurrentLoc = utils_transform::Get_EntityCurrentLocation(TransformHandle);
        const auto Delta = CurrentLoc - _SpawnLocation;

        ck::crowd::Log(f"Locomotion gym: pos={CurrentLoc}  delta_from_spawn={Delta}  (stationary until RequestPath; up to 240 cm/s after)");

        // Drop a small cyan capsule at the agent's current position. Spam PrintPos to leave a
        // breadcrumb trail along the walk. Offset upward by HalfHeight so the capsule's bottom sits
        // at the agent's feet (CurrentLoc) rather than HalfHeight below them.
        const auto TrailColor = FLinearColor(0.42, 0.85, 1.0, 0.4);
        const auto TrailHalfHeight = 48.0f;
        utils_pmg_basic_shapes::DrawFilledCapsule(
            CurrentLoc + FVector(0.0, 0.0, TrailHalfHeight),
            20.0f,           // radius — smaller than spawn marker to distinguish trail vs origin
            TrailHalfHeight, // half-height — half of spawn marker's
            12,              // segments
            6,               // rings
            TrailColor,
            true,
            1.5f,
            ECk_Plane_Axis::XY,
            30.0f);          // 30s decay
    }

    UFUNCTION(Exec, DisplayName="Crowd Locomotion - Request Path To -X 800cm")
    void Ck_GymCrowd_Loco_RequestPath()
    {
        if (HasAuthority() == false) { return; }
        if (_AgentValid == false || ck::Is_NOT_Valid(_Agent))
        {
            ck::crowd::Log("Locomotion gym: no agent. Run Ck_GymCrowd_Loco_Spawn first.");
            return;
        }

        // Stations face -X (rotated 180° in Request_ApplyDefaultGridLayout so they face the player
        // who spawns at +X). The path target is chosen forward of the station — i.e., negative X
        // from the station origin — so the agent walks out toward the player camera and the path
        // overlay is visible in the foreground rather than going through the station's back wall.
        const auto Target = _SpawnLocation + FVector(-800.0, 0.0, -100.0);

        FCk_Handle GenericAgent = _Agent;
        auto Request = FCk_Request_Nav_FindPath(Target);
        utils_nav::Request_FindPath(GenericAgent, Request);

        ck::crowd::Log(f"Locomotion gym: enqueued FindPath -> {Target}");
    }

    UFUNCTION(Exec, DisplayName="Crowd Locomotion - Print Desired Velocity")
    void Ck_GymCrowd_Loco_PrintDesired()
    {
        if (_AgentValid == false || ck::Is_NOT_Valid(_Agent))
        {
            ck::crowd::Log("Locomotion gym: no agent. Run Ck_GymCrowd_Loco_Spawn first.");
            return;
        }

        const auto Desired = utils_crowd_agent::Get_DesiredVelocity(_Agent);
        ck::crowd::Log(f"Locomotion gym: desired_velocity={Desired}  speed={Desired.Size()} cm/s");
    }

    UFUNCTION(Exec, DisplayName="Crowd Locomotion - Print Yaw (current vs target)")
    void Ck_GymCrowd_Loco_PrintYaw()
    {
        if (_AgentValid == false || ck::Is_NOT_Valid(_Agent))
        {
            ck::crowd::Log("Locomotion gym: no agent. Run Ck_GymCrowd_Loco_Spawn first.");
            return;
        }

        FCk_Handle GenericAgent = _Agent;
        auto TransformHandle = utils_transform::DoCastChecked(GenericAgent);
        if (ck::Is_NOT_Valid(TransformHandle))
        {
            ck::crowd::Warning("Locomotion gym: agent has no Transform feature — cannot read rotation");
            return;
        }

        const auto CurrentRot = utils_transform::Get_EntityCurrentRotation(TransformHandle);
        const auto TargetYaw = utils_crowd_agent::Get_TargetYawDegrees(_Agent);
        ck::crowd::Log(f"Locomotion gym: current_yaw={CurrentRot.Yaw}°  target_yaw={TargetYaw}°  (lerping at MaxTurnRate=4 rad/s)");
    }

    UFUNCTION(Exec, DisplayName="Crowd Locomotion - Stop / Destroy Agent")
    void Ck_GymCrowd_Loco_Stop()
    {
        if (HasAuthority() == false) { return; }

        if (_AgentValid == false || ck::Is_NOT_Valid(_Agent))
        {
            ck::crowd::Log("Locomotion gym: no agent to stop");
            return;
        }

        FCk_Handle GenericAgent = _Agent;
        utils_entity_lifetime::Request_DestroyEntity(GenericAgent);
        _AgentValid = false;

        ck::crowd::Log("Locomotion gym: agent destroyed");
    }
}
