// Language=angelscript
// --------------------------------------------------------------------------------------------------------------------
// QUEUE GYM — state-driven CrowdAgent adapter demo. Gym options exercise the public queue boundary and the
// resulting events are deliberately the same surface that a GOAP planner would consume.
// --------------------------------------------------------------------------------------------------------------------

class ACk_QueueGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _PcEntity;
    private FCk_Handle _LiveStation;
    private FCk_Handle _NavProbeEntity;
    private FCk_Handle _QueueOwner;
    private FCk_Handle_Queue _Queue;
    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private TArray<FCk_Handle_CrowdAgent> _RejectedAgents;
    private TArray<UCk_NavAreaMarkup_UE> _TargetBlockers;
    private ACk_Gym_Floor _Floor = nullptr;
    private TArray<FString> _Trace;
    private int32 _JoinSucceeded = 0;
    private int32 _JoinRejected = 0;
    private int32 _EventCount = 0;
    private int32 _Population = 6;
    private int32 _OriginMode = 0;
    private bool _Linear = false;
    private bool _TargetBlocked = false;
    private bool _QueueVisualization = true;
    private bool _PreviousQueueVisualization = false;
    private bool _CapturedQueueVisualization = false;
    private bool _AutoStarted = false;

    private const float SpawnZ = 110.0f;
    private const float QueueFwdOffset = 1000.0f;
    private const float AgentRadius = 42.0f;
    private const float AgentHeight = 192.0f;
    private const float TargetBlockerHalfExtent = 180.0f;
    private const int32 HardLimit = 30;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false) { return TArray<FCkGym_Station_SpawnParams_Payload>(); }
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        AddStation(Stations, n"Gym.Queue.Live", "QUEUE: LIVE CROWD AGENTS",
            "Use the numbered options panel for direct queue scenarios. Default: six agents, one target, orthogonal snake, reachable navigation, and visible diagnostics.");
        return Stations;
    }

    TArray<FCkGym_Option> Get_GymOptions() override
    {
        auto Options = TArray<FCkGym_Option>();
        Options.Add(FCkGym_Option(n"Queue.Reset", "Reset demo", "", "Rebuild the selected scenario from source-of-truth options."));
        Options.Add(FCkGym_Option(n"Queue.Population", "Population", GetPopulationLabel(), "Cycles exact reset populations: 6, 12, 24, 30, then 32 (30 admitted + 2 rejected)."));
        Options.Add(FCkGym_Option(n"Queue.Layout", "Layout", GetLayoutLabel(), "Changes the current queue layout and reflows admitted agents."));
        Options.Add(FCkGym_Option(n"Queue.Origins", "Origins", GetOriginModeLabel(), "Cycles single, moved/rotated, and two weighted targets."));
        Options.Add(FCkGym_Option(n"Queue.Navigation", "Navigation", GetNavigationLabel(), "Blocks only active target footprints; starts and corridor remain navigable."));
        Options.Add(FCkGym_Option(n"Queue.Visualization", "Queue visualization", _QueueVisualization ? "On" : "Off", "Shows reservations, explicit target markers, rejected agents, and blocker bounds."));
        Options.Add(FCkGym_Option(n"Queue.Advance", "Advance origin", "", "Serves the front member at the first origin."));
        Options.Add(FCkGym_Option(n"Queue.DestroyAgent", "Destroy first queued agent", "", "Destroys the first valid admitted agent without Leave."));
        Options.Add(FCkGym_Option(n"Queue.DestroyOwner", "Destroy queue owner", "", "Invalidates the queue and demonstrates safe adapter teardown."));
        Options.Add(FCkGym_Option(n"Queue.Digest", "Snapshot / GOAP trace", "", "Prints membership, ranks, state, and assignment revisions."));
        return Options;
    }

    FString Get_GymOptionsTitle() override { return "QUEUE GYM OPTIONS"; }

    bool Request_SelectGymOption(FName InOptionId) override
    {
        if (HasAuthority() == false) { return false; }
        if (InOptionId == n"Queue.Reset") { Ck_GymQueue_Start(); return true; }
        if (InOptionId == n"Queue.Population") { CyclePopulation(); return true; }
        if (InOptionId == n"Queue.Layout") { CycleLayout(); return true; }
        if (InOptionId == n"Queue.Origins") { CycleOrigins(); return true; }
        if (InOptionId == n"Queue.Navigation") { CycleNavigation(); return true; }
        if (InOptionId == n"Queue.Visualization") { CycleVisualization(); return true; }
        if (InOptionId == n"Queue.Advance") { Ck_GymQueue_Advance(0); return true; }
        if (InOptionId == n"Queue.DestroyAgent") { DestroyFirstQueuedAgent(); return true; }
        if (InOptionId == n"Queue.DestroyOwner") { Ck_GymQueue_DestroyOwner(); return true; }
        if (InOptionId == n"Queue.Digest") { Ck_GymQueue_Digest(); return true; }
        return false;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false) { return; }
        _PcEntity = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_PcEntity)) { ck::Warning("Queue gym requires its PlayerController entity"); return; }
        if (_CapturedQueueVisualization == false)
        {
            _PreviousQueueVisualization = utils_queue::Get_IsDebugDrawEnabled();
            _CapturedQueueVisualization = true;
        }
        _LiveStation = Get_StationHandle("Gym.Queue.Live");
        if (ck::Is_NOT_Valid(_LiveStation)) { ck::Warning("Queue gym requires its live station"); return; }

        _AutoStarted = false;
        if (TrySpawnFloor() == false) { return; }
        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);

        if (ck::IsValid(_NavProbeEntity)) { utils_entity_lifetime::Request_DestroyEntity(_NavProbeEntity); }

        const auto ProbeStart = StationLocal_To_World(FVector(QueueFwdOffset - 600.0f, 0.0f, SpawnZ));
        const auto ProbeGoal = StationLocal_To_World(FVector(QueueFwdOffset + 200.0f, 0.0f, SpawnZ));
        _NavProbeEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        utils_transform::Add(_NavProbeEntity, FTransform(FRotator::ZeroRotator, ProbeStart, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        utils_nav::BindTo_OnPathReady(_NavProbeEntity, FCk_Delegate_Nav_OnPathReady(this, n"OnNavProbeReady"), ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame, ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::BindTo_OnPathFailed(_NavProbeEntity, FCk_Delegate_Nav_OnPathFailed(this, n"OnNavProbeFailed"), ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame, ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::Request_FindPath(_NavProbeEntity, FCk_Request_Nav_FindPath(ProbeGoal));
        ck::Trace("Queue gym: waiting for its runtime floor to finish baking before auto-start");
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds) { DrawScenarioDiagnostics(); }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        RestoreTargetBlocker();
        if (_CapturedQueueVisualization)
        { utils_queue::Set_DebugDrawEnabled(_PreviousQueueVisualization); }
    }

    UFUNCTION()
    private void OnNavProbeReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (InHandle != _NavProbeEntity || _AutoStarted) { return; }
        _AutoStarted = true;
        Ck_GymQueue_Start();
    }

    UFUNCTION()
    private void OnNavProbeFailed(FCk_Handle InHandle)
    {
        if (InHandle != _NavProbeEntity) { return; }
        ck::Warning("Queue gym navmesh probe failed; auto-start skipped until the floor is navigable");
    }

    // Compatibility entry point. The menu is primary; this rebuilds exactly the selected configuration.
    UFUNCTION(Exec, DisplayName="Queue - Start / Reset Live Demo")
    void Ck_GymQueue_Start()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_LiveStation)) { return; }
        _AutoStarted = true;
        ApplyVisualizationSetting();
        ResetScenario();
        _Trace.Empty();
        _JoinSucceeded = 0;
        _JoinRejected = 0;
        _EventCount = 0;

        const auto QueueOwnerTransform = Get_QueueOwnerTransform();
        _QueueOwner = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        utils_transform::Add(_QueueOwner, QueueOwnerTransform, ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Fragment_Queue_ParamsData(GetConfiguredOrigins());
        Params.Set_Category(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        Params.Set_SlotSpacingUu(120.0f);
        Params.Set_HardLimit(HardLimit);
        Params.Set_SoftLimit(4);
        Params.Set_AgentRadiusUu(AgentRadius);
        Params.Set_AgentHalfHeightUu(AgentHeight * 0.5f);
        Params.Set_LayoutAlgorithm(_Linear ? ECk_Queue_LayoutAlgorithm::Linear : ECk_Queue_LayoutAlgorithm::OrthogonalSnake);
        _Queue = utils_queue::Add(_QueueOwner, Params);
        _Queue.BindTo_OnQueueMemberStateChanged(FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberEvent"));
        _Queue.BindTo_OnQueuePressureChanged(FCk_Delegate_Queue_OnPressureChanged(this, n"OnPressure"));
        _Queue.BindTo_OnQueueFormationStateChanged(FCk_Delegate_Queue_OnFormationStateChanged(this, n"OnFormation"));
        _Queue.BindTo_OnQueueInvalidated(FCk_Delegate_Queue_OnInvalidated(this, n"OnInvalidated"));

        ApplyTargetBlocker();
        SpawnAndJoinAgents(_Population);
        AddTrace(f"START: {GetPopulationLabel()} requested; layout={GetLayoutLabel()} origins={GetOriginModeLabel()} nav={GetNavigationLabel()}");
        RefreshDisplays();
    }

    // Compatibility entry point. It changes source state then creates an exact new scenario, not an incremental mystery population.
    UFUNCTION(Exec, DisplayName="Queue - Add Agents")
    void Ck_GymQueue_AddAgents(int32 InCount = 5)
    {
        if (InCount <= 0) { return; }
        _Population = Math::Min(32, _Population + InCount);
        Ck_GymQueue_Start();
    }

    UFUNCTION(Exec, DisplayName="Queue - Move Origin (Reflow)")
    void Ck_GymQueue_MoveOrigin() { _OriginMode = 1; ApplyOriginsLive(); }

    UFUNCTION(Exec, DisplayName="Queue - Use Two Weighted Origins")
    void Ck_GymQueue_TwoOrigins() { _OriginMode = 2; ApplyOriginsLive(); }

    UFUNCTION(Exec, DisplayName="Queue - Advance Origin")
    void Ck_GymQueue_Advance(int32 InOrigin = 0)
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_Queue)) { return; }
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(InOrigin));
        AddTrace(f"ACTION: advance requested at origin {InOrigin}");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Toggle Orthogonal Snake / Linear")
    void Ck_GymQueue_ToggleLayout() { CycleLayout(); }

    UFUNCTION(Exec, DisplayName="Queue - Make Target Unreachable")
    void Ck_GymQueue_Impossible() { _TargetBlocked = true; ApplyTargetBlocker(); RefreshDisplays(); }

    UFUNCTION(Exec, DisplayName="Queue - Restore Target Navigation")
    void Ck_GymQueue_RestoreNav() { _TargetBlocked = false; ApplyTargetBlocker(); RefreshDisplays(); }

    UFUNCTION(Exec, DisplayName="Queue - Overfill Hard Limit")
    void Ck_GymQueue_Overfill() { _Population = 32; Ck_GymQueue_Start(); }

    UFUNCTION(Exec, DisplayName="Queue - Destroy Agent By Index")
    void Ck_GymQueue_DestroyAgent(int32 InIndex = 0)
    {
        if (HasAuthority() == false || InIndex < 0 || InIndex >= _Agents.Num()) { return; }
        if (ck::IsValid(_Agents[InIndex]))
        {
            utils_entity_lifetime::Request_DestroyEntity(_Agents[InIndex]);
            AddTrace(f"ACTION: agent {InIndex} destroyed without Leave; reconciliation must reflow survivors.");
        }
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Destroy Queue Owner")
    void Ck_GymQueue_DestroyOwner()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_QueueOwner)) { return; }
        if (RestoreTargetBlocker()) { utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity); }
        utils_entity_lifetime::Request_DestroyEntity(_QueueOwner);
        AddTrace("ACTION: queue owner destroyed. Invalidated event must arrive before adapter callbacks can re-enter.");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Print Snapshot / GOAP Trace")
    void Ck_GymQueue_Digest() { if (HasAuthority()) { EmitSnapshot(); RefreshDisplays(); } }

    UFUNCTION()
    private void OnJoinCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (InRequestOwner != FCk_Handle(_Queue)) { return; }

        if (InResult == ECk_Request_OperationResult::Succeeded) { _JoinSucceeded += 1; }
        else { _JoinRejected += 1; }
        AddTrace(f"GOAP completion: Join result={InResult}");
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnMemberEvent(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (InQueue != _Queue) { return; }
        _EventCount += 1;
        const auto Member = InEvent.Get_Member();
        if (Member.Get_State() == ECk_Queue_MemberState::Rejected)
        { MarkRejectedAgent(Member.Get_Member()); }
        AddTrace(f"GOAP event: {InEvent.Get_Reason()} member={Member.Get_Member().ToString()} rank={Member.Get_Rank()} rev={InEvent.Get_QueueRevision()}");
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnPressure(FCk_Handle_Queue InQueue, FCk_Queue_Pressure InPressure)
    {
        if (InQueue == _Queue) { AddTrace(f"GOAP pressure: count={InPressure.Get_MemberCount()} soft={InPressure.Get_IsSoftLimited()} hard={InPressure.Get_IsHardLimited()}"); }
    }

    UFUNCTION()
    private void OnFormation(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        if (InQueue == _Queue) { AddTrace(f"GOAP formation: {InState.Get_State()} reason={InState.Get_Reason()} retry={InState.Get_RetryEpisode()}"); RefreshDisplays(); }
    }

    UFUNCTION()
    private void OnInvalidated(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        if (InQueue != _Queue) { return; }
        AddTrace(f"GOAP invalidated: reason={InState.Get_Reason()} rev={InState.Get_QueueRevision()}");
        RefreshDisplays();
    }

    private void CyclePopulation()
    {
        if (_Population == 6) { _Population = 12; }
        else if (_Population == 12) { _Population = 24; }
        else if (_Population == 24) { _Population = 30; }
        else if (_Population == 30) { _Population = 32; }
        else { _Population = 6; }
        Ck_GymQueue_Start();
    }

    private void CycleLayout()
    {
        _Linear = !_Linear;
        if (ck::IsValid(_Queue))
        {
            const auto Layout = _Linear ? ECk_Queue_LayoutAlgorithm::Linear : ECk_Queue_LayoutAlgorithm::OrthogonalSnake;
            _Queue.Request_SetLayout(FCk_Request_Queue_SetLayout(Layout));
            AddTrace(f"OPTION: layout changed to {GetLayoutLabel()}; all slots receive a new revision.");
        }
        RefreshDisplays();
    }

    private void CycleOrigins() { _OriginMode = (_OriginMode + 1) % 3; ApplyOriginsLive(); }
    private void CycleNavigation() { _TargetBlocked = !_TargetBlocked; ApplyTargetBlocker(); RefreshDisplays(); }
    private void CycleVisualization() { _QueueVisualization = !_QueueVisualization; ApplyVisualizationSetting(); RefreshDisplays(); }

    private void ApplyOriginsLive()
    {
        if (ck::Is_NOT_Valid(_Queue)) { return; }
        RestoreTargetBlocker();
        _Queue.Request_SetOrigins(FCk_Request_Queue_SetOrigins(GetConfiguredOrigins()));
        ApplyTargetBlocker();
        AddTrace(f"OPTION: origins changed to {GetOriginModeLabel()}; queue will reflow with fresh assignments.");
        RefreshDisplays();
    }

    private TArray<FCk_Queue_Origin> GetConfiguredOrigins() const
    {
        auto Origins = TArray<FCk_Queue_Origin>();
        if (_OriginMode == 1)
        { Origins.Add(FCk_Queue_Origin(FTransform(FRotator(0.0f, 90.0f, 0.0f), FVector(280.0f, 0.0f, 0.0f), FVector::OneVector))); }
        else if (_OriginMode == 2)
        {
            auto Left = FCk_Queue_Origin(FTransform(FRotator::ZeroRotator, FVector(0.0f, -280.0f, 0.0f), FVector::OneVector));
            Left.Set_Weight(1);
            auto Right = FCk_Queue_Origin(FTransform(FRotator::ZeroRotator, FVector(0.0f, 280.0f, 0.0f), FVector::OneVector));
            Right.Set_Weight(2);
            Origins.Add(Left);
            Origins.Add(Right);
        }
        else { Origins.Add(FCk_Queue_Origin(FTransform::Identity)); }
        return Origins;
    }

    private void ApplyTargetBlocker()
    {
        const bool RemovedBlocker = RestoreTargetBlocker();
        if (HasAuthority() == false || !_TargetBlocked || ck::Is_NOT_Valid(_QueueOwner))
        {
            if (RemovedBlocker)
            {
                utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);
                AddTrace("OPTION: target navigation restored; NavigationChanged should reopen formation.");
            }
            return;
        }
        const auto Targets = GetConfiguredTargetTransforms();
        for (const auto& Target : Targets)
        {
            auto Blocker = utils_nav_area_markup::Request_Create(_PcEntity, Target,
                FVector(TargetBlockerHalfExtent, TargetBlockerHalfExtent, 300.0f), UNavArea_Null);
            if (ck::IsValid(Blocker)) { _TargetBlockers.Add(Blocker); }
        }
        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);
        AddTrace(f"OPTION: {_TargetBlockers.Num()} TARGET footprint(s) are NavArea_Null. Starts and approach remain navigable; formation retries then waits for navigation change.");
    }

    private bool RestoreTargetBlocker()
    {
        bool Removed = false;
        for (auto Blocker : _TargetBlockers)
        {
            if (ck::Is_NOT_Valid(Blocker)) { continue; }
            utils_nav_area_markup::Request_Destroy(Blocker);
            Removed = true;
        }
        _TargetBlockers.Empty();
        return Removed;
    }

    private TArray<FTransform> GetConfiguredTargetTransforms() const
    {
        auto Targets = TArray<FTransform>();
        if (ck::Is_NOT_Valid(_QueueOwner)) { return Targets; }
        const auto OwnerTransform = utils_transform::Get_EntityCurrentTransform(utils_transform::DoCastChecked(_QueueOwner));
        const auto Origins = GetConfiguredOrigins();
        for (const auto& Origin : Origins)
        { Targets.Add(Origin.Get_LocalTransform() * OwnerTransform); }
        return Targets;
    }

    private void DestroyFirstQueuedAgent()
    {
        if (ck::Is_NOT_Valid(_Queue)) { return; }
        for (auto Agent : _Agents)
        {
            if (ck::IsValid(Agent) && _Queue.Get_IsMember(FCk_Handle(Agent)))
            {
                utils_entity_lifetime::Request_DestroyEntity(Agent);
                AddTrace("ACTION: first valid queued agent destroyed without Leave; reconciliation must reflow survivors.");
                RefreshDisplays();
                return;
            }
        }
        AddTrace("ACTION: no valid admitted agent was available to destroy.");
        RefreshDisplays();
    }

    private void MarkRejectedAgent(FCk_Handle InRequestOwner)
    {
        for (auto Agent : _Agents)
        {
            if (FCk_Handle(Agent) != InRequestOwner) { continue; }
            utils_crowd_agent::Set_DebugColor(Agent, FLinearColor(1.0f, 0.05f, 0.05f, 1.0f));
            if (_RejectedAgents.Contains(Agent) == false) { _RejectedAgents.Add(Agent); }
            return;
        }
    }

    private void ApplyVisualizationSetting() { utils_queue::Set_DebugDrawEnabled(_QueueVisualization); }

    private void DrawScenarioDiagnostics()
    {
        if (_QueueVisualization == false) { return; }
        const auto QueueCategory = utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym");
        for (const auto& Snapshot : utils_queue::Get_DebugSnapshots(_PcEntity))
        {
            if (Snapshot.Get_Category() != QueueCategory) { continue; }
            for (int32 OriginIndex = 0; OriginIndex < Snapshot.Get_OriginWorldTransforms().Num(); ++OriginIndex)
            {
                const auto Target = Snapshot.Get_OriginWorldTransforms()[OriginIndex];
                const auto Location = Target.GetLocation();
                const auto Cyan = FLinearColor(0.1f, 0.9f, 1.0f, 1.0f);
                utils_debug_draw::DrawDebugCross(Location, 85.0f, Cyan, 0.0f, 3.0f);
                utils_debug_draw::DrawDebugArrow(Location, Location + Target.Rotator().GetForwardVector() * 140.0f, 26.0f, Cyan, 0.0f, 3.0f);
                utils_debug_draw::DrawDebugString(Location + FVector(0.0f, 0.0f, 70.0f), f"TARGET {OriginIndex}", Cyan, 0.0f);
            }
        }

        if (_TargetBlocked && _TargetBlockers.Num() > 0 && ck::IsValid(_QueueOwner))
        {
            const auto Red = FLinearColor(1.0f, 0.1f, 0.1f, 1.0f);
            for (const auto& Target : GetConfiguredTargetTransforms())
            {
                utils_debug_draw::DrawDebugBox(Target.GetLocation(), FVector(TargetBlockerHalfExtent, TargetBlockerHalfExtent, 300.0f), Red, Target.Rotator(), 0.0f, 3.0f);
                utils_debug_draw::DrawDebugString(Target.GetLocation() + FVector(0.0f, 0.0f, 320.0f), "TARGET BLOCKED: NAVAREA_NULL", Red, 0.0f);
            }
        }

        for (auto Agent : _RejectedAgents)
        {
            if (ck::Is_NOT_Valid(Agent)) { continue; }
            const auto Location = utils_transform::Get_EntityCurrentLocation(Agent.As_Transform());
            utils_debug_draw::DrawDebugString(Location + FVector(0.0f, 0.0f, AgentHeight + 20.0f), "REJECTED: HARD LIMIT", FLinearColor(1.0f, 0.05f, 0.05f, 1.0f), 0.0f);
        }
    }

    private FString GetPopulationLabel() const { return _Population == 32 ? "32 (30 admitted + 2 rejected)" : f"{_Population}"; }
    private FString GetLayoutLabel() const { return _Linear ? "Linear" : "Orthogonal snake"; }
    private FString GetOriginModeLabel() const { if (_OriginMode == 1) { return "Moved / rotated"; } if (_OriginMode == 2) { return "Two weighted"; } return "Single"; }
    private FString GetNavigationLabel() const { return _TargetBlocked ? "All targets blocked" : "Targets reachable"; }

    private FVector StationLocal_To_World(FVector InLocalOffset)
    {
        return Get_StationAnchorTransform("Gym.Queue.Live", ECk_GymStation_Anchor::FootprintCenter).TransformPosition(InLocalOffset);
    }

    private FTransform Get_QueueOwnerTransform()
    {
        const auto StationTransform = Get_StationAnchorTransform("Gym.Queue.Live", ECk_GymStation_Anchor::FootprintCenter);
        return FTransform(StationTransform.Rotator(), StationTransform.TransformPosition(FVector(QueueFwdOffset, 0.0f, 0.0f)), FVector::OneVector);
    }

    private bool TrySpawnFloor()
    {
        if (System::IsValid(_Floor)) { return true; }
        _Floor = SpawnActor(ACk_Gym_Floor, FVector::ZeroVector, FRotator::ZeroRotator, NAME_None, true);
        if (_Floor == nullptr) { ck::Warning("Queue gym failed to spawn its navigation floor"); return false; }
        _Floor.SetActorScale3D(FVector(75.0f, 75.0f, 0.5f));
        FinishSpawningActor(_Floor);
        return true;
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FVector InLocation, int32 InIndex)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(_QueueOwner);
        Entity.Set_DebugName(FName(f"QueueGym_Agent_{InIndex}"));
        FVector Snapped;
        auto Location = InLocation;
        if (utils_nav::Try_ProjectOntoNavmesh(_PcEntity, InLocation, 250.0f, Snapped, 400.0f)) { Location = Snapped; }
        auto Transform = utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, Location, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(Transform, FCk_Fragment_CrowdAgent_ParamsData(AgentRadius, AgentHeight));
        utils_crowd_agent::Set_DebugColor(Agent, FLinearColor::MakeFromHSV8(uint8((InIndex * 47) % 255), 210, 240));
        utils_velocity::Add(Entity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Entity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Entity);
        return Agent;
    }

    private void SpawnAndJoinAgents(int32 InCount)
    {
        const auto QueueOwnerTransform = Get_QueueOwnerTransform();
        for (int32 Added = 0; Added < InCount; ++Added)
        {
            const auto Index = _Agents.Num();
            const auto X = -500.0f + float(Math::IntegerDivisionTrunc(Index, 6)) * 140.0f;
            const auto Y = (float(Index % 6) - 2.5f) * 130.0f;
            auto Agent = SpawnAgent(QueueOwnerTransform.TransformPosition(FVector(X, Y, SpawnZ)), Index);
            _Agents.Add(Agent);
            Agent.Request_JoinQueue(_Queue, FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
        }
    }

    private void ResetScenario()
    {
        RestoreTargetBlocker();
        if (ck::IsValid(_NavProbeEntity)) { utils_entity_lifetime::Request_DestroyEntity(_NavProbeEntity); }
        _NavProbeEntity = FCk_Handle();
        for (auto Agent : _Agents) { if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); } }
        _Agents.Empty();
        _RejectedAgents.Empty();
        if (ck::IsValid(_QueueOwner)) { utils_entity_lifetime::Request_DestroyEntity(_QueueOwner); }
        _QueueOwner = FCk_Handle();
        _Queue = FCk_Handle_Queue();
    }

    private void EmitSnapshot()
    {
        if (ck::Is_NOT_Valid(_Queue)) { AddTrace("DIGEST: queue is invalid"); return; }
        const auto Members = _Queue.Get_Members();
        const auto Pressure = _Queue.Get_Pressure();
        AddTrace(f"DIGEST: count={Pressure.Get_MemberCount()} hard={Pressure.Get_IsHardLimited()} rejected={_RejectedAgents.Num()} revision={_Queue.Get_Revision()} layout={_Queue.Get_LayoutAlgorithm()}");
        for (auto Member : Members) { AddTrace(f"  ticket={Member.Get_Ticket()} origin={Member.Get_OriginIndex()} rank={Member.Get_Rank()} state={Member.Get_State()} assignment={Member.Get_AssignmentRevision()}"); }
    }

    private void AddTrace(const FString& InLine)
    {
        _Trace.Add(InLine);
        if (_Trace.Num() > 7) { _Trace.RemoveAt(0); }
        ck::Trace(f"[QueueGym] {InLine}");
    }

    private void RefreshDisplays()
    {
        if (ck::Is_NOT_Valid(_Queue)) { return; }
        const auto Pressure = _Queue.Get_Pressure();
        auto DisplayText = "GOAP-REACTIVE QUEUE\n";
        DisplayText = f"{DisplayText}population={GetPopulationLabel()} members={Pressure.Get_MemberCount()} rejected={_RejectedAgents.Num()} soft={Pressure.Get_IsSoftLimited()} hard={Pressure.Get_IsHardLimited()}\n";
        DisplayText = f"{DisplayText}layout={GetLayoutLabel()} origins={GetOriginModeLabel()} navigation={GetNavigationLabel()} visualization={_QueueVisualization}\n";
        DisplayText = f"{DisplayText}revision={_Queue.Get_Revision()} joins={_JoinSucceeded}/{_JoinRejected} events={_EventCount}\n";
        for (auto Line : _Trace) { DisplayText = f"{DisplayText}{Line}\n"; }
        CkGym_Common::Update_StationDisplay(Get_StationHandle("Gym.Queue.Live"), "QUEUE: LIVE CROWD AGENTS", DisplayText,
            "Options: 1 Reset | 2 Population | 3 Layout | 4 Origins | 5 Navigation | 6 Visualization | 7 Advance | 8 Destroy agent | 9 Destroy owner | 0 Snapshot");
    }

    private void AddStation(TArray<FCkGym_Station_SpawnParams_Payload>& InOutStations, FName InTag, FString InTitle, FString InDescription)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.AutoSize = true;
        Station.Title = FText::FromString(InTitle);
        auto Description = TArray<FText>();
        Description.Add(FText::FromString(InDescription));
        Station.Description = Description;
        InOutStations.Add(Station);
    }
}
