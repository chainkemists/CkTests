// --------------------------------------------------------------------------------------------------------------------
// VoxelNav Stress Gym — 400 flying CrowdAgents cross a Jolt-baked central wall.
//
// The 20x20 lattice deliberately crosses both Y and Z: this is one provider/bake and one movement
// episode with a dense population, rather than 400 copies of the two-agent presentation gym.
// Planned paths and agent-body drawing remain OFF because either turns this into a debug-draw test.
// --------------------------------------------------------------------------------------------------------------------

class ACk_VoxelNavGym_Stress_PlayerController : ACk_Gym_Base_PlayerController
{
    private const int32 k_Columns = 20;
    private const int32 k_Rows = 20;
    private const int32 k_AgentCount = k_Columns * k_Rows;

    private const float k_AgentRadius = 42.0f;
    private const float k_AgentHeight = 192.0f;
    private const float k_LatticeSpacingUu = 200.0f;
    private const float k_CellSizeUu = 100.0f;
    private const float k_DrawIntervalSec = 0.5f;

    private const FVector k_VolumeMin = FVector(-3400.0, -3200.0, -100.0);
    private const FVector k_VolumeMax = FVector( 3400.0,  3200.0, 4500.0);
    private const FVector k_ViewLocation = FVector(4300.0, 0.0, 2600.0);
    private const FRotator k_ViewRotation = FRotator(-12.0, 180.0, 0.0);
    private const FLinearColor k_VolumeColor = FLinearColor(0.35, 0.35, 0.45, 1.0);
    private const FLinearColor k_StatusColor = FLinearColor(0.15, 0.9, 1.0, 1.0);

