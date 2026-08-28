class ACk_CrowdGym_AvoidanceVolume_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _OwnerHandle;
    private FCk_Handle _StationHandle;
    private FCk_Handle _AgentEntity;
    private FCk_Handle _VolumeEntity;
    private FCk_Handle_CrowdAgent _Agent;

    private bool _DrawVolume = true;
    private int32 _ActiveScenario = 0;
    private FString _LastResult = "Not run";

    private const int32 Scenario_None = 0;
    private const int32 Scenario_Baseline = 1;
    private const int32 Scenario_Crossing = 2;
    private const int32 Scenario_Inside = 3;

    private const float32 AgentRadius = 42.0f;
    private const float32 AgentHeight = 192.0f;
    private const float CourseHalfLength = 600.0;
    private const float CourseZ = 100.0;
    private const float VolumeYawDegrees = 35.0;
    private const float VolumeInfluenceRange = 400.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Crowd.AvoidanceVolume");
        Station.Title = FText::FromString("CROWD AVOIDANCE VOLUME");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("1: baseline follows the straight dashed route with no volume."));
        Description.Add(FText::FromString("2: same route; the cyan agent must curve around the yellow box."));
        Description.Add(FText::FromString("3: agent starts inside the box and must escape before reaching the goal."));
        Description.Add(FText::FromString("After the nav rebuild, the planned path must bend around the expanded box."));
        Station.Description = Description;
        Stations.Add(Station);
        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _OwnerHandle = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_OwnerHandle))
        {
            ck::crowd::Warning("Avoidance-volume gym: PlayerController entity is invalid");
            return;
        }

        SpawnFloor();
        _StationHandle = Get_StationHandle("Gym.Crowd.AvoidanceVolume");
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::crowd::Warning("Avoidance-volume gym: station handle is invalid");
            return;
        }

        System::ExecuteConsoleCommand("ck.Crowd.Debug.AgentBody 1");
        utils_nav::Request_NavigationRebuild_ForTesting(_OwnerHandle);
        utils_timer::Create_Tick(_OwnerHandle, FCk_Delegate_Timer(this, n"OnGymTick"));
        ck::crowd::Log("Avoidance-volume gym ready. Press 1 for baseline, 2 for volume crossing, or 3 for inside escape.");
    }

    private void SpawnFloor()
    {
        auto Floor = SpawnActor(ACk_Gym_Floor, FVector::ZeroVector, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::crowd::Warning("Avoidance-volume gym: failed to spawn floor actor");
            return;
        }

        Floor.SetActorScale3D(FVector(30.0, 30.0, 0.5));
        FinishSpawningActor(Floor);
    }

    FString Get_ControlPanelTitle() override
    {
        return "CROWD: AVOIDANCE VOLUME";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("COMPARE THE SAME ROUTE"));
        Rows.Add(CkGym_Control::Numbered(0, "Baseline: no volume", _ActiveScenario == Scenario_Baseline));
        Rows.Add(CkGym_Control::Numbered(1, "Volume: detour around box", _ActiveScenario == Scenario_Crossing));
        Rows.Add(CkGym_Control::Numbered(2, "Inside: escape the box", _ActiveScenario == Scenario_Inside));
        Rows.Add(CkGym_Control::Toggle(EKeys::V, "V", "Volume wireframe", _DrawVolume));
        Rows.Add(CkGym_Control::Action(EKeys::C, "C", "Clear agent and volume"));
        Rows.Add(CkGym_Control::Status("Last result", _LastResult,
            _LastResult == "FAILED" || _LastResult == "VOLUME FAILED" || _LastResult == "AGENT FAILED"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1) { Ck_GymCrowd_AvoidanceVolume_Baseline(); }
        else if (InRowIndex == 2) { Ck_GymCrowd_AvoidanceVolume_Cross(); }
        else if (InRowIndex == 3) { Ck_GymCrowd_AvoidanceVolume_Inside(); }
        else if (InRowIndex == 4) { Ck_GymCrowd_AvoidanceVolume_ToggleDebug(); }
        else if (InRowIndex == 5) { Ck_GymCrowd_AvoidanceVolume_Clear(); }
    }

    UFUNCTION(Exec, DisplayName="Crowd Avoidance Volume - Baseline Without Volume")
    void Ck_GymCrowd_AvoidanceVolume_Baseline()
    {
        if (CanRunScenario() == false)
        { return; }

        ClearEntities();
        _ActiveScenario = Scenario_Baseline;
        _LastResult = "Running baseline";
        if (SpawnAgentAndMove(GetCourseSpawn(), GetCourseGoal(), n"AvoidanceVolumeBaselineAgent") == false)
        {
            _ActiveScenario = Scenario_None;
            _LastResult = "AGENT FAILED";
            return;
        }
        ck::crowd::Log("Avoidance-volume gym: baseline dispatched without a volume");
    }

    UFUNCTION(Exec, DisplayName="Crowd Avoidance Volume - Cross Volume")
    void Ck_GymCrowd_AvoidanceVolume_Cross()
    {
        if (CanRunScenario() == false)
        { return; }

        ClearEntities();
        if (SpawnVolume() == false)
        {
            _ActiveScenario = Scenario_None;
            _LastResult = "VOLUME FAILED";
            return;
        }
        _ActiveScenario = Scenario_Crossing;
        _LastResult = "Running crossing";
        if (SpawnAgentAndMove(GetCourseSpawn(), GetCourseGoal(), n"AvoidanceVolumeCrossingAgent") == false)
        {
            ClearEntities();
            _ActiveScenario = Scenario_None;
            _LastResult = "AGENT FAILED";
            return;
        }
        ck::crowd::Log("Avoidance-volume gym: crossing agent dispatched through the authored volume");
    }

    UFUNCTION(Exec, DisplayName="Crowd Avoidance Volume - Start Inside Volume")
    void Ck_GymCrowd_AvoidanceVolume_Inside()
    {
        if (CanRunScenario() == false)
        { return; }

        ClearEntities();
        if (SpawnVolume() == false)
        {
            _ActiveScenario = Scenario_None;
            _LastResult = "VOLUME FAILED";
            return;
        }
        _ActiveScenario = Scenario_Inside;
        _LastResult = "Running inside escape";
        if (SpawnAgentAndMove(GetVolumeCenter() + FVector(-120.0, 0.0, 0.0),
            GetCourseGoal(), n"AvoidanceVolumeInsideAgent") == false)
        {
            ClearEntities();
            _ActiveScenario = Scenario_None;
            _LastResult = "AGENT FAILED";
            return;
        }
        ck::crowd::Log("Avoidance-volume gym: agent dispatched from inside the authored volume");
    }

    UFUNCTION(Exec, DisplayName="Crowd Avoidance Volume - Toggle Wireframe")
    void Ck_GymCrowd_AvoidanceVolume_ToggleDebug()
    {
        _DrawVolume = !_DrawVolume;
    }

    UFUNCTION(Exec, DisplayName="Crowd Avoidance Volume - Clear")
    void Ck_GymCrowd_AvoidanceVolume_Clear()
    {
        if (HasAuthority() == false)
        { return; }

        ClearEntities();
        _ActiveScenario = Scenario_None;
        _LastResult = "Cleared";
        ck::crowd::Log("Avoidance-volume gym: cleared agent and volume");
    }

    private bool CanRunScenario()
    {
        return HasAuthority() && ck::IsValid(_OwnerHandle) && ck::IsValid(_StationHandle);
    }

    private FVector GetCourseCenter()
    {
        const auto StationTransform = Get_StationAnchorTransform(
            "Gym.Crowd.AvoidanceVolume", ECk_GymStation_Anchor::FootprintCenter);
        return StationTransform.GetLocation() + FVector(-700.0, 0.0, CourseZ);
    }

    private FVector GetCourseSpawn()
    {
        return GetCourseCenter() + FVector(CourseHalfLength, 0.0, 0.0);
    }

    private FVector GetCourseGoal()
    {
        return GetCourseCenter() - FVector(CourseHalfLength, 0.0, 0.0);
    }

    private FVector GetVolumeCenter()
    {
        return GetCourseCenter();
    }

    private FVector GetVolumeHalfExtents()
    {
        return FVector(250.0, 90.0, 100.0);
    }

    private FRotator GetVolumeRotation()
    {
        return FRotator(0.0, VolumeYawDegrees, 0.0);
    }

    private bool SpawnVolume()
    {
        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        _VolumeEntity.Set_DebugName(n"CrowdAvoidanceVolumeGymVolume");

        const auto VolumeTransform = FTransform(GetVolumeRotation(), GetVolumeCenter(), FVector::OneVector);
        auto Transform = utils_transform::Add(_VolumeEntity, VolumeTransform, ECk_Replication::DoesNotReplicate);
        const auto Params = FCk_Fragment_CrowdAvoidanceVolume_ParamsData(
            GetVolumeHalfExtents(), VolumeInfluenceRange);
        const auto Volume = utils_crowd_avoidance_volume::Add(Transform, Params);
        if (ck::Is_NOT_Valid(Volume))
        {
            ck::crowd::Warning("Avoidance-volume gym: failed to compose the volume");
            utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
            _VolumeEntity = FCk_Handle();
            return false;
        }

        return true;
    }

    private bool SpawnAgentAndMove(FVector InSpawn, FVector InGoal, FName InDebugName)
    {
        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        _AgentEntity.Set_DebugName(InDebugName);

        const auto Facing = (InGoal - InSpawn).GetSafeNormal().Rotation();
        const auto TransformValue = FTransform(Facing, InSpawn, FVector::OneVector);
        auto Transform = utils_transform::Add(_AgentEntity, TransformValue, ECk_Replication::DoesNotReplicate);
        _Agent = utils_crowd_agent::Add(Transform, FCk_Fragment_CrowdAgent_ParamsData(AgentRadius, AgentHeight));
        if (ck::Is_NOT_Valid(_Agent))
        {
            ck::crowd::Warning("Avoidance-volume gym: failed to compose the crowd agent");
            utils_entity_lifetime::Request_DestroyEntity(_AgentEntity);
            _AgentEntity = FCk_Handle();
            return false;
        }

        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);
        utils_crowd_agent::Set_DebugColor(_Agent, FLinearColor(0.2, 0.9, 1.0, 1.0));

        utils_crowd_agent::BindTo_OnGoalReached(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnAgentGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnAgentGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(InGoal));
        return true;
    }

    private void ClearEntities()
    {
        if (ck::IsValid(_AgentEntity))
        { utils_entity_lifetime::Request_DestroyEntity(_AgentEntity); }
        if (ck::IsValid(_VolumeEntity))
        { utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity); }

        _AgentEntity = FCk_Handle();
        _VolumeEntity = FCk_Handle();
        _Agent = FCk_Handle_CrowdAgent();
    }

    UFUNCTION()
    private void OnGymTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Spawn = GetCourseSpawn();
        const auto Goal = GetCourseGoal();
        utils_debug_draw::DrawDebugDashedLine(Spawn, Goal, 25.0,
            FLinearColor(0.8, 0.8, 0.8, 1.0), 0.0, 2.0);
        utils_debug_draw::DrawDebugSphere(Spawn, 18.0, 12,
            FLinearColor(0.2, 0.9, 1.0, 1.0), 0.0, 3.0);
        utils_debug_draw::DrawDebugSphere(Goal, 24.0, 12,
            FLinearColor(0.3, 1.0, 0.3, 1.0), 0.0, 4.0);

        if (_DrawVolume && ck::IsValid(_VolumeEntity))
        {
            const auto Color = ck::IsValid(_AgentEntity)
                ? FLinearColor(1.0, 0.8, 0.1, 1.0)
                : FLinearColor(0.3, 1.0, 0.3, 1.0);
            utils_debug_draw::DrawDebugWireframeBox(GetVolumeCenter(), GetVolumeHalfExtents(),
                GetVolumeRotation().Quaternion(), Color, 0.0, 5.0);
        }

    }

    UFUNCTION()
    private void OnAgentGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (InAgent != _Agent)
        { return; }

        _LastResult = "REACHED";
        ck::crowd::Log("Avoidance-volume gym: agent reached the goal");
    }

    UFUNCTION()
    private void OnAgentGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (InAgent != _Agent)
        { return; }

        _LastResult = "FAILED";
        ck::crowd::Warning("Avoidance-volume gym: agent failed to reach the goal");
    }
}
