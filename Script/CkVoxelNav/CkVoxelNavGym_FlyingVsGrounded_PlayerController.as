class ACk_VoxelNavGym_FlyingVsGrounded_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- Scene constants (every position is KNOWN; nothing is looked up at runtime) ---------------

    // Z SCALE MUST BE >= 0.5 — thinner slabs bake to zero walkable tiles. The floor's walkable
    // surface sits at the actor origin, so the slab hangs below Z=0 and agents walk on Z=0.
    private const FVector k_FloorLocation = FVector(0.0, 0.0, 0.0);
    private const FVector k_FloorScale    = FVector(30.0, 30.0, 0.5);

    // /Engine/BasicShapes/Cube is a 100uu cube CENTRED on its own origin, so a Z scale of 12 spans
    // 1200uu and the actor must sit at Z=600 for the wall to run from the floor (0) up to 1200.
    // Footprint: X +/-100, Y from -850 to +50 — it straddles the flying lane and clears the other.
    private const FVector k_WallLocation = FVector(0.0, -400.0, 600.0);
    private const FVector k_WallScale    = FVector(2.0, 9.0, 12.0);

    // Flying lane Y=-400 runs into the wall; grounded lane Y=+400 is clear of it. Both start and end
    // 1000uu up, so the grounded agent's goal hangs in the air above the floor it is clamped to.
    private const FVector k_FlyerSpawn      = FVector(-1000.0, -400.0, 1000.0);
    private const FVector k_FlyerGoal       = FVector( 1000.0, -400.0, 1000.0);
    private const FVector k_GroundedSpawn   = FVector(-1000.0,  400.0, 1000.0);
    private const FVector k_GroundedGoal    = FVector( 1000.0,  400.0, 1000.0);

    private const FVector k_VolumeMin = FVector(-1600.0, -1600.0, -100.0);
    private const FVector k_VolumeMax = FVector( 1600.0,  1600.0, 1600.0);
    private const float   k_FinestCellSizeUu = 50.0;

    private const float k_AgentRadius = 42.0;
    private const float k_AgentHeight = 192.0;

    private const FLinearColor k_FlyerColor    = FLinearColor(0.15, 0.9, 1.0, 1.0);
    private const FLinearColor k_GroundedColor = FLinearColor(1.0, 0.55, 0.1, 1.0);
    private const FLinearColor k_VolumeColor   = FLinearColor(0.35, 0.35, 0.45, 1.0);

    private const FVector  k_PlayerViewLocation = FVector(2400.0, 0.0, 1000.0);
    private const FRotator k_PlayerViewRotation = FRotator(-15.0, 180.0, 0.0);

    private const float k_TickIntervalSec = 0.1f;
    private const float k_LabelZOffset    = 120.0f;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FCk_Handle_VoxelNavVolume _Volume;
    private FCk_Handle_CrowdAgent _FlyerAgent;
    private FCk_Handle_CrowdAgent _GroundedAgent;

    private bool _GoalsAreOutbound = true;
    private FVector _FlyerGoal = FVector::ZeroVector;
    private FVector _GroundedGoal = FVector::ZeroVector;

    // ---- Station ---------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"VoxelNavFlyingVsGrounded");
        Station.AutoSize = true;
        Station.Transform = FTransform(FRotator(0.0, 180.0, 0.0), FVector(2600.0, 0.0, 0.0), FVector::OneVector);
        Station.Title = FText::FromString("VoxelNav — Flying vs Grounded");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Two agents spawn 1000cm up on the same baked voxel volume and differ only in _AgentMode. The FLYING one (cyan, Y=-400) climbs over the 1200cm wall in its lane with a visible nose-up/nose-down pitch and holds its altitude to the goal."));
        Description.Add(FText::FromString("The GROUNDED one (orange, Y=+400) drops to the level's navmesh within a second and walks the floor flat for the rest of the run, then parks BENEATH its elevated goal — that is the navmesh constraint winning, not a pathing failure."));
        Description.Add(FText::FromString("Fail signatures: flyer frozen at spawn = its displacement drain is missing; flyer sinking to the floor = it is still inside ConstrainToNavmesh's view; flyer rolling or banking = its rotation is being composed as a delta instead of written absolutely."));
        Description.Add(FText::FromString("Ck_GymVoxelNav_Restart\nCk_GymVoxelNav_ReturnTrip"));
        Station.Description = Description;

        Stations.Add(Station);
        return Stations;
    }

    // ---- Startup ---------------------------------------------------------------------------------

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _PcEntity = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_PcEntity))
        {
            ck::voxelnav::Warning("VoxelNav gym: PC entity invalid; cannot start");
            return;
        }

        _GoalsAreOutbound = true;
        _FlyerGoal = k_FlyerGoal;
        _GroundedGoal = k_GroundedGoal;

        // Both toggles persist in the editor ini, so force them on entry: the planned polyline is
        // what shows the flyer's route is airborne along its whole length, and the agent body is
        // what shows its pitch.
        System::ExecuteConsoleCommand("ck.Crowd.DrawPlannedPaths 1");
        System::ExecuteConsoleCommand("ck.Crowd.Debug.AgentBody 1");

        if (DoSpawnFloor() == false)
        { return; }

        if (DoSpawnWall() == false)
        { return; }

        // Recast has to see the runtime floor and wall before the grounded agent asks for a route.
        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);

        // The volume's build resolves its UWorld by walking lifetime ownership, so an unparented
        // entity has no world to voxelize.
        auto VolumeEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        VolumeEntity.Request_OverrideToSelf();

        auto VolumeParams = FCk_Fragment_VoxelNavVolume_ParamsData(
            FBox(k_VolumeMin, k_VolumeMax), k_FinestCellSizeUu);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        VolumeParams.Set_ClearanceUu(k_AgentRadius);

        _Volume = utils_voxel_nav_volume::Add(VolumeEntity, VolumeParams);

        // The bake spans many frames; this delegate fires when it FINISHES, not when it is accepted.
        utils_voxel_nav_volume::Request_Build(_Volume, FCk_Request_VoxelNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));

        auto TickerParams = FCk_Timer_Spec(FCk_Time(k_TickIntervalSec));
        TickerParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Ticker = utils_timer::Add(_PcEntity, TickerParams);
        Ticker.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnDrawTick"));

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        ck::voxelnav::Log("VoxelNav gym: volume bake requested — agents spawn when it completes");
    }

    private bool DoSpawnFloor()
    {
        auto Floor = SpawnActor(ACk_Gym_Floor, k_FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::voxelnav::Warning("VoxelNav gym: failed to spawn floor actor");
            return false;
        }
        Floor.SetActorScale3D(k_FloorScale);
        FinishSpawningActor(Floor);
        return true;
    }

    private bool DoSpawnWall()
    {
        auto WallActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, k_WallLocation));
        if (ck::Is_NOT_Valid(WallActor))
        {
            ck::voxelnav::Warning("VoxelNav gym: failed to spawn the wall actor");
            return false;
        }

        // A runtime-spawned AStaticMeshActor must be Movable BEFORE it will accept a mesh.
        WallActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);

        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh == nullptr)
        {
            ck::voxelnav::Warning("VoxelNav gym: failed to load /Engine/BasicShapes/Cube.Cube");
            return false;
        }
        WallActor.StaticMeshComponent.SetStaticMesh(CubeMesh);

        auto WallMaterial = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (WallMaterial != nullptr)
        { WallActor.StaticMeshComponent.SetMaterial(0, WallMaterial); }

        WallActor.SetActorScale3D(k_WallScale);
        WallActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        auto NumBaked = utils_jolt_static_world::Request_BakeActor(WallActor);
        if (NumBaked == 0)
        {
            ck::voxelnav::Warning("VoxelNav gym: the wall baked 0 Jolt bodies — the volume would voxelize it as free space");
            ck::Error("VoxelNav gym: wall bake produced 0 Jolt bodies — gym aborted", n"VoxelNavGym.WallBake", 10.0);
            return false;
        }

        return true;
    }

    private void DoBringPlayerToViewpoint()
    {
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        { return; }

        ViewPawn.SetActorLocation(k_PlayerViewLocation);
        SetControlRotation(k_PlayerViewRotation);
    }

    // Mirrors the gym base's private WaitOneFrame — a one-shot timer on the PC's own entity.
    private void DoWaitOneFrame(FName InCallbackName)
    {
        auto Params = FCk_Timer_Spec(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_PcEntity, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }

    UFUNCTION()
    private void OnViewpointSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        // Retry — the pawn may not have been possessed yet when the gym started.
        DoBringPlayerToViewpoint();
    }

    // ---- Bake completion -------------------------------------------------------------------------

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (InResult != ECk_Request_OperationResult::Succeeded)
        {
            ck::voxelnav::Warning(f"VoxelNav gym: the volume bake did not succeed (got {InResult}) — no agents spawned");
            ck::Error("VoxelNav gym: volume bake failed — no agents spawned", n"VoxelNavGym.Bake", 10.0);
            return;
        }

        DoSpawnAgentsAndMove();
    }

    private void DoSpawnAgentsAndMove()
    {
        _FlyerAgent = DoSpawnAgent(k_FlyerSpawn, ECk_CrowdAgent_Mode::Flying, k_FlyerColor);
        _GroundedAgent = DoSpawnAgent(k_GroundedSpawn, ECk_CrowdAgent_Mode::Grounded, k_GroundedColor);

        DoMoveTo(_FlyerAgent, _FlyerGoal);
        DoMoveTo(_GroundedAgent, _GroundedGoal);
    }

    private FCk_Handle_CrowdAgent DoSpawnAgent(FVector InSpawn, ECk_CrowdAgent_Mode InMode, FLinearColor InColor)
    {
        // The agent is a CHILD of the registry transient, never composed onto it: utils_crowd_agent
        // permits one agent per entity, so composing onto the transient would put both agents on the
        // same entity and make the destroy in Restart target the world transient.
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(k_AgentRadius, k_AgentHeight);
        Params.Set_AgentMode(InMode);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator(0.0, 0.0, 0.0), InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        auto Path = utils_voxel_nav_path::Add(FCk_Handle(Agent), FCk_Fragment_VoxelNavPath_ParamsData(k_AgentRadius));
        utils_voxel_nav_path::Request_SetVolume(Path, _Volume);

        utils_crowd_agent::Set_DebugColor(Agent, InColor);

        utils_crowd_agent::BindTo_OnGoalReached(Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnAgentGoalReached"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        return Agent;
    }

    private void DoMoveTo(FCk_Handle_CrowdAgent InAgent, FVector InGoal)
    {
        if (ck::Is_NOT_Valid(InAgent))
        { return; }

        utils_crowd_agent::Request_MoveTo(InAgent, FCk_Request_CrowdAgent_MoveTo(InGoal));
    }

    private void DoDestroyAgents()
    {
        if (ck::IsValid(_FlyerAgent))
        { utils_entity_lifetime::Request_DestroyEntity(_FlyerAgent); }
        if (ck::IsValid(_GroundedAgent))
        { utils_entity_lifetime::Request_DestroyEntity(_GroundedAgent); }

        _FlyerAgent = utils_crowd_agent::Get_InvalidHandle();
        _GroundedAgent = utils_crowd_agent::Get_InvalidHandle();
    }

    // ---- Per-tick draw ---------------------------------------------------------------------------

    UFUNCTION()
    private void OnDrawTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        // A local, not a class const: AS class-scope const floats reach float32 params as float64
        // literals and warn on every call site.
        const float DrawSeconds = 0.12f;

        const auto VolumeCenter = (k_VolumeMin + k_VolumeMax) * 0.5;
        const auto VolumeExtent = (k_VolumeMax - k_VolumeMin) * 0.5;
        utils_debug_draw::DrawDebugBox(VolumeCenter, VolumeExtent, k_VolumeColor,
            FRotator::ZeroRotator, DrawSeconds, 1.0f);

        utils_debug_draw::DrawDebugSphere(_FlyerGoal, 60.0f, 16, k_FlyerColor, DrawSeconds, 2.0f);
        utils_debug_draw::DrawDebugSphere(_GroundedGoal, 60.0f, 16, k_GroundedColor, DrawSeconds, 2.0f);

        if (ck::IsValid(_Volume) && utils_voxel_nav_volume::Get_IsBuilt(_Volume) == false)
        {
            utils_debug_draw::DrawDebugString(FVector(0.0, 0.0, 500.0),
                f"Baking voxel volume… {utils_voxel_nav_volume::Get_BuildProgress(_Volume)}",
                FLinearColor(1.0f, 1.0f, 1.0f, 1.0f), DrawSeconds);
        }

        if (ck::IsValid(_FlyerAgent))
        {
            utils_debug_draw::DrawDebugString(DoGet_LabelLocation(_FlyerAgent),
                f"FLYING  pitch {utils_crowd_agent::Get_TargetPitchDegrees(_FlyerAgent)}  {utils_crowd_agent::Get_MovementState(_FlyerAgent)}",
                k_FlyerColor, DrawSeconds);
        }

        if (ck::IsValid(_GroundedAgent))
        {
            utils_debug_draw::DrawDebugString(DoGet_LabelLocation(_GroundedAgent),
                f"GROUNDED  {utils_crowd_agent::Get_MovementState(_GroundedAgent)}",
                k_GroundedColor, DrawSeconds);
        }
    }

    private FVector DoGet_LabelLocation(FCk_Handle_CrowdAgent InAgent)
    {
        const auto AgentTransform = utils_transform::DoCastChecked(FCk_Handle(InAgent));
        return utils_transform::Get_EntityCurrentLocation(AgentTransform) + FVector(0.0, 0.0, k_LabelZOffset);
    }

    // ---- Signal handlers -------------------------------------------------------------------------

    UFUNCTION()
    void OnAgentGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (InAgent == _FlyerAgent)
        {
            ck::Trace("VoxelNav gym: the FLYING agent reached its goal");
            return;
        }

        if (InAgent == _GroundedAgent)
        {
            ck::Trace("VoxelNav gym: the GROUNDED agent reached its goal");
            return;
        }

        ck::Trace("VoxelNav gym: an unrecognised agent reached its goal");
    }

    // ---- Console ---------------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="VoxelNav Flying vs Grounded - Restart Agents")
    void Ck_GymVoxelNav_Restart()
    {
        if (HasAuthority() == false)
        { return; }

        DoDestroyAgents();
        DoSpawnAgentsAndMove();
        ck::voxelnav::Log("VoxelNav gym: agents restarted against the existing volume");
    }

    UFUNCTION(Exec, DisplayName="VoxelNav Flying vs Grounded - Return Trip")
    void Ck_GymVoxelNav_ReturnTrip()
    {
        if (HasAuthority() == false)
        { return; }

        _GoalsAreOutbound = !_GoalsAreOutbound;
        _FlyerGoal = _GoalsAreOutbound ? k_FlyerGoal : k_FlyerSpawn;
        _GroundedGoal = _GoalsAreOutbound ? k_GroundedGoal : k_GroundedSpawn;

        DoMoveTo(_FlyerAgent, _FlyerGoal);
        DoMoveTo(_GroundedAgent, _GroundedGoal);
        ck::voxelnav::Log("VoxelNav gym: both agents re-targeted to the opposite end");
    }
}