    private FCk_Handle _PcEntity;
    private FCk_Handle_VoxelNavVolume _Volume;
    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private bool _GoalsAreOutbound = true;
    private int32 _ReachedCount = 0;
    private int32 _FailedCount = 0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"VoxelNavStressFlying400");
        Station.AutoSize = true;
        Station.Transform = FTransform(FRotator(0.0, 180.0, 0.0), FVector(4600.0, 0.0, 0.0), FVector::OneVector);
        Station.Title = FText::FromString("VoxelNav Stress — Flying 400");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("400 FLYING CrowdAgents launch from a 20x20 Y/Z\nlattice. All cross one Jolt-backed voxel volume\naround or above its central wall. The display\nreports spawned, reached, and failed totals."));
        Description.Add(FText::FromString("Ck_GymVoxelNavStress_Restart starts a fresh\n400-agent episode on the existing bake.\nCk_GymVoxelNavStress_Reverse sends the current\npopulation back through the wall."));
        Description.Add(FText::FromString("Profile with stat CkCrowd, stat CkAStar, and\nstat CkJolt. Planned paths and agent-body drawing\nare OFF to avoid measuring debug rendering.\nEnable either only for a small diagnostic repro."));
        Station.Description = Description;
        Stations.Add(Station);
        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _PcEntity = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_PcEntity))
        {
            ck::voxelnav::Warning("VoxelNav stress gym: PC entity invalid; cannot start");
            return;
        }

        // These CVars persist in editor ini files. Explicitly disable the high-cardinality draw modes.
        System::ExecuteConsoleCommand("ck.Crowd.DrawPlannedPaths 0");
        System::ExecuteConsoleCommand("ck.Crowd.Debug.AgentBody 0");

        if (DoSpawnAndBakeCentralWall() == false)
        { return; }

        auto VolumeEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        if (ck::Is_NOT_Valid(VolumeEntity))
        {
            ck::voxelnav::Warning("VoxelNav stress gym: volume entity creation failed; no agents spawned");
            return;
        }
        VolumeEntity.Request_OverrideToSelf();

        auto Params = FCk_Fragment_VoxelNavVolume_ParamsData(FBox(k_VolumeMin, k_VolumeMax), k_CellSizeUu);
        Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        Params.Set_ClearanceUu(k_AgentRadius);
        _Volume = utils_voxel_nav_volume::Add(VolumeEntity, Params);

        if (ck::Is_NOT_Valid(_Volume))
        {
            utils_entity_lifetime::Request_DestroyEntity(VolumeEntity);
            ck::voxelnav::Warning("VoxelNav stress gym: volume composition failed; no agents spawned");
            return;
        }

        utils_voxel_nav_volume::Request_Build(_Volume, FCk_Request_VoxelNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));

        auto TickerParams = FCk_Timer_Spec(FCk_Time(k_DrawIntervalSec));
        TickerParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Ticker = utils_timer::Add(_PcEntity, TickerParams);
        if (ck::IsValid(Ticker))
        { Ticker.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnDrawTick")); }
        else
        { ck::voxelnav::Warning("VoxelNav stress gym: status ticker composition failed"); }

        DoBringPlayerToViewpoint();
        ck::voxelnav::Log("VoxelNav stress gym: Jolt-backed volume bake requested; 400 agents wait for completion");
    }

    private bool DoSpawnAndBakeCentralWall()
    {
        // The 5000cm-wide, 3600cm-high wall leaves deterministic side and overhead routes inside
        // the baked volume; a direct X-only path cannot cross it.
        auto Wall = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, FVector(0.0, 0.0, 1800.0)));
        if (ck::Is_NOT_Valid(Wall))
        {
            ck::voxelnav::Warning("VoxelNav stress gym: failed to spawn central wall");
            return false;
        }

        Wall.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        auto Cube = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (Cube == nullptr)
        {
            ck::voxelnav::Warning("VoxelNav stress gym: failed to load /Engine/BasicShapes/Cube.Cube");
            return false;
        }

        Wall.StaticMeshComponent.SetStaticMesh(Cube);
        Wall.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");
        Wall.SetActorScale3D(FVector(1.0, 25.0, 36.0));

        if (utils_jolt_static_world::Request_BakeActor(Wall) == 0)
        {
            ck::voxelnav::Warning("VoxelNav stress gym: central wall baked 0 Jolt bodies; gym aborted");
            return false;
        }
        return true;
    }

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (InResult != ECk_Request_OperationResult::Succeeded || ck::Is_NOT_Valid(_Volume))
        {
            ck::voxelnav::Warning(f"VoxelNav stress gym: bake did not succeed ({InResult}); no agents spawned");
            return;
        }
        DoSpawnAgentsAndMove();
    }

    private void DoSpawnAgentsAndMove()
    {
        DoDestroyAgents();
        _GoalsAreOutbound = true;
        _ReachedCount = 0;
        _FailedCount = 0;

        for (int32 Row = 0; Row < k_Rows; ++Row)
        {
            for (int32 Column = 0; Column < k_Columns; ++Column)
            {
                auto Agent = DoSpawnAgent(DoGetSpawnLocation(Row, Column));
                if (ck::Is_NOT_Valid(Agent))
                {
                    ck::voxelnav::Warning("VoxelNav stress gym: agent composition failed; stopping before a partial population is published");
                    DoDestroyAgents();
                    return;
                }
                _Agents.Add(Agent);
            }
        }

        if (_Agents.Num() != k_AgentCount)
        {
            ck::voxelnav::Warning("VoxelNav stress gym: unexpected population count; no movement issued");
            DoDestroyAgents();
            return;
        }

        DoIssueMoveRequests();
    }

    private FCk_Handle_CrowdAgent DoSpawnAgent(FVector InSpawn)
    {
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        if (ck::Is_NOT_Valid(AgentEntity))
        { return utils_crowd_agent::Get_InvalidHandle(); }

        auto Transform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(Transform))
        {
            utils_entity_lifetime::Request_DestroyEntity(AgentEntity);
            return utils_crowd_agent::Get_InvalidHandle();
        }
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(k_AgentRadius, k_AgentHeight);
        Params.Set_AgentMode(ECk_CrowdAgent_Mode::Flying);
        auto Agent = utils_crowd_agent::Add(Transform, Params);
        if (ck::Is_NOT_Valid(Agent))
        {
            utils_entity_lifetime::Request_DestroyEntity(AgentEntity);
            return utils_crowd_agent::Get_InvalidHandle();
        }

        auto VelocityHandle = utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        auto AccelerationHandle = utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(VelocityHandle) || ck::Is_NOT_Valid(AccelerationHandle))
        {
            utils_entity_lifetime::Request_DestroyEntity(AgentEntity);
            return utils_crowd_agent::Get_InvalidHandle();
        }
        utils_euler_integrator::Request_Start(AgentEntity);

        auto Path = utils_voxel_nav_path::Add(FCk_Handle(Agent), FCk_Fragment_VoxelNavPath_ParamsData(k_AgentRadius));
        if (ck::Is_NOT_Valid(Path))
        {
            utils_entity_lifetime::Request_DestroyEntity(AgentEntity);
            return utils_crowd_agent::Get_InvalidHandle();
        }
        auto ConfiguredPath = utils_voxel_nav_path::Request_SetVolume(Path, _Volume);
        if (ck::Is_NOT_Valid(ConfiguredPath))
        {
            utils_entity_lifetime::Request_DestroyEntity(AgentEntity);
            return utils_crowd_agent::Get_InvalidHandle();
        }

        utils_crowd_agent::BindTo_OnGoalReached(Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnAgentGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnAgentGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        return Agent;
    }

    private FVector DoGetSpawnLocation(int32 InRow, int32 InColumn)
    {
        return FVector(-2700.0,
            -1900.0 + InColumn * k_LatticeSpacingUu,
             250.0 + InRow * k_LatticeSpacingUu);
    }

    private FVector DoGetGoalLocation(FCk_Handle_CrowdAgent InAgent)
    {
        auto Transform = utils_transform::DoCastChecked(FCk_Handle(InAgent));
        auto Current = utils_transform::Get_EntityCurrentLocation(Transform);
        return FVector(_GoalsAreOutbound ? 2700.0 : -2700.0, -Current.Y, Current.Z);
    }

    private void DoIssueMoveRequests()
    {
        for (int32 Index = 0; Index < _Agents.Num(); ++Index)
        {
            auto Agent = _Agents[Index];
            if (ck::Is_NOT_Valid(Agent))
            { continue; }
            utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(DoGetGoalLocation(Agent)));
        }
    }

    private void DoDestroyAgents()
    {
        for (int32 Index = 0; Index < _Agents.Num(); ++Index)
        {
            if (ck::IsValid(_Agents[Index]))
            { utils_entity_lifetime::Request_DestroyEntity(_Agents[Index]); }
        }
        _Agents.Empty();
    }

    private void DoBringPlayerToViewpoint()
    {
        auto Pawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(Pawn))
        { return; }
        Pawn.SetActorLocation(k_ViewLocation);
        SetControlRotation(k_ViewRotation);
    }

    UFUNCTION()
    private void OnDrawTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const float DrawSeconds = 0.55f;
        const auto Center = (k_VolumeMin + k_VolumeMax) * 0.5;
        const auto Extent = (k_VolumeMax - k_VolumeMin) * 0.5;
        utils_debug_draw::DrawDebugBox(Center, Extent, k_VolumeColor, FRotator::ZeroRotator, DrawSeconds, 1.0f);

        auto Status = f"VoxelNav stress: spawned {_Agents.Num()}/{k_AgentCount}  reached {_ReachedCount}  failed {_FailedCount}";
        if (ck::IsValid(_Volume) && utils_voxel_nav_volume::Get_IsBuilt(_Volume) == false)
        { Status = f"VoxelNav stress: baking {utils_voxel_nav_volume::Get_BuildProgress(_Volume)}  {Status}"; }
        utils_debug_draw::DrawDebugString(FVector(0.0, 0.0, 4300.0), Status, k_StatusColor, DrawSeconds);
    }

    UFUNCTION()
    void OnAgentGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (ck::IsValid(InAgent))
        { ++_ReachedCount; }
    }

    UFUNCTION()
    void OnAgentGoalFailed(FCk_Handle_CrowdAgent InAgent)
    {
        if (ck::IsValid(InAgent))
        { ++_FailedCount; }
    }

    UFUNCTION(Exec, DisplayName="VoxelNav Stress - Restart Flying 400")
    void Ck_GymVoxelNavStress_Restart()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_Volume) || utils_voxel_nav_volume::Get_IsBuilt(_Volume) == false)
        { return; }
        DoSpawnAgentsAndMove();
    }

    UFUNCTION(Exec, DisplayName="VoxelNav Stress - Reverse Flying 400")
    void Ck_GymVoxelNavStress_Reverse()
    {
        if (HasAuthority() == false || _Agents.Num() != k_AgentCount)
        { return; }
        _GoalsAreOutbound = !_GoalsAreOutbound;
        _ReachedCount = 0;
        _FailedCount = 0;
        DoIssueMoveRequests();
    }
}
