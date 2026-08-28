class ACk_CrowdGym_AvoidanceVolume_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _OwnerHandle;
    private FCk_Handle _StationHandle;
    private FCk_Handle _PrimaryAgentEntity;
    private FCk_Handle _PrimaryVolumeEntity;
    private FCk_Handle_CrowdAgent _PrimaryAgent;
    private FCk_Handle_CrowdAvoidanceVolume _PrimaryVolume;
    private TArray<FCk_Handle> _TrackedAgentEntities;
    private TArray<FCk_Handle> _TrackedVolumeEntities;
    private TArray<FCk_Handle_CrowdAgent> _StressAgents;
    private TArray<UCk_NavAreaMarkup_UE> _TrackedMarkup;
    private TArray<FVector> _StressVolumeCenters;
    private TArray<ECk_CrowdAvoidanceVolume_TraversalPolicy> _StressVolumePolicies;
    private FVector _PrimaryVolumeCenter = FVector::ZeroVector;
    private FVector _PrimaryVolumeHalfExtents = FVector::ZeroVector;
    private FRotator _PrimaryVolumeRotation = FRotator::ZeroRotator;
    private ECk_CrowdAvoidanceVolume_TraversalPolicy _PrimaryVolumePolicy = ECk_CrowdAvoidanceVolume_TraversalPolicy::AvoidIfPossible;

    private bool _DrawVolume = true;
    private bool _ReplacementDispatched = false;
    private bool _SealedRoutePending = false;
    private float _PathPlanningClearance = 50.0;
    private int32 _ActiveScenario = 0;
    private int32 _StressReached = 0;
    private int32 _StressFailed = 0;
    private FString _LastResult = "Not run";

    private const int32 Scenario_None = 0;
    private const int32 Scenario_Baseline = 1;
    private const int32 Scenario_AvoidIfPossible = 2;
    private const int32 Scenario_CostOnly = 3;
    private const int32 Scenario_HardExclude = 4;
    private const int32 Scenario_Inside = 5;
    private const int32 Scenario_Replacement = 6;
    private const int32 Scenario_SealedAvoidIfPossible = 7;
    private const int32 Scenario_SealedHardExclude = 8;
    private const int32 Scenario_Stress = 9;

    private const float32 AgentRadius = 42.0f;
    private const float32 AgentHeight = 192.0f;
    private const float CourseHalfLength = 600.0;
    private const float CourseZ = 100.0;
    private const float VolumeYawDegrees = 35.0;
    private const float VolumeInfluenceRange = 400.0;
    private const float ExactPathPlanningClearance = 0.0;
    private const float ExpandedPathPlanningClearance = 50.0;
    private const float SealedCorridorHalfWidth = 190.0;
    private const float SealedWallHalfExtent = 5000.0;
    private const int32 StressDimension = 10;
    private const float StressSpacing = 360.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Crowd.AvoidanceVolume");
        Station.Title = FText::FromString("CROWD AVOIDANCE VOLUME");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("1 baseline; 2 Avoid If Possible detour; 3 Cost Only weighted route; 4 Hard Exclude detour."));
        Description.Add(FText::FromString("5 inside escape; 6 confirmed removal and same-tick replacement."));
        Description.Add(FText::FromString("7 sealed Avoid If Possible fallback; 8 sealed Hard Exclude failure; 9 100-volume/100-agent stress."));
        Description.Add(FText::FromString("K selects exact (0 uu) or expanded (50 uu) path clearance for every scenario."));
        Description.Add(FText::FromString("V toggles authored volume wireframes. C clears every tracked entity and nav markup."));
        Station.Description = Description;
        Stations.Add(Station);
        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false) { return; }
        _OwnerHandle = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_OwnerHandle))
        { ck::crowd::Warning("Avoidance-volume gym: PlayerController entity is invalid"); return; }
        SpawnFloor();
        _StationHandle = Get_StationHandle("Gym.Crowd.AvoidanceVolume");
        if (ck::Is_NOT_Valid(_StationHandle))
        { ck::crowd::Warning("Avoidance-volume gym: station handle is invalid"); return; }
        System::ExecuteConsoleCommand("ck.Crowd.Debug.AgentBody 1");
        utils_nav::Request_NavigationRebuild_ForTesting(_OwnerHandle);
        utils_timer::Create_Tick(_OwnerHandle, FCk_Delegate_Timer(this, n"OnGymTick"));
        ck::crowd::Log("Avoidance-volume gym ready. Use controls 1-9 to compare traversal policies and stress rebuild behavior.");
    }

    private void SpawnFloor()
    {
        auto Floor = SpawnActor(ACk_Gym_Floor, FVector::ZeroVector, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr) { ck::crowd::Warning("Avoidance-volume gym: failed to spawn floor actor"); return; }
        // Match the established large crowd gyms: a 7500 x 7500 walkable surface leaves room for
        // the 100-volume field and all 100 separated spawn points.
        Floor.SetActorScale3D(FVector(75.0, 75.0, 0.5));
        FinishSpawningActor(Floor);
    }

    FString Get_ControlPanelTitle() override { return "CROWD: AVOIDANCE VOLUME"; }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("TRAVERSAL POLICY AND LIFECYCLE"));
        Rows.Add(CkGym_Control::Numbered(0, "Baseline: no volume", _ActiveScenario == Scenario_Baseline));
        Rows.Add(CkGym_Control::Numbered(1, "Avoid If Possible: open detour", _ActiveScenario == Scenario_AvoidIfPossible));
        Rows.Add(CkGym_Control::Numbered(2, "Cost Only: weighted and traversable", _ActiveScenario == Scenario_CostOnly));
        Rows.Add(CkGym_Control::Numbered(3, "Hard Exclude: open detour", _ActiveScenario == Scenario_HardExclude));
        Rows.Add(CkGym_Control::Numbered(4, "Start inside: escape before goal", _ActiveScenario == Scenario_Inside));
        Rows.Add(CkGym_Control::Numbered(5, "Removal: confirmed volume then same-tick replacement", _ActiveScenario == Scenario_Replacement));
        Rows.Add(CkGym_Control::Numbered(6, "Sealed: Avoid If Possible fallback traversal", _ActiveScenario == Scenario_SealedAvoidIfPossible));
        Rows.Add(CkGym_Control::Numbered(7, "Sealed: Hard Exclude expected failure", _ActiveScenario == Scenario_SealedHardExclude));
        Rows.Add(CkGym_Control::Numbered(8, "Stress: 100 volumes + 100 agents", _ActiveScenario == Scenario_Stress));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::K, "K", "Path clearance",
            _PathPlanningClearance > ExactPathPlanningClearance, "50 uu", "EXACT (0 uu)"));
        Rows.Add(CkGym_Control::Toggle(EKeys::V, "V", "Volume wireframe", _DrawVolume));
        Rows.Add(CkGym_Control::Action(EKeys::C, "C", "Clear tracked entities and nav markup"));
        Rows.Add(CkGym_Control::Status("Tracked", f"agents={_TrackedAgentEntities.Num()} volumes={_TrackedVolumeEntities.Num()} markup={_TrackedMarkup.Num()}", false));
        Rows.Add(CkGym_Control::Status("Stress", f"reached={_StressReached} failed={_StressFailed} / 100", _StressFailed > 0));
        Rows.Add(CkGym_Control::Status("Last result", _LastResult,
            _LastResult == "FAILED" || _LastResult == "VOLUME FAILED" ||
            _LastResult == "AGENT FAILED" || _LastResult == "MARKUP FAILED"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1) { Ck_GymCrowd_AvoidanceVolume_Baseline(); }
        else if (InRowIndex == 2) { Ck_GymCrowd_AvoidanceVolume_AvoidIfPossible(); }
        else if (InRowIndex == 3) { Ck_GymCrowd_AvoidanceVolume_CostOnly(); }
        else if (InRowIndex == 4) { Ck_GymCrowd_AvoidanceVolume_HardExclude(); }
        else if (InRowIndex == 5) { Ck_GymCrowd_AvoidanceVolume_Inside(); }
        else if (InRowIndex == 6) { Ck_GymCrowd_AvoidanceVolume_Replacement(); }
        else if (InRowIndex == 7) { Ck_GymCrowd_AvoidanceVolume_SealedAvoidIfPossible(); }
        else if (InRowIndex == 8) { Ck_GymCrowd_AvoidanceVolume_SealedHardExclude(); }
        else if (InRowIndex == 9) { Ck_GymCrowd_AvoidanceVolume_Stress(); }
        else if (InRowIndex == 10) { TogglePathPlanningClearance(); }
        else if (InRowIndex == 11) { Ck_GymCrowd_AvoidanceVolume_ToggleDebug(); }
        else if (InRowIndex == 12) { Ck_GymCrowd_AvoidanceVolume_Clear(); }
    }

    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_Baseline()
    { BeginOpenScenario(Scenario_Baseline, ECk_CrowdAvoidanceVolume_TraversalPolicy::CostOnly, false, false, "baseline"); }
    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_AvoidIfPossible()
    { BeginOpenScenario(Scenario_AvoidIfPossible, ECk_CrowdAvoidanceVolume_TraversalPolicy::AvoidIfPossible, true, false, "Avoid If Possible detour"); }
    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_CostOnly()
    { BeginOpenScenario(Scenario_CostOnly, ECk_CrowdAvoidanceVolume_TraversalPolicy::CostOnly, true, false, "Cost Only weighted route"); }
    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_HardExclude()
    { BeginOpenScenario(Scenario_HardExclude, ECk_CrowdAvoidanceVolume_TraversalPolicy::HardExclude, true, false, "Hard Exclude detour"); }
    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_Inside()
    { BeginOpenScenario(Scenario_Inside, ECk_CrowdAvoidanceVolume_TraversalPolicy::AvoidIfPossible, true, true, "start-inside escape"); }
    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_Replacement()
    { BeginOpenScenario(Scenario_Replacement, ECk_CrowdAvoidanceVolume_TraversalPolicy::AvoidIfPossible, true, false, "waiting for confirmed removal"); }

    private void BeginOpenScenario(int32 InScenario, ECk_CrowdAvoidanceVolume_TraversalPolicy InPolicy, bool InSpawnVolume, bool InStartInside, FString InLabel)
    {
        if (CanRunScenario() == false) { return; }
        ClearEntities();
        _ActiveScenario = InScenario;
        _SealedRoutePending = false;
        _LastResult = f"Running {InLabel}";
        _ReplacementDispatched = false;
        if (InSpawnVolume)
        { _PrimaryVolume = SpawnVolume(GetVolumeCenter(), GetVolumeHalfExtents(), GetVolumeRotation(), InPolicy, n"CrowdAvoidanceVolumeGymVolume"); }
        if (InSpawnVolume && ck::Is_NOT_Valid(_PrimaryVolume))
        { _ActiveScenario = Scenario_None; _LastResult = "VOLUME FAILED"; return; }
        const auto Spawn = InStartInside ? GetVolumeCenter() + FVector(-120.0, 0.0, 0.0) : GetCourseSpawn();
        _PrimaryAgent = SpawnAgentAndMove(Spawn, GetCourseGoal(), n"CrowdAvoidanceVolumeGymAgent", FLinearColor(0.2, 0.9, 1.0, 1.0));
        if (ck::Is_NOT_Valid(_PrimaryAgent))
        { ClearEntities(); _ActiveScenario = Scenario_None; _LastResult = "AGENT FAILED"; return; }
    }

    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_SealedAvoidIfPossible()
    { BeginSealedScenario(Scenario_SealedAvoidIfPossible, ECk_CrowdAvoidanceVolume_TraversalPolicy::AvoidIfPossible); }
    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_SealedHardExclude()
    { BeginSealedScenario(Scenario_SealedHardExclude, ECk_CrowdAvoidanceVolume_TraversalPolicy::HardExclude); }

    private void BeginSealedScenario(int32 InScenario, ECk_CrowdAvoidanceVolume_TraversalPolicy InPolicy)
    {
        if (CanRunScenario() == false) { return; }
        ClearEntities();
        _ActiveScenario = InScenario;
        _LastResult = InScenario == Scenario_SealedAvoidIfPossible ? "Waiting for sealed fallback" : "Waiting for Hard Exclude failure";
        const auto WallCenterY = SealedCorridorHalfWidth + SealedWallHalfExtent;
        const auto TopTracked = TrackMarkup(utils_nav_area_markup::Request_Create(_OwnerHandle, FTransform(FRotator::ZeroRotator, GetCourseCenter() + FVector(0.0, WallCenterY, 0.0), FVector::OneVector), FVector(SealedWallHalfExtent, SealedWallHalfExtent, 200.0), UNavArea_Null));
        const auto BottomTracked = TrackMarkup(utils_nav_area_markup::Request_Create(_OwnerHandle, FTransform(FRotator::ZeroRotator, GetCourseCenter() + FVector(0.0, -WallCenterY, 0.0), FVector::OneVector), FVector(SealedWallHalfExtent, SealedWallHalfExtent, 200.0), UNavArea_Null));
        if (TopTracked == false || BottomTracked == false)
        { ClearEntities(); _ActiveScenario = Scenario_None; _LastResult = "MARKUP FAILED"; return; }
        _PrimaryVolume = SpawnVolume(GetVolumeCenter(), FVector(180.0, 90.0, 100.0), FRotator::ZeroRotator, InPolicy, n"CrowdAvoidanceVolumeGymSealedVolume");
        if (ck::Is_NOT_Valid(_PrimaryVolume))
        { ClearEntities(); _ActiveScenario = Scenario_None; _LastResult = "VOLUME FAILED"; return; }
        utils_nav::Request_NavigationRebuild_ForTesting(_OwnerHandle);
        _SealedRoutePending = true;
    }

    UFUNCTION(Exec)
    void Ck_GymCrowd_AvoidanceVolume_Stress()
    {
        if (CanRunScenario() == false) { return; }
        ClearEntities();
        _ActiveScenario = Scenario_Stress;
        _LastResult = "Dispatching 100 volumes and 100 agents toward 81 interior + 19 cross-field goals";
        const auto FieldCenter = GetCourseCenter();
        const auto HalfField = (StressDimension - 1) * StressSpacing * 0.5;
        for (int32 Row = 0; Row < StressDimension; ++Row)
        {
            for (int32 Column = 0; Column < StressDimension; ++Column)
            {
                const auto Index = Row * StressDimension + Column;
                auto Policy = ECk_CrowdAvoidanceVolume_TraversalPolicy::AvoidIfPossible;
                if (Index % 3 == 1) { Policy = ECk_CrowdAvoidanceVolume_TraversalPolicy::CostOnly; }
                else if (Index % 3 == 2) { Policy = ECk_CrowdAvoidanceVolume_TraversalPolicy::HardExclude; }
                const auto Center = FieldCenter + FVector(Column * StressSpacing - HalfField, Row * StressSpacing - HalfField + (Column % 2 == 0 ? 90.0 : -90.0), 0.0);
                _StressVolumeCenters.Add(Center);
                _StressVolumePolicies.Add(Policy);
                const auto Volume = SpawnVolume(Center, FVector(100.0, 80.0, 100.0), FRotator::ZeroRotator, Policy, n"CrowdAvoidanceVolumeGymStressVolume");
                if (ck::Is_NOT_Valid(Volume)) { _LastResult = "VOLUME FAILED"; ClearEntities(); _ActiveScenario = Scenario_None; return; }
            }
        }
        // Deliberately do not wait for confirmation: these MoveTo requests exercise the rebuild window.
        for (int32 Row = 0; Row < StressDimension; ++Row)
        {
            for (int32 Lane = 0; Lane < StressDimension; ++Lane)
            {
                const auto AgentIndex = Row * StressDimension + Lane;
                const auto Y = FieldCenter.Y + (Row - 4.5) * 150.0;
                const auto Spawn = FVector(FieldCenter.X - HalfField - 450.0 - Lane * 90.0, Y, FieldCenter.Z);
                const auto Goal = GetStressGoal(FieldCenter, HalfField, AgentIndex);
                const auto Agent = SpawnAgentAndMove(Spawn, Goal, n"CrowdAvoidanceVolumeGymStressAgent", FLinearColor(0.8, 0.3, 1.0, 1.0));
                if (ck::Is_NOT_Valid(Agent)) { _LastResult = "AGENT FAILED"; ClearEntities(); _ActiveScenario = Scenario_None; return; }
                _StressAgents.Add(Agent);
            }
        }
        ck::crowd::Log("Avoidance-volume gym: stress dispatched exactly 100 volumes (34 Avoid If Possible, 33 Cost Only, 33 Hard Exclude) and 100 moving agents toward 81 interior gap goals plus 19 cross-field goals");
    }

    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_ToggleDebug() { _DrawVolume = !_DrawVolume; }
    UFUNCTION(Exec) void Ck_GymCrowd_AvoidanceVolume_Clear()
    {
        if (HasAuthority() == false) { return; }
        ClearEntities(); _ActiveScenario = Scenario_None; _LastResult = "Cleared";
    }

    private void TogglePathPlanningClearance()
    {
        if (HasAuthority() == false) { return; }
        ClearEntities();
        _ActiveScenario = Scenario_None;
        _PathPlanningClearance = _PathPlanningClearance > ExactPathPlanningClearance
            ? ExactPathPlanningClearance
            : ExpandedPathPlanningClearance;
        _LastResult = _PathPlanningClearance > ExactPathPlanningClearance
            ? "Path clearance set to 50 uu; choose a scenario"
            : "Path clearance set to exact 0 uu; choose a scenario";
        ck::crowd::Log(_LastResult);
    }

    private bool CanRunScenario() { return HasAuthority() && ck::IsValid(_OwnerHandle) && ck::IsValid(_StationHandle); }
    private FVector GetCourseCenter()
    {
        const auto StationTransform = Get_StationAnchorTransform("Gym.Crowd.AvoidanceVolume", ECk_GymStation_Anchor::FootprintCenter);
        return StationTransform.GetLocation() + FVector(-700.0, 0.0, CourseZ);
    }
    private FVector GetCourseSpawn() { return GetCourseCenter() + FVector(CourseHalfLength, 0.0, 0.0); }
    private FVector GetCourseGoal() { return GetCourseCenter() - FVector(CourseHalfLength, 0.0, 0.0); }
    private FVector GetVolumeCenter() { return GetCourseCenter(); }
    private FVector GetVolumeHalfExtents() { return FVector(250.0, 90.0, 100.0); }
    private FRotator GetVolumeRotation() { return FRotator(0.0, VolumeYawDegrees, 0.0); }

    private FVector GetStressGoal(FVector InFieldCenter, float InHalfField, int32 InAgentIndex)
    {
        // 37 is coprime with 100, so every agent receives a unique slot while adjacent spawn
        // ranks are scattered across the goal field instead of following parallel lanes.
        const auto GoalSlot = (InAgentIndex * 37) % 100;
        if (GoalSlot < 81)
        {
            const auto GapDimension = StressDimension - 1;
            const auto GapRow = Math::IntegerDivisionTrunc(GoalSlot, GapDimension);
            const auto GapColumn = GoalSlot % GapDimension;
            return FVector(
                InFieldCenter.X + (GapColumn - 4.0) * StressSpacing,
                InFieldCenter.Y + (GapRow - 4.0) * StressSpacing,
                InFieldCenter.Z);
        }

        const auto CrossIndex = GoalSlot - 81;
        return FVector(
            InFieldCenter.X + InHalfField + 450.0,
            InFieldCenter.Y + (CrossIndex - 9.0) * 200.0,
            InFieldCenter.Z);
    }

    private FCk_Handle_CrowdAvoidanceVolume SpawnVolume(FVector InCenter, FVector InHalfExtents, FRotator InRotation, ECk_CrowdAvoidanceVolume_TraversalPolicy InPolicy, FName InDebugName)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Set_DebugName(InDebugName);
        auto Transform = utils_transform::Add(Entity, FTransform(InRotation, InCenter, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Fragment_CrowdAvoidanceVolume_ParamsData(InHalfExtents, VolumeInfluenceRange);
        Params.Set_TraversalPolicy(InPolicy);
        Params.Set_PathPlanningClearance(_PathPlanningClearance);
        const auto Volume = utils_crowd_avoidance_volume::Add(Transform, Params);
        if (ck::Is_NOT_Valid(Volume)) { utils_entity_lifetime::Request_DestroyEntity(Entity); return FCk_Handle_CrowdAvoidanceVolume(); }
        _TrackedVolumeEntities.Add(Entity);
        _PrimaryVolumeEntity = Entity;
        _PrimaryVolumeCenter = InCenter;
        _PrimaryVolumeHalfExtents = InHalfExtents;
        _PrimaryVolumeRotation = InRotation;
        _PrimaryVolumePolicy = InPolicy;
        return Volume;
    }

    private FCk_Handle_CrowdAgent SpawnAgentAndMove(FVector InSpawn, FVector InGoal, FName InDebugName, FLinearColor InColor)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Set_DebugName(InDebugName);
        auto Transform = utils_transform::Add(Entity, FTransform((InGoal - InSpawn).GetSafeNormal().Rotation(), InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        const auto Agent = utils_crowd_agent::Add(Transform, FCk_Fragment_CrowdAgent_ParamsData(AgentRadius, AgentHeight));
        if (ck::Is_NOT_Valid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Entity); return FCk_Handle_CrowdAgent(); }
        utils_velocity::Add(Entity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Entity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Entity);
        utils_crowd_agent::Set_DebugColor(Agent, InColor);
        utils_crowd_agent::BindTo_OnGoalReached(Agent, FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnAgentGoalReached"), ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame, ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(Agent, FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnAgentGoalFailed"), ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame, ECk_Signal_PostFireBehavior::DoNothing);
        _TrackedAgentEntities.Add(Entity);
        _PrimaryAgentEntity = Entity;
        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(InGoal));
        return Agent;
    }

    private bool TrackMarkup(UCk_NavAreaMarkup_UE InMarkup)
    {
        if (InMarkup == nullptr) { return false; }
        _TrackedMarkup.Add(InMarkup);
        return true;
    }

    private void ClearEntities()
    {
        for (auto Entity : _TrackedAgentEntities) { if (ck::IsValid(Entity)) { utils_entity_lifetime::Request_DestroyEntity(Entity); } }
        for (auto Entity : _TrackedVolumeEntities) { if (ck::IsValid(Entity)) { utils_entity_lifetime::Request_DestroyEntity(Entity); } }
        for (auto Markup : _TrackedMarkup) { if (Markup != nullptr) { utils_nav_area_markup::Request_Destroy(Markup); } }
        _TrackedAgentEntities.Empty(); _TrackedVolumeEntities.Empty(); _StressAgents.Empty();
        _TrackedMarkup.Empty(); _StressVolumeCenters.Empty(); _StressVolumePolicies.Empty();
        _PrimaryAgentEntity = FCk_Handle(); _PrimaryVolumeEntity = FCk_Handle();
        _PrimaryAgent = FCk_Handle_CrowdAgent(); _PrimaryVolume = FCk_Handle_CrowdAvoidanceVolume();
        _StressReached = 0; _StressFailed = 0; _SealedRoutePending = false; _ReplacementDispatched = false;
    }

    UFUNCTION()
    private void OnGymTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Spawn = GetCourseSpawn(); const auto Goal = GetCourseGoal();
        utils_debug_draw::DrawDebugDashedLine(Spawn, Goal, 25.0, FLinearColor(0.8, 0.8, 0.8, 1.0), 0.0, 2.0);
        utils_debug_draw::DrawDebugSphere(Spawn, 18.0, 12, FLinearColor(0.2, 0.9, 1.0, 1.0), 0.0, 3.0);
        utils_debug_draw::DrawDebugSphere(Goal, 24.0, 12, FLinearColor(0.3, 1.0, 0.3, 1.0), 0.0, 4.0);
        if (_DrawVolume && _ActiveScenario != Scenario_Stress && ck::IsValid(_PrimaryVolumeEntity))
        { utils_debug_draw::DrawDebugWireframeBox(_PrimaryVolumeCenter, _PrimaryVolumeHalfExtents, _PrimaryVolumeRotation.Quaternion(), GetPolicyColor(_PrimaryVolumePolicy), 0.0, 5.0); }
        if (_DrawVolume && _ActiveScenario == Scenario_Stress)
        {
            for (int32 Index = 0; Index < _StressVolumeCenters.Num(); ++Index)
            {
                utils_debug_draw::DrawDebugWireframeBox(_StressVolumeCenters[Index],
                    FVector(100.0, 80.0, 100.0), FRotator::ZeroRotator.Quaternion(),
                    GetPolicyColor(_StressVolumePolicies[Index]), 0.0, 1.0);
            }
        }
        if (_SealedRoutePending && ck::IsValid(_PrimaryVolume) &&
            utils_crowd_avoidance_volume::Get_IsNavigationConfirmed(_PrimaryVolume) &&
            Get_AreSealedWallsConfirmed())
        {
            _PrimaryAgent = SpawnAgentAndMove(GetCourseSpawn(), GetCourseGoal(), n"CrowdAvoidanceVolumeGymSealedAgent", FLinearColor(1.0, 0.5, 0.2, 1.0));
            _SealedRoutePending = false;
            _LastResult = ck::IsValid(_PrimaryAgent) ? "Sealed route dispatched after confirmation" : "AGENT FAILED";
        }
        if (_ActiveScenario == Scenario_Replacement && _ReplacementDispatched == false && ck::IsValid(_PrimaryVolume) && utils_crowd_avoidance_volume::Get_IsNavigationConfirmed(_PrimaryVolume))
        {
            // Removal and replacement deliberately share this tick; destruction is deferred.
            utils_entity_lifetime::Request_DestroyEntity(_PrimaryVolumeEntity);
            utils_entity_lifetime::Request_DestroyEntity(_PrimaryAgentEntity);
            _PrimaryAgent = SpawnAgentAndMove(GetCourseSpawn(), GetCourseGoal(), n"CrowdAvoidanceVolumeGymReplacementAgent", FLinearColor(0.3, 1.0, 0.3, 1.0));
            _ReplacementDispatched = ck::IsValid(_PrimaryAgent);
            _LastResult = _ReplacementDispatched ? "Replacement MoveTo dispatched same tick" : "AGENT FAILED";
        }
    }

    UFUNCTION()
    private void OnAgentGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (_ActiveScenario == Scenario_Stress)
        {
            if (_StressAgents.Contains(InAgent)) { ++_StressReached; }
            return;
        }
        if (InAgent != _PrimaryAgent) { return; }
        _LastResult = "REACHED";
    }

    UFUNCTION()
    private void OnAgentGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (_ActiveScenario == Scenario_Stress)
        {
            if (_StressAgents.Contains(InAgent)) { ++_StressFailed; }
            return;
        }
        if (InAgent != _PrimaryAgent) { return; }
        _LastResult = _ActiveScenario == Scenario_SealedHardExclude ? "EXPECTED HARD EXCLUDE FAILURE" : "FAILED";
    }

    private FLinearColor GetPolicyColor(ECk_CrowdAvoidanceVolume_TraversalPolicy InPolicy)
    {
        if (InPolicy == ECk_CrowdAvoidanceVolume_TraversalPolicy::HardExclude)
        { return FLinearColor(1.0, 0.15, 0.1, 1.0); }
        if (InPolicy == ECk_CrowdAvoidanceVolume_TraversalPolicy::CostOnly)
        { return FLinearColor(1.0, 0.65, 0.1, 1.0); }
        return FLinearColor(0.15, 0.65, 1.0, 1.0);
    }

    private bool Get_AreSealedWallsConfirmed()
    {
        const auto WitnessOffset = SealedCorridorHalfWidth + 100.0;
        for (int32 Index = 0; Index < 5; ++Index)
        {
            const auto X = -CourseHalfLength + (CourseHalfLength * 2.0) * (float(Index) / 4.0);
            FVector Projected;
            const auto TopWitness = GetCourseCenter() + FVector(X, WitnessOffset, 0.0);
            const auto BottomWitness = GetCourseCenter() + FVector(X, -WitnessOffset, 0.0);
            if (utils_nav::Try_ProjectOntoNavmesh(_OwnerHandle, TopWitness, 20.0f, Projected, 300.0f) ||
                utils_nav::Try_ProjectOntoNavmesh(_OwnerHandle, BottomWitness, 20.0f, Projected, 300.0f))
            { return false; }
        }
        return true;
    }
}
