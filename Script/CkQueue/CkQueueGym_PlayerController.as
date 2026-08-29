// Language=angelscript
// --------------------------------------------------------------------------------------------------------------------
// QUEUE GYM - state-driven CrowdAgent adapter demo. Gym options exercise the public queue boundary and the
// resulting events are deliberately the same surface that a GOAP planner would consume.
// --------------------------------------------------------------------------------------------------------------------

struct FCk_QueueGym_RouteState
{
    FCk_Handle_Queue SelectedQueue;
    TArray<FCk_Handle_Queue> FallbackQueues;
    int32 NextFallbackIndex = 0;
}

struct FCk_QueueGym_AdvanceJob
{
    FCk_Handle_Queue Queue;
    FCk_Handle_CrowdAgent ServingAgent;
    FVector NominalSlotLocation;
    bool RequestCompleted = false;
    bool RequestSucceeded = false;
    bool ServingCaptured = false;
}

struct FCk_QueueGym_ServedExitJob
{
    FCk_Handle_Queue Queue;
    FCk_Handle_CrowdAgent Agent;
    FVector NominalSlotLocation;
}

class ACk_QueueGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _PcEntity;
    private FCk_Handle _LiveStation;
    private FCk_Handle _NavProbeEntity;
    private FCk_Handle _CoordinatorOwner;
    private FCk_Handle_QueueCoordinator _Coordinator;
    private TArray<FCk_Handle> _QueueOwners;
    private TArray<FCk_Handle_Queue> _Queues;
    // Primary is retained only for the existing deliberately single-queue visual presets.
    private FCk_Handle _QueueOwner;
    private FCk_Handle_Queue _Queue;
    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private TArray<FCk_Handle_CrowdAgent> _RejectedAgents;
    private TArray<FVector> _AgentDiagnosticGoals;
    private TArray<bool> _AgentHasDiagnosticGoal;
    private TArray<UCk_NavAreaMarkup_UE> _TargetBlockers;
    private TArray<AActor> _LayoutBlockers;
    private ACk_Gym_Floor _Floor = nullptr;
    private TArray<FString> _Trace;
    private int32 _JoinSucceeded = 0;
    private int32 _JoinRejected = 0;
    private int32 _EventCount = 0;
    private int32 _Population = 6;
    private int32 _HardLimit = 30;
    private int32 _QueueCount = 2;
    // The increment the agent-add row applies. 5 is what the old console command defaulted to.
    private int32 _AddAgentsStep = 5;
    private int32 _SelectedQueueIndex = 0;
    private bool _CoordinatorNearestFirst = false;
    private bool _PrimaryOwnerMoved = false;
    // 0 Open, 1 Target unreachable, 2 Tight corridor, 3 90-degree corner, 4 Constrained snake.
    private int32 _EnvironmentMode = 0;
    private bool _Linear = false;
    private bool _ClaimSlotsOnReach = false;
    private bool _ReserveByTicketOrder = false;
    private bool _ReserveAssignmentPhaseSpread = true;
    private float _ReserveAssignmentRefreshSeconds = 0.25f;
    // This is a complete authored scenario, not a configuration the normal controls happen to resemble.
    // Reset intentionally keeps it true so the visual race is replayable.
    private bool _ContestedSlotRacePreset = false;
    private bool _ReservationScatterPreset = false;
    private int64 _ContestedFirstWinnerTicket = 0;
    private bool _PreviousQueueVisualization = false;
    private bool _CapturedQueueVisualization = false;
    private bool _CapturedCrowdVisualization = false;
    private bool _PreviousCrowdAgentBody = false;
    private bool _PreviousCrowdSeparation = false;
    private bool _PreviousCrowdBreadcrumbs = false;
    private bool _PreviousCrowdPlannedPaths = false;
    private bool _PreviousCrowdPathTrouble = false;
    private bool _PreviousCrowdNavProjection = false;
    private bool _PreviousCrowdAgentRings = false;
    private bool _PreviousCrowdBlockStatus = false;
    private bool _AutoStarted = false;
    private bool _AwaitingEnvironmentTopology = false;
    private bool _TopologyValidated = false;
    private bool _AdmissionIssued = false;
    private bool _TopologyPathRequested = false;
    private bool _ScatterNearAdmissionPending = false;
    private float _ScatterFarReservationDisplaySeconds = 0.0f;
    private bool _PlannerRetryPending = false;
    private int32 _PlannerRetriesAwaiting = 0;
    private int32 _RegisteredQueueCount = 0;
    private TArray<FCk_Handle_CrowdAgent> _SelectionPendingAgents;
    private TArray<FCk_QueueGym_RouteState> _AgentRoutes;
    private TArray<FCk_QueueGym_AdvanceJob> _AdvanceJobs;
    private TArray<FCk_QueueGym_ServedExitJob> _PendingServedExits;
    private FCk_Handle_Queue _AdvancingQueue;
    private FCk_Handle_CrowdAgent _ServedExitAgent;
    private FVector _ServedExitDepartureLocation;
    private FVector _ServedExitNominalSlotLocation;
    private FVector _ServedExitGoal;
    private int32 _ServedExitCorrelation = 0;
    private int32 _RejectedExitCorrelation = 0;
    private int32 _ServedExitAttempts = 0;
    private int32 _ServedExitLaneSerial = 0;
    private bool _ServedExitDestroyRequested = false;
    private bool _ServedExitAwaitingDispatch = false;
    private float _ServedExitAttemptElapsedSeconds = 0.0f;
    private FVector _TopologyProbeStart;
    private FVector _TopologyProbeGoal;
    private TArray<FVector> _TopologyClearWitnesses;

    private const float SpawnZ = 110.0f;
    private const float QueueFwdOffset = 1000.0f;
    private const float AgentRadius = 42.0f;
    private const float AgentHeight = 192.0f;
    private const float TargetBlockerHalfExtent = 180.0f;
    // At least 300uu: more than two 42uu agent radii plus a generous movement/arrival margin.
    private const float ServedExitClearanceRadiusUu = 300.0f;
    private const float ServedExitDispatchTimeoutSeconds = 1.0f;
    private const float ServedExitMovementTimeoutSeconds = 8.0f;
    private const float ScatterFarReservationHoldSeconds = 1.5f;
    private const int32 MaxServedExitAttempts = 3;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false) { return TArray<FCkGym_Station_SpawnParams_Payload>(); }
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        AddStation(Stations, n"Gym.Queue.Live", "QUEUE: LIVE CROWD AGENTS",
            "Use the numbered options panel for direct queue scenarios. Press R for the contested-slot race or K for reservation scatter: far tickets reserve first, then nearby admissions prove incumbent-first compaction. Queue and all Crowd-agent debug overlays are enabled while this gym is active.");
        return Stations;
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(MakeNumberedControl(0, "Reset demo"));
        Rows.Add(MakeNumberedControl(1, "Population", GetPopulationLabel()));
        Rows.Add(MakeNumberedControl(2, "Layout", GetLayoutLabel()));
        const bool EnvironmentIsOpen = _EnvironmentMode == 0;
        Rows.Add(MakeNumberedControl(3, "Queue bank", GetQueueBankLabel(), EnvironmentIsOpen));
        Rows.Add(MakeNumberedControl(4, "Environment", GetEnvironmentLabel()));
        Rows.Add(MakeNumberedControl(5, "Advance all queues", GetAdvanceStatusLabel(), Get_CanAdvanceQueueBank()));
        Rows.Add(MakeNumberedControl(6, "Destroy first queued agent"));
        Rows.Add(MakeNumberedControl(7, "Destroy selected queue owner"));
        Rows.Add(MakeNumberedControl(8, "Slot claiming", GetSlotClaimingLabel()));
        Rows.Add(CkGym_Control::Action(EKeys::L, "L", f"Cycle queue limit (reset): {_HardLimit}"));
        Rows.Add(CkGym_Control::Action(EKeys::P, "P", f"Reserve assignment: {GetReserveAssignmentPolicyLabel()}"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Run contested slot race"));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Run reservation scatter"));
        Rows.Add(CkGym_Control::Action(EKeys::T, "T", f"Refresh phase spread: {GetReserveAssignmentPhaseSpreadLabel()}"));
        Rows.Add(CkGym_Control::Action(EKeys::Y, "Y", f"Refresh interval: {GetReserveAssignmentRefreshSecondsLabel()}"));
        Rows.Add(CkGym_Control::Action(EKeys::I, "I", f"Coordinator policy: {GetCoordinatorPolicyLabel()}"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", f"Selected queue: {GetSelectedQueueLabel()}"));
        Rows.Add(CkGym_Control::Action(EKeys::M, "M", f"Move primary queue, forces 1 queue: {GetPrimaryOwnerMovedLabel()}"));
        Rows.Add(CkGym_Control::Action(EKeys::G, "G", "Print snapshot / GOAP trace"));
        Rows.Add(CkGym_Control::Cycle(EKeys::N, "N", "Agent add step", f"+{_AddAgentsStep}"));
        Rows.Add(CkGym_Control::Action(EKeys::J, "J", f"Add {_AddAgentsStep} agents (rebuilds, caps at 32)"));
        Rows.Add(CkGym_Control::Status("Destroy an agent by index", "Ck_GymQueue_DestroyAgent N"));
        return Rows;
    }

    FString Get_ControlPanelTitle() override { return "QUEUE GYM OPTIONS"; }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (HasAuthority() == false) { return; }
        if (InRowIndex == 0) { Request_StartLiveDemo(); return; }
        if (InRowIndex == 1) { CyclePopulation(); return; }
        if (InRowIndex == 2) { CycleLayout(); return; }
        if (InRowIndex == 3) { CycleQueueBank(); return; }
        if (InRowIndex == 4) { CycleEnvironment(); return; }
        if (InRowIndex == 5) { Request_AdvanceReadyQueues(); return; }
        if (InRowIndex == 6) { DestroyFirstQueuedAgent(); return; }
        if (InRowIndex == 7) { Request_DestroySelectedQueueOwner(); return; }
        if (InRowIndex == 8) { CycleSlotClaiming(); return; }
        if (InRowIndex == 9) { CycleHardLimit(); return; }
        if (InRowIndex == 10) { CycleReserveAssignmentPolicy(); return; }
        if (InRowIndex == 11) { Request_RunContestedSlotRace(); return; }
        if (InRowIndex == 12) { Request_RunReservationScatter(); return; }
        if (InRowIndex == 13) { CycleReserveAssignmentPhaseSpread(); return; }
        if (InRowIndex == 14) { CycleReserveAssignmentRefreshSeconds(); return; }
        if (InRowIndex == 15) { CycleCoordinatorPolicy(); return; }
        if (InRowIndex == 16) { CycleSelectedQueue(); return; }
        if (InRowIndex == 17) { MovePrimaryQueue(); return; }
        if (InRowIndex == 18) { EmitSnapshot(); RefreshDisplays(); return; }
        if (InRowIndex == 19) { CycleAddAgentsStep(); return; }
        if (InRowIndex == 20) { AddAgents(_AddAgentsStep); }
        // Row 21 is a Status row - it holds no key and never arrives here.
    }

    // Split from the old console command so the add STEP is picked on one row and applied on the next,
    // the same shape the population row already has: a value you choose, then a rebuild you ask for.
    private void CycleAddAgentsStep()
    {
        _AddAgentsStep = _AddAgentsStep == 1 ? 5 : _AddAgentsStep == 5 ? 20 : 1;
    }

    private void AddAgents(int32 InCount)
    {
        if (InCount <= 0) { return; }
        ClearContestedSlotRacePreset();
        _Population = Math::Min(32, _Population + InCount);
        Request_StartLiveDemo();
    }

    private void MovePrimaryQueue()
    {
        ClearContestedSlotRacePreset();
        _QueueCount = 1;
        _PrimaryOwnerMoved = !_PrimaryOwnerMoved;
        Request_StartLiveDemo();
    }

    private FCkGym_ControlRow MakeNumberedControl(
        int32 InIndex,
        FString InLabel,
        FString InValue = "",
        bool InEnabled = true) const
    {
        auto Row = CkGym_Control::Numbered(InIndex, InLabel, false, InEnabled);
        Row.Value = InValue;
        return Row;
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
        utils_queue::Set_DebugDrawEnabled(true);
        CaptureAndEnableCrowdVisualization();
        _LiveStation = Get_StationHandle("Gym.Queue.Live");
        if (ck::Is_NOT_Valid(_LiveStation)) { ck::Warning("Queue gym requires its live station"); return; }

        _AutoStarted = false;
        if (TrySpawnFloor() == false) { return; }
        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);

        CancelEnvironmentTopologyProbe();

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
    void Tick(float InDeltaSeconds)
    {
        PollEnvironmentTopology();
        TickScatterNearAdmission(InDeltaSeconds);
        TickServedExitClearance(InDeltaSeconds);
        DrawScenarioDiagnostics();
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        CancelServedExit();
        CancelEnvironmentTopologyProbe();
        ClearEnvironmentGeometry();
        if (_CapturedQueueVisualization)
        { utils_queue::Set_DebugDrawEnabled(_PreviousQueueVisualization); }
        RestoreCrowdVisualization();
    }

    private void CaptureAndEnableCrowdVisualization()
    {
        if (_CapturedCrowdVisualization == false)
        {
            _PreviousCrowdAgentBody = utils_crowd_debug_settings::Get_DrawAgentBody();
            _PreviousCrowdSeparation = utils_crowd_debug_settings::Get_DrawSeparation();
            _PreviousCrowdBreadcrumbs = utils_crowd_debug_settings::Get_DrawBreadcrumbs();
            _PreviousCrowdPlannedPaths = utils_crowd_debug_settings::Get_DrawPlannedPaths();
            _PreviousCrowdPathTrouble = utils_crowd_debug_settings::Get_DrawPathTrouble();
            _PreviousCrowdNavProjection = utils_crowd_debug_settings::Get_DrawNavProjection();
            _PreviousCrowdAgentRings = utils_crowd_debug_settings::Get_DrawAgentRings();
            _PreviousCrowdBlockStatus = utils_crowd_debug_settings::Get_DrawBlockStatus();
            _CapturedCrowdVisualization = true;
        }

        SetCrowdVisualization(true, true, true, true, true, true, true, true);
    }

    private void RestoreCrowdVisualization()
    {
        if (_CapturedCrowdVisualization == false) { return; }
        SetCrowdVisualization(
            _PreviousCrowdAgentBody,
            _PreviousCrowdSeparation,
            _PreviousCrowdBreadcrumbs,
            _PreviousCrowdPlannedPaths,
            _PreviousCrowdPathTrouble,
            _PreviousCrowdNavProjection,
            _PreviousCrowdAgentRings,
            _PreviousCrowdBlockStatus);
        _CapturedCrowdVisualization = false;
    }

    private void SetCrowdVisualization(
        bool InAgentBody,
        bool InSeparation,
        bool InBreadcrumbs,
        bool InPlannedPaths,
        bool InPathTrouble,
        bool InNavProjection,
        bool InAgentRings,
        bool InBlockStatus)
    {
        SetCrowdVisualizationCVar("ck.Crowd.Debug.AgentBody", InAgentBody);
        SetCrowdVisualizationCVar("ck.Crowd.Debug", InSeparation);
        SetCrowdVisualizationCVar("ck.Crowd.DrawBreadcrumbs", InBreadcrumbs);
        SetCrowdVisualizationCVar("ck.Crowd.DrawPlannedPaths", InPlannedPaths);
        SetCrowdVisualizationCVar("ck.Crowd.DrawPathTrouble", InPathTrouble);
        SetCrowdVisualizationCVar("ck.Crowd.DrawNavProjection", InNavProjection);
        SetCrowdVisualizationCVar("ck.Crowd.DrawAgentRings", InAgentRings);
        SetCrowdVisualizationCVar("ck.Crowd.DrawBlockStatus", InBlockStatus);
    }

    private void SetCrowdVisualizationCVar(const FString& InName, bool InEnabled)
    {
        const auto Value = InEnabled ? 1 : 0;
        System::ExecuteConsoleCommand(f"{InName} {Value}");
    }

    UFUNCTION()
    private void OnNavProbeReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (InHandle != _NavProbeEntity || _AutoStarted) { return; }
        _AutoStarted = true;
        Request_StartLiveDemo();
    }

    UFUNCTION()
    private void OnNavProbeFailed(FCk_Handle InHandle)
    {
        if (InHandle != _NavProbeEntity) { return; }
        ck::Warning("Queue gym navmesh probe failed; auto-start skipped until the floor is navigable");
    }

    UFUNCTION()
    private void OnEnvironmentTopologyPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (InHandle != _NavProbeEntity || !_AwaitingEnvironmentTopology || _AdmissionIssued || _EnvironmentMode == 1) { return; }

        FVector StartProjected;
        FVector GoalProjected;
        const bool StartProjects = utils_nav::Try_ProjectOntoNavmesh(_PcEntity, _TopologyProbeStart, 30.0f, StartProjected, 400.0f);
        const bool GoalProjects = utils_nav::Try_ProjectOntoNavmesh(_PcEntity, _TopologyProbeGoal, 30.0f, GoalProjected, 400.0f);
        auto Waypoints = InResult.Get_Waypoints();
        const bool ReachesGoal = Waypoints.Num() > 0 && (Waypoints[Waypoints.Num() - 1] - _TopologyProbeGoal).Size() <= 200.0f;
        if (StartProjects && GoalProjects && ReachesGoal)
        {
            AdmitAfterEnvironmentTopology("reachable probe projected start/target and reached the intended target");
            return;
        }

        AddTrace("TOPOLOGY: reachable probe resolved before its intended start/target/path contract; still waiting.");
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnEnvironmentTopologyPathFailed(FCk_Handle InHandle)
    {
        if (InHandle != _NavProbeEntity || !_AwaitingEnvironmentTopology || _AdmissionIssued || _EnvironmentMode == 1) { return; }
        AddTrace("TOPOLOGY: reachable environment path failed; no agents admitted. Choose another environment or reset.");
        RefreshDisplays();
    }

    // Rebuilds exactly the selected configuration; every option row funnels through here.
    private void Request_StartLiveDemo()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_LiveStation)) { return; }
        if (_SelectedQueueIndex < 0 || _SelectedQueueIndex >= _QueueCount)
        { _SelectedQueueIndex = 0; }
        _AutoStarted = true;
        utils_queue::Set_DebugDrawEnabled(true);
        CancelServedExit();
        const bool RemovedEnvironmentGeometry = ResetScenario();
        _Trace.Empty();
        _JoinSucceeded = 0;
        _JoinRejected = 0;
        _EventCount = 0;
        _PlannerRetryPending = false;
        _PlannerRetriesAwaiting = 0;
        _ContestedFirstWinnerTicket = 0;
        _ScatterNearAdmissionPending = false;
        _ScatterFarReservationDisplaySeconds = 0.0f;
        _TopologyValidated = false;
        _RejectedExitCorrelation = 0;

        _CoordinatorOwner = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        auto CoordinatorParams = FCk_Fragment_QueueCoordinator_ParamsData();
        CoordinatorParams.Set_RequiredQueueCategory(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        CoordinatorParams.Set_SelectionPolicy(_CoordinatorNearestFirst
            ? ECk_QueueCoordinator_SelectionPolicy::NearestThenLeastMembers
            : ECk_QueueCoordinator_SelectionPolicy::LeastMembersThenDistance);
        _Coordinator = utils_queue_coordinator::Add(_CoordinatorOwner, CoordinatorParams);
        _RegisteredQueueCount = 0;
        for (int32 QueueIndex = 0; QueueIndex < _QueueCount; ++QueueIndex)
        { CreateAndRegisterQueue(QueueIndex); }
        _QueueOwner = _QueueOwners.IsEmpty() ? FCk_Handle() : _QueueOwners[0];
        _Queue = _Queues.IsEmpty() ? FCk_Handle_Queue() : _Queues[0];

        ApplyEnvironment(RemovedEnvironmentGeometry);
        BeginEnvironmentTopologyProbe();
        AddTrace(f"START: {GetPopulationLabel()} selected; bank={GetQueueBankLabel()} policy={GetCoordinatorPolicyLabel()} layout={GetLayoutLabel()} environment={GetEnvironmentLabel()}; waiting for Queue registrations and rebuilt topology before admission.");
        RefreshDisplays();
    }

    private void Request_AdvanceReadyQueues()
    {
        if (HasAuthority() == false || Get_CanAdvanceQueueBank() == false)
        {
            AddTrace("ACTION: bank advance rejected; at least one Queue needs a rank-0 AtFront member and no advance batch may be active.");
            RefreshDisplays();
            return;
        }

        auto QueuesToAdvance = TArray<FCk_Handle_Queue>();
        for (auto Queue : _Queues)
        {
            if (Get_HasReadyFront(Queue)) { QueuesToAdvance.Add(Queue); }
        }
        for (auto Queue : QueuesToAdvance)
        {
            auto Job = FCk_QueueGym_AdvanceJob();
            Job.Queue = Queue;
            _AdvanceJobs.Add(Job);
        }
        for (int32 QueueIndex = 0; QueueIndex < QueuesToAdvance.Num(); ++QueueIndex)
        {
            auto Queue = QueuesToAdvance[QueueIndex];
            Queue.Request_Advance(FCk_Request_Queue_Advance(),
                FCk_Delegate_Request_OnCompleted(this, n"OnAdvanceCompleted"));
        }
        AddTrace(f"ACTION: advance requested for all {QueuesToAdvance.Num()} ready Queue(s); each completion is tracked by Queue.");
        RefreshDisplays();
    }

    // The later tickets deliberately start closer. ClaimFirstAvailableOnReach therefore proves that
    // physical arrival, not ticket order, owns each provisional slot.
    private void Request_RunContestedSlotRace()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_LiveStation)) { return; }
        _ContestedSlotRacePreset = true;
        _ReservationScatterPreset = false;
        _Population = 6;
        _HardLimit = 30;
        _QueueCount = 1;
        _EnvironmentMode = 0;
        _Linear = true;
        _ClaimSlotsOnReach = true;
        Request_StartLiveDemo();
    }

    private void CreateAndRegisterQueue(int32 InQueueIndex)
    {
        auto QueueOwner = utils_entity_lifetime::Request_CreateEntity(_CoordinatorOwner);
        utils_transform::Add(QueueOwner, Get_QueueOwnerTransform(InQueueIndex), ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_Category(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        Params.Set_SlotSpacingUu(GetConfiguredSlotSpacingUu());
        Params.Set_SlotClaimRadiusUu(30.0f);
        Params.Set_SlotSettleRadiusUu(10.0f);
        Params.Set_SlotReacquireRadiusUu(20.0f);
        Params.Set_HardLimit(_HardLimit);
        Params.Set_SoftLimit(GetConfiguredSoftLimit());
        Params.Set_AgentRadiusUu(AgentRadius);
        Params.Set_AgentHalfHeightUu(AgentHeight * 0.5f);
        Params.Set_LayoutAlgorithm(_Linear ? ECk_Queue_LayoutAlgorithm::Linear : ECk_Queue_LayoutAlgorithm::OrthogonalSnake);
        Params.Set_SlotClaimPolicy(_ClaimSlotsOnReach
            ? ECk_Queue_SlotClaimPolicy::ClaimFirstAvailableOnReach
            : ECk_Queue_SlotClaimPolicy::ReserveOnFormation);
        Params.Set_ReserveAssignmentPolicy(_ReserveByTicketOrder
            ? ECk_Queue_ReserveAssignmentPolicy::TicketOrder
            : ECk_Queue_ReserveAssignmentPolicy::DistanceThenTicket);
        Params.Set_ReserveAssignmentRefreshSeconds(_ReserveAssignmentRefreshSeconds);
        Params.Set_ReserveAssignmentRefreshPhaseSpread(_ReserveAssignmentPhaseSpread
            ? ECk_EnableDisable::Enable
            : ECk_EnableDisable::Disable);
        auto Queue = utils_queue::Add(QueueOwner, Params);
        Queue.BindTo_OnQueueMemberStateChanged(FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberEvent"));
        Queue.BindTo_OnQueuePressureChanged(FCk_Delegate_Queue_OnPressureChanged(this, n"OnPressure"));
        Queue.BindTo_OnQueueFormationStateChanged(FCk_Delegate_Queue_OnFormationStateChanged(this, n"OnFormation"));
        Queue.BindTo_OnQueueInvalidated(FCk_Delegate_Queue_OnInvalidated(this, n"OnInvalidated"));
        _QueueOwners.Add(QueueOwner);
        _Queues.Add(Queue);
        _Coordinator.Request_RegisterQueue(FCk_Request_QueueCoordinator_RegisterQueue(Queue),
            FCk_Delegate_Request_OnCompleted(this, n"OnQueueRegistered"));
    }

    UFUNCTION()
    private void OnQueueRegistered(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (InRequestOwner != FCk_Handle(_Coordinator)) { return; }
        if (InResult != ECk_Request_OperationResult::Succeeded)
        {
            AddTrace(f"COORDINATOR: Queue registration failed ({InResult}).");
            RefreshDisplays();
            return;
        }
        _RegisteredQueueCount++;
        if (_RegisteredQueueCount == _Queues.Num())
        {
            AddTrace(f"COORDINATOR: {_RegisteredQueueCount} Queue services registered.");
            if (_TopologyValidated) { AdmitAfterEnvironmentTopology("Queue registrations completed after topology validation"); }
        }
        RefreshDisplays();
    }

    private void Request_RunReservationScatter()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_LiveStation)) { return; }
        _ContestedSlotRacePreset = false;
        _ReservationScatterPreset = true;
        _QueueCount = 1;
        _EnvironmentMode = 0;
        _Linear = true;
        _ClaimSlotsOnReach = false;
        _ReserveByTicketOrder = false;
        Request_StartLiveDemo();
    }

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

    private void Request_DestroySelectedQueueOwner()
    {
        if (HasAuthority() == false || _QueueOwners.IsValidIndex(_SelectedQueueIndex) == false
            || ck::Is_NOT_Valid(_QueueOwners[_SelectedQueueIndex]))
        { return; }
        CancelEnvironmentTopologyProbe();
        CancelServedExit();
        _PlannerRetryPending = false;
        _PlannerRetriesAwaiting = 0;
        if (ClearEnvironmentGeometry()) { utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity); }
        utils_entity_lifetime::Request_DestroyEntity(_QueueOwners[_SelectedQueueIndex]);
        AddTrace(f"ACTION: {GetSelectedQueueLabel()} owner destroyed. QueueCoordinator must prune that service without affecting peer Queues.");
        RefreshDisplays();
    }

    UFUNCTION()
    private void SubmitPendingSelections()
    {
        if (ck::Is_NOT_Valid(_Coordinator) || _RegisteredQueueCount != _Queues.Num()) { return; }
        for (auto Agent : _SelectionPendingAgents)
        {
            if (ck::Is_NOT_Valid(Agent)) { continue; }
            const auto Location = utils_transform::Get_EntityCurrentLocation(Agent.As_Transform());
            _Coordinator.Request_SelectQueue(
                FCk_Request_QueueCoordinator_SelectQueue(FCk_Handle(Agent), Location),
                FCk_Delegate_QueueCoordinator_OnSelected(this, n"OnQueueSelected"),
                FCk_Delegate_Request_OnCompleted(this, n"OnQueueSelectionCompleted"));
        }
        _SelectionPendingAgents.Empty();
    }

    UFUNCTION()
    private void OnQueueSelectionCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (InRequestOwner != FCk_Handle(_Coordinator) || InResult == ECk_Request_OperationResult::Succeeded) { return; }
        AddTrace(f"COORDINATOR completion: selection request failed ({InResult}).");
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnQueueSelected(FCk_QueueCoordinator_SelectResult InResult)
    {
        const auto AgentIndex = GetAgentIndex(InResult.Get_Member());
        if (AgentIndex == -1 || ck::Is_NOT_Valid(_Agents[AgentIndex])) { return; }
        const auto Agent = _Agents[AgentIndex];
        const auto Outcome = InResult.Get_Outcome();
        if (Outcome == ECk_QueueCoordinator_SelectOutcome::AlreadyQueued)
        {
            _AgentRoutes[AgentIndex].SelectedQueue = InResult.Get_SelectedQueue();
            AddTrace(f"ROUTE: agent {AgentIndex} remains on {GetQueueLabel(InResult.Get_SelectedQueue())}.");
            RefreshDisplays();
            return;
        }
        if (Outcome != ECk_QueueCoordinator_SelectOutcome::Selected
            || ck::Is_NOT_Valid(InResult.Get_SelectedQueue()))
        {
            AddTrace(f"ROUTE: agent {AgentIndex} has no eligible Queue ({Outcome}); overflowed.");
            MarkRejectedAgent(FCk_Handle(Agent));
            RefreshDisplays();
            return;
        }
        _AgentRoutes[AgentIndex].SelectedQueue = InResult.Get_SelectedQueue();
        _AgentRoutes[AgentIndex].FallbackQueues = InResult.Get_EligibleFallbackQueues();
        _AgentRoutes[AgentIndex].NextFallbackIndex = 0;
        RequestAgentJoin(AgentIndex, InResult.Get_SelectedQueue());
    }

    private void RequestAgentJoin(int32 InAgentIndex, FCk_Handle_Queue InQueue)
    {
        if (_Agents.IsValidIndex(InAgentIndex) == false || ck::Is_NOT_Valid(InQueue))
        { return; }
        auto Agent = _Agents[InAgentIndex];
        if (ck::Is_NOT_Valid(Agent)) { return; }
        _AgentRoutes[InAgentIndex].SelectedQueue = InQueue;
        auto Queue = InQueue;
        Agent.Request_JoinQueue(Queue, FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
    }

    UFUNCTION()
    private void OnJoinCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        const auto QueueIndex = GetQueueIndexFromHandle(InRequestOwner);
        if (QueueIndex == -1) { return; }
        const auto Queue = _Queues[QueueIndex];
        if (InResult == ECk_Request_OperationResult::Succeeded) { _JoinSucceeded += 1; }
        else { _JoinRejected += 1; }
        if (_PlannerRetriesAwaiting > 0)
        {
            _PlannerRetriesAwaiting--;
            _PlannerRetryPending = _PlannerRetriesAwaiting > 0;
        }
        AddTrace(f"GOAP completion: Join {GetQueueLabel(Queue)} result={InResult}");
        RefreshDisplays();
    }

    private void RetryAgentFallbackOrOverflow(int32 InAgentIndex, FCk_Handle_Queue InRejectedQueue)
    {
        if (_AgentRoutes.IsValidIndex(InAgentIndex) == false)
        { MarkRejectedAgent(FCk_Handle(_Agents[InAgentIndex])); return; }
        auto Route = _AgentRoutes[InAgentIndex];
        while (Route.NextFallbackIndex < Route.FallbackQueues.Num())
        {
            const auto Candidate = Route.FallbackQueues[Route.NextFallbackIndex];
            Route.NextFallbackIndex++;
            if (Candidate == InRejectedQueue || ck::Is_NOT_Valid(Candidate)
                || Candidate.Get_CanAcceptRequests() == false)
            { continue; }
            Route.SelectedQueue = Candidate;
            _AgentRoutes[InAgentIndex] = Route;
            RequestAgentJoin(InAgentIndex, Candidate);
            return;
        }
        Route.SelectedQueue = FCk_Handle_Queue();
        _AgentRoutes[InAgentIndex] = Route;
        MarkRejectedAgent(FCk_Handle(_Agents[InAgentIndex]));
    }

    UFUNCTION()
    private void OnAdvanceCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        const auto JobIndex = FindAdvanceJobIndex(InRequestOwner);
        if (JobIndex == -1) { return; }
        _AdvanceJobs[JobIndex].RequestCompleted = true;
        _AdvanceJobs[JobIndex].RequestSucceeded = InResult == ECk_Request_OperationResult::Succeeded;
        const auto Queue = _AdvanceJobs[JobIndex].Queue;
        if (InResult != ECk_Request_OperationResult::Succeeded)
        {
            AddTrace(f"GOAP completion: Advance {GetQueueLabel(Queue)} failed ({InResult}); no served exit move issued.");
            TryQueueServedExit(JobIndex);
            RefreshDisplays();
            return;
        }

        AddTrace(f"GOAP completion: Advance {GetQueueLabel(Queue)} succeeded.");
        TryQueueServedExit(JobIndex);
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnMemberEvent(FCk_Handle_Queue InQueue, FCk_Queue_MemberEvent InEvent)
    {
        if (GetQueueIndex(InQueue) == -1) { return; }
        _EventCount += 1;
        const auto Member = InEvent.Get_Member();
        if (Member.Get_State() == ECk_Queue_MemberState::Rejected)
        {
            const auto AgentIndex = GetAgentIndex(Member.Get_Mover());
            if (AgentIndex != -1)
            { RetryAgentFallbackOrOverflow(AgentIndex, InQueue); }
            else { MarkRejectedAgent(Member.Get_Member()); }
        }
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::Advanced
            && Member.Get_State() == ECk_Queue_MemberState::Serving)
        {
            const auto JobIndex = FindAdvanceJobIndex(FCk_Handle(InQueue));
            if (JobIndex == -1)
            {
                AddTrace(f"GOAP event: {GetQueueLabel(InQueue)} produced an unowned serving event; no gym exit move issued.");
                RefreshDisplays();
                return;
            }
            for (auto Agent : _Agents)
            {
                if (FCk_Handle(Agent) == Member.Get_Mover())
                {
                    _AdvanceJobs[JobIndex].ServingAgent = Agent;
                    _AdvanceJobs[JobIndex].NominalSlotLocation = Member.Get_TargetWorldTransform().GetLocation();
                    _AdvanceJobs[JobIndex].ServingCaptured = true;
                    break;
                }
            }
            AddTrace(f"GOAP event: {GetQueueLabel(InQueue)} serving member captured for exit={Member.Get_Member().ToString()}");
            TryQueueServedExit(JobIndex);
        }
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::Joined)
        { RestoreAdmittedAgentColor(Member.Get_Member()); }
        if (_ContestedSlotRacePreset
            && _ContestedFirstWinnerTicket == 0
            && InEvent.Get_Reason() == ECk_Queue_EventReason::SlotReached
            && Member.Get_State() == ECk_Queue_MemberState::AtFront)
        {
            _ContestedFirstWinnerTicket = Member.Get_Ticket();
            AddTrace(f"RACE RESULT: ticket {_ContestedFirstWinnerTicket} claimed rank 0 first; ticket 1 was admitted first.");
        }
        RefreshAgentDiagnostics(Member);
        AddTrace(f"GOAP event: {GetQueueLabel(InQueue)} {InEvent.Get_Reason()} member={Member.Get_Member().ToString()} rank={Member.Get_Rank()} rev={InEvent.Get_QueueRevision()}");
        RefreshDisplays();
    }

    private void RefreshAgentDiagnostics(const FCk_Queue_MemberSnapshot& InMember)
    {
        const auto HasCurrentTarget = InMember.Get_AssignmentRevision() > 0
            && InMember.Get_TargetWorldTransform().ContainsNaN() == false
            && (InMember.Get_State() == ECk_Queue_MemberState::Assigned
                || InMember.Get_State() == ECk_Queue_MemberState::MovingToSlot
                || InMember.Get_State() == ECk_Queue_MemberState::AtSlot
                || InMember.Get_State() == ECk_Queue_MemberState::AtFront);
        if (HasCurrentTarget == false) { return; }

        for (int32 Index = 0; Index < _Agents.Num(); ++Index)
        {
            if (FCk_Handle(_Agents[Index]) != InMember.Get_Mover())
            { continue; }

            const auto Goal = InMember.Get_TargetWorldTransform().GetLocation();
            TrackAgentIndexForGoal(Index, Goal);
            return;
        }
    }

    private void TrackAgentForGoal(FCk_Handle_CrowdAgent InAgent, FVector InGoal)
    {
        for (int32 Index = 0; Index < _Agents.Num(); ++Index)
        {
            if (_Agents[Index] != InAgent) { continue; }
            TrackAgentIndexForGoal(Index, InGoal);
            return;
        }
    }

    private void TrackAgentIndexForGoal(int32 InIndex, FVector InGoal)
    {
        if (_Agents.IsValidIndex(InIndex) == false
            || _AgentDiagnosticGoals.IsValidIndex(InIndex) == false
            || _AgentHasDiagnosticGoal.IsValidIndex(InIndex) == false
            || ck::Is_NOT_Valid(_Agents[InIndex]))
        { return; }
        if (_AgentHasDiagnosticGoal[InIndex] && _AgentDiagnosticGoals[InIndex].Equals(InGoal, 1.0f))
        { return; }

        auto Agent = _Agents[InIndex];
        const auto Start = utils_transform::Get_EntityCurrentLocation(Agent.As_Transform());
        utils_crowd_agent_diag::Track(Agent, Start, InGoal);
        _AgentDiagnosticGoals[InIndex] = InGoal;
        _AgentHasDiagnosticGoal[InIndex] = true;
    }

    UFUNCTION()
    private void OnPressure(FCk_Handle_Queue InQueue, FCk_Queue_Pressure InPressure)
    {
        if (GetQueueIndex(InQueue) == -1) { return; }
        AddTrace(f"GOAP pressure {GetQueueLabel(InQueue)}: count={InPressure.Get_MemberCount()} soft={InPressure.Get_IsSoftLimited()} hard={InPressure.Get_IsHardLimited()}");
        RequestPlannerRetryWhenCapacityReturns(InQueue, InPressure);
    }

    UFUNCTION()
    private void OnFormation(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        if (GetQueueIndex(InQueue) != -1) { AddTrace(f"GOAP formation {GetQueueLabel(InQueue)}: {InState.Get_State()} reason={InState.Get_Reason()} retry={InState.Get_RetryEpisode()}"); RefreshDisplays(); }
    }

    UFUNCTION()
    private void OnInvalidated(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        if (GetQueueIndex(InQueue) == -1) { return; }
        AddTrace(f"GOAP invalidated {GetQueueLabel(InQueue)}: reason={InState.Get_Reason()} rev={InState.Get_QueueRevision()}");
        RefreshDisplays();
    }

    private void CyclePopulation()
    {
        ClearContestedSlotRacePreset();
        if (_Population == 6) { _Population = 12; }
        else if (_Population == 12) { _Population = 24; }
        else if (_Population == 24) { _Population = 30; }
        else if (_Population == 30) { _Population = 32; }
        else { _Population = 6; }
        Request_StartLiveDemo();
    }

    private void CycleLayout()
    {
        ClearContestedSlotRacePreset();
        _Linear = !_Linear;
        AddTrace(f"OPTION: layout changed to {GetLayoutLabel()}; rebuilding the Queue bank.");
        Request_StartLiveDemo();
    }

    private void CycleSlotClaiming()
    {
        ClearContestedSlotRacePreset();
        _ClaimSlotsOnReach = !_ClaimSlotsOnReach;
        AddTrace(f"OPTION: slot claiming changed to {GetSlotClaimingLabel()}; rebuilding selected scenario.");
        Request_StartLiveDemo();
    }

    private void CycleHardLimit()
    {
        ClearContestedSlotRacePreset();
        if (_HardLimit == 2) { _HardLimit = 4; }
        else if (_HardLimit == 4) { _HardLimit = 6; }
        else if (_HardLimit == 6) { _HardLimit = 30; }
        else { _HardLimit = 2; }
        AddTrace(f"OPTION: queue limit changed to {_HardLimit}; rebuilding through public Queue params.");
        Request_StartLiveDemo();
    }

    private void TickScatterNearAdmission(float InDeltaSeconds)
    {
        if (_ScatterNearAdmissionPending == false || _Agents.Num() != 2 || ck::Is_NOT_Valid(_Queue))
        { return; }

        FCk_Queue_MemberSnapshot FirstFar;
        FCk_Queue_MemberSnapshot SecondFar;
        const bool HasFirstFar = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agents[0]), FirstFar);
        const bool HasSecondFar = _Queue.TryGet_MemberSnapshot(FCk_Handle(_Agents[1]), SecondFar);
        const bool FarPairOwnsDistinctReservations = HasFirstFar && HasSecondFar
            && FirstFar.Get_AssignmentRevision() > 0
            && SecondFar.Get_AssignmentRevision() > 0
            && FirstFar.Get_Rank() >= 0 && FirstFar.Get_Rank() <= 1
            && SecondFar.Get_Rank() >= 0 && SecondFar.Get_Rank() <= 1
            && FirstFar.Get_Rank() != SecondFar.Get_Rank();
        if (FarPairOwnsDistinctReservations == false)
        {
            _ScatterFarReservationDisplaySeconds = 0.0f;
            return;
        }

        _ScatterFarReservationDisplaySeconds += Math::Max(0.0f, InDeltaSeconds);
        if (_ScatterFarReservationDisplaySeconds < ScatterFarReservationHoldSeconds) { return; }

        _ScatterNearAdmissionPending = false;
        _ScatterFarReservationDisplaySeconds = 0.0f;
        SpawnAndJoinAgents(_Population - _Agents.Num());
        AddTrace("SCATTER: the far pair held distinct ranks 0 and 1 visibly; nearby admissions now join and must fill only the unreserved suffix.");
        RefreshDisplays();
    }

    private void CycleReserveAssignmentPolicy()
    {
        ClearContestedSlotRacePreset();
        _ReserveByTicketOrder = !_ReserveByTicketOrder;
        AddTrace(f"OPTION: reserve assignment changed to {GetReserveAssignmentPolicyLabel()}; rebuilding selected scenario.");
        Request_StartLiveDemo();
    }

    private void CycleReserveAssignmentPhaseSpread()
    {
        ClearContestedSlotRacePreset();
        _ReserveAssignmentPhaseSpread = !_ReserveAssignmentPhaseSpread;
        AddTrace(f"OPTION: reserve refresh phase spread changed to {GetReserveAssignmentPhaseSpreadLabel()}; rebuilding selected scenario.");
        Request_StartLiveDemo();
    }

    private void CycleReserveAssignmentRefreshSeconds()
    {
        ClearContestedSlotRacePreset();
        if (_ReserveAssignmentRefreshSeconds <= 0.0f) { _ReserveAssignmentRefreshSeconds = 0.1f; }
        else if (_ReserveAssignmentRefreshSeconds <= 0.1f) { _ReserveAssignmentRefreshSeconds = 0.25f; }
        else if (_ReserveAssignmentRefreshSeconds <= 0.25f) { _ReserveAssignmentRefreshSeconds = 0.5f; }
        else { _ReserveAssignmentRefreshSeconds = 0.0f; }
        AddTrace(f"OPTION: reserve refresh interval changed to {GetReserveAssignmentRefreshSecondsLabel()}; rebuilding selected scenario.");
        Request_StartLiveDemo();
    }

    private bool Get_HasReadyFront(FCk_Handle_Queue InQueue) const
    {
        if (ck::Is_NOT_Valid(InQueue)) { return false; }
        for (const auto Member : InQueue.Get_Members())
        {
            if (Member.Get_Rank() == 0
                && Member.Get_State() == ECk_Queue_MemberState::AtFront)
            { return true; }
        }
        return false;
    }

    private int32 Get_ReadyQueueCount() const
    {
        auto ReadyCount = 0;
        for (const auto Queue : _Queues)
        {
            if (Get_HasReadyFront(Queue)) { ReadyCount++; }
        }
        return ReadyCount;
    }

    private bool Get_CanAdvanceQueueBank() const
    {
        return Get_IsAdvanceBatchActive() == false && Get_ReadyQueueCount() > 0;
    }

    private bool Get_IsAdvanceBatchActive() const
    {
        return _AdvanceJobs.IsEmpty() == false
            || _PendingServedExits.IsEmpty() == false
            || Get_IsServedExitClearanceActive();
    }

    private FString GetAdvanceStatusLabel() const
    {
        if (_AdvanceJobs.IsEmpty() == false) { return f"Advancing {_AdvanceJobs.Num()} Queue(s)"; }
        const auto ExitCount = _PendingServedExits.Num() + (Get_IsServedExitClearanceActive() ? 1 : 0);
        if (ExitCount > 0) { return f"Clearing {ExitCount} served agent(s)"; }
        const auto ReadyCount = Get_ReadyQueueCount();
        return ReadyCount > 0 ? f"Ready: {ReadyCount} Queue(s)" : "Waiting for fronts";
    }

    private bool Get_IsServedExitClearanceActive() const
    {
        return _ServedExitDestroyRequested || ck::IsValid(_ServedExitAgent);
    }

    private int32 FindAdvanceJobIndex(FCk_Handle InQueue) const
    {
        for (int32 Index = 0; Index < _AdvanceJobs.Num(); ++Index)
        {
            if (FCk_Handle(_AdvanceJobs[Index].Queue) == InQueue) { return Index; }
        }
        return -1;
    }

    private void TryQueueServedExit(int32 InJobIndex)
    {
        if (_AdvanceJobs.IsValidIndex(InJobIndex) == false) { return; }
        const auto Job = _AdvanceJobs[InJobIndex];
        if (Job.RequestCompleted == false) { return; }
        if (Job.RequestSucceeded == false)
        {
            _AdvanceJobs.RemoveAt(InJobIndex);
            return;
        }
        if (Job.ServingCaptured == false)
        {
            AddTrace(f"SERVICE EXIT: {GetQueueLabel(Job.Queue)} advance succeeded; awaiting its serving mover event.");
            return;
        }

        auto ExitJob = FCk_QueueGym_ServedExitJob();
        ExitJob.Queue = Job.Queue;
        ExitJob.Agent = Job.ServingAgent;
        ExitJob.NominalSlotLocation = Job.NominalSlotLocation;
        _PendingServedExits.Add(ExitJob);
        _AdvanceJobs.RemoveAt(InJobIndex);
        TryStartNextServedExit();
    }

    private void TryStartNextServedExit()
    {
        if (Get_IsServedExitClearanceActive()) { return; }
        while (_PendingServedExits.IsEmpty() == false)
        {
            const auto ExitJob = _PendingServedExits[0];
            _PendingServedExits.RemoveAt(0);
            if (ck::Is_NOT_Valid(ExitJob.Agent))
            {
                AddTrace(f"SERVICE EXIT: skipped invalid served agent from {GetQueueLabel(ExitJob.Queue)}.");
                continue;
            }

            _AdvancingQueue = ExitJob.Queue;
            _ServedExitAgent = ExitJob.Agent;
            _ServedExitNominalSlotLocation = ExitJob.NominalSlotLocation;
            _ServedExitDepartureLocation = utils_transform::Get_EntityCurrentLocation(_ServedExitAgent.As_Transform());
            _ServedExitAttempts = 0;
            _ServedExitDestroyRequested = false;
            auto NominalOffset = _ServedExitDepartureLocation - _ServedExitNominalSlotLocation;
            NominalOffset.Z = 0.0f;
            AddTrace(f"SERVICE EXIT: {GetQueueLabel(_AdvancingQueue)} physical departure={_ServedExitDepartureLocation} nominal slot={_ServedExitNominalSlotLocation} offset={NominalOffset.Size()}uu.");
            RequestNextServedExitMove("initial served exit");
            return;
        }
    }

    private void TickServedExitClearance(float InDeltaSeconds)
    {
        if (Get_IsServedExitClearanceActive() == false) { return; }
        if (ck::Is_NOT_Valid(_ServedExitAgent))
        {
            CompleteServedExitClearance("served agent is no longer valid");
            return;
        }
        if (_ServedExitDestroyRequested) { return; }

        _ServedExitAttemptElapsedSeconds += Math::Max(0.0f, InDeltaSeconds);

        if (_ServedExitAwaitingDispatch)
        {
            if (utils_crowd_agent::Get_ActiveMoveCorrelationId(_ServedExitAgent) != _ServedExitCorrelation)
            {
                if (_ServedExitAttemptElapsedSeconds >= ServedExitDispatchTimeoutSeconds)
                { RequestNextServedExitMove("exit move was not adopted before the dispatch deadline"); }
                return;
            }
            _ServedExitAwaitingDispatch = false;
        }

        auto AgentLocation = utils_transform::Get_EntityCurrentLocation(_ServedExitAgent.As_Transform());
        auto Offset = AgentLocation - _ServedExitDepartureLocation;
        Offset.Z = 0.0f;
        if (Offset.Size() >= ServedExitClearanceRadiusUu)
        {
            CompleteServedExitClearance("served agent moved clear of its departure footprint");
            return;
        }

        if (utils_crowd_agent::Get_IsGoalFailedHold(_ServedExitAgent))
        { RequestNextServedExitMove("exit goal entered GoalFailedHold"); return; }

        const auto MovementState = utils_crowd_agent::Get_MovementState(_ServedExitAgent);
        const auto ActiveGoal = utils_crowd_agent::Get_ActiveGoal(_ServedExitAgent);
        if (MovementState == ECk_CrowdAgent_MovementState::Idle
            && ActiveGoal.Equals(_ServedExitGoal, 1.0f) == false)
        { RequestNextServedExitMove("served exit episode was replaced before clearance"); return; }

        // A reached goal inside the front reservation radius is an authored exit mistake, not successful clearance.
        if (utils_crowd_agent::Get_HasReachedActiveGoal(_ServedExitAgent))
        { RequestNextServedExitMove("exit goal reached before footprint clearance"); return; }

        if (_ServedExitAttemptElapsedSeconds >= ServedExitMovementTimeoutSeconds)
        { RequestNextServedExitMove("served agent did not clear the front reservation radius before the movement deadline"); }
    }

    private void RequestNextServedExitMove(const FString& InReason)
    {
        if (ck::Is_NOT_Valid(_ServedExitAgent) || _ServedExitDestroyRequested) { return; }
        if (_ServedExitAttempts >= MaxServedExitAttempts)
        {
            _ServedExitDestroyRequested = true;
            AddTrace(f"SERVICE EXIT: exhausted {MaxServedExitAttempts} attempts ({InReason}); destroying only this served gym agent as bounded recovery.");
            utils_entity_lifetime::Request_DestroyEntity(_ServedExitAgent);
            return;
        }

        _ServedExitAttempts++;
        _ServedExitLaneSerial++;
        const auto LaneIndex = (_ServedExitLaneSerial % 5) - 2;
        const auto AdvancingQueueIndex = GetQueueIndex(_AdvancingQueue);
        const auto OwnerTransform = AdvancingQueueIndex == -1
            ? Get_QueueOwnerTransform()
            : Get_QueueOwnerTransform(AdvancingQueueIndex);
        auto ExitLocation = OwnerTransform.TransformPosition(
            FVector(900.0f + float(_ServedExitAttempts - 1) * 180.0f, float(LaneIndex) * 220.0f, SpawnZ));
        FVector ProjectedExit;
        if (utils_nav::Try_ProjectOntoNavmesh(_PcEntity, ExitLocation, 250.0f, ProjectedExit, 400.0f))
        { ExitLocation = ProjectedExit; }
        _ServedExitCorrelation = _ServedExitCorrelation == 2147483647 ? 1 : _ServedExitCorrelation + 1;
        if (_ServedExitCorrelation == 0) { _ServedExitCorrelation = 1; }
        auto Move = FCk_Request_CrowdAgent_MoveTo(ExitLocation);
        Move.Set_CorrelationId(_ServedExitCorrelation)
            .Set_ForceRepath(true);
        _ServedExitGoal = ExitLocation;
        TrackAgentForGoal(_ServedExitAgent, ExitLocation);
        _ServedExitAwaitingDispatch = true;
        _ServedExitAttemptElapsedSeconds = 0.0f;
        utils_crowd_agent::Request_MoveTo(_ServedExitAgent, Move);
        AddTrace(f"SERVICE EXIT: attempt {_ServedExitAttempts}/{MaxServedExitAttempts} ({InReason}) goal={ExitLocation} lane={LaneIndex}.");
    }

    private void CompleteServedExitClearance(const FString& InReason)
    {
        AddTrace(f"SERVICE EXIT: {GetQueueLabel(_AdvancingQueue)} clearance complete ({InReason}).");
        _ServedExitAgent = FCk_Handle_CrowdAgent();
        _ServedExitDepartureLocation = FVector::ZeroVector;
        _ServedExitNominalSlotLocation = FVector::ZeroVector;
        _ServedExitGoal = FVector::ZeroVector;
        _ServedExitAttempts = 0;
        _ServedExitDestroyRequested = false;
        _ServedExitAwaitingDispatch = false;
        _ServedExitAttemptElapsedSeconds = 0.0f;
        _AdvancingQueue = FCk_Handle_Queue();
        TryStartNextServedExit();
    }

    private void CancelServedExit()
    {
        if (ck::IsValid(_ServedExitAgent)
            && utils_crowd_agent::Get_ActiveMoveCorrelationId(_ServedExitAgent) == _ServedExitCorrelation)
        { utils_crowd_agent::Request_Stop(_ServedExitAgent); }
        _ServedExitAgent = FCk_Handle_CrowdAgent();
        _ServedExitDepartureLocation = FVector::ZeroVector;
        _ServedExitNominalSlotLocation = FVector::ZeroVector;
        _ServedExitGoal = FVector::ZeroVector;
        _ServedExitAttempts = 0;
        _ServedExitDestroyRequested = false;
        _ServedExitAwaitingDispatch = false;
        _ServedExitAttemptElapsedSeconds = 0.0f;
        _AdvancingQueue = FCk_Handle_Queue();
        _AdvanceJobs.Empty();
        _PendingServedExits.Empty();
    }

    private void RequestPlannerRetryWhenCapacityReturns(FCk_Handle_Queue InQueue, FCk_Queue_Pressure InPressure)
    {
        if (_PlannerRetryPending || _RejectedAgents.IsEmpty()
            || InPressure.Get_MemberCount() >= InPressure.Get_HardLimit()
            || ck::Is_NOT_Valid(_Coordinator))
        { return; }

        const auto Capacity = InPressure.Get_HardLimit() - InPressure.Get_MemberCount();
        if (Capacity <= 0) { return; }

        auto Retried = 0;
        for (auto Index = _RejectedAgents.Num() - 1; Index >= 0 && Retried < Capacity; --Index)
        {
            auto Agent = _RejectedAgents[Index];
            _RejectedAgents.RemoveAt(Index);
            if (ck::Is_NOT_Valid(Agent)) { continue; }
            _SelectionPendingAgents.Add(Agent);
            ++Retried;
        }
        if (Retried <= 0) { return; }
        _PlannerRetriesAwaiting = Retried;
        _PlannerRetryPending = true;
        SubmitPendingSelections();
        AddTrace(f"GOAP planner retry {GetQueueLabel(InQueue)}: capacity={Capacity}; resubmitted {Retried} rejected agent(s) through Coordinator.");
    }

    private void CycleQueueBank()
    {
        ClearContestedSlotRacePreset();
        if (_EnvironmentMode != 0) { _EnvironmentMode = 0; }
        if (_QueueCount == 1) { _QueueCount = 2; }
        else if (_QueueCount == 2) { _QueueCount = 10; }
        else { _QueueCount = 1; }
        _SelectedQueueIndex = 0;
        AddTrace(f"OPTION: Queue bank changed to {_QueueCount} independent Queues; rebuilding.");
        Request_StartLiveDemo();
    }

    private void CycleCoordinatorPolicy()
    {
        _CoordinatorNearestFirst = !_CoordinatorNearestFirst;
        AddTrace(f"OPTION: coordinator policy changed to {GetCoordinatorPolicyLabel()}; rebuilding.");
        Request_StartLiveDemo();
    }

    private void CycleSelectedQueue()
    {
        if (_Queues.IsEmpty()) { return; }
        _SelectedQueueIndex = (_SelectedQueueIndex + 1) % _Queues.Num();
        AddTrace(f"OPTION: selected {GetSelectedQueueLabel()} for per-Queue diagnostics and destruction actions.");
        RefreshDisplays();
    }

    private void CycleEnvironment()
    {
        ClearContestedSlotRacePreset();
        _EnvironmentMode = (_EnvironmentMode + 1) % 5;
        if (_EnvironmentMode != 0) { _QueueCount = 1; }
        Request_StartLiveDemo();
    }

    private bool ClearContestedSlotRacePreset()
    {
        const bool WasActive = _ContestedSlotRacePreset || _ReservationScatterPreset;
        _ContestedSlotRacePreset = false;
        _ReservationScatterPreset = false;
        _ContestedFirstWinnerTicket = 0;
        _ScatterNearAdmissionPending = false;
        _ScatterFarReservationDisplaySeconds = 0.0f;
        return WasActive;
    }

    private float GetConfiguredSlotSpacingUu() const
    {
        return _ContestedSlotRacePreset ? 240.0f : 120.0f;
    }

    private void CancelEnvironmentTopologyProbe(bool InClearTopologyWitnesses = true)
    {
        _AwaitingEnvironmentTopology = false;
        _AdmissionIssued = false;
        _TopologyPathRequested = false;
        _TopologyProbeStart = FVector::ZeroVector;
        _TopologyProbeGoal = FVector::ZeroVector;
        if (InClearTopologyWitnesses) { _TopologyClearWitnesses.Empty(); }
        if (ck::IsValid(_NavProbeEntity)) { utils_entity_lifetime::Request_DestroyEntity(_NavProbeEntity); }
        _NavProbeEntity = FCk_Handle();
    }

    private void BeginEnvironmentTopologyProbe()
    {
        // Preserve witnesses captured during ResetScenario so Open waits for removed tiles to become walkable.
        CancelEnvironmentTopologyProbe(false);
        if (ck::Is_NOT_Valid(_QueueOwner) || ck::Is_NOT_Valid(_Queue)) { return; }

        const auto Targets = GetConfiguredTargetTransforms();
        if (Targets.IsEmpty())
        {
            AddTrace("TOPOLOGY: queue has no active target; no agents admitted.");
            RefreshDisplays();
            return;
        }

        const auto OwnerTransform = Get_QueueOwnerTransform();
        _TopologyProbeStart = OwnerTransform.TransformPosition(FVector(-500.0f, 0.0f, SpawnZ));
        _TopologyProbeGoal = Targets[0].GetLocation() + FVector(0.0f, 0.0f, SpawnZ);
        _NavProbeEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        utils_transform::Add(_NavProbeEntity,
            FTransform(FRotator::ZeroRotator, _TopologyProbeStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _AwaitingEnvironmentTopology = true;

        if (_EnvironmentMode != 0) { _TopologyClearWitnesses.Empty(); }

        if (_EnvironmentMode == 1)
        {
            AddTrace("TOPOLOGY: waiting until every target projection is absent after NavArea_Null rebuild.");
            RefreshDisplays();
            return;
        }
        if (HasPhysicalEnvironment())
        {
            _TopologyClearWitnesses.Empty();
            AddTrace("TOPOLOGY: waiting until every physical blocker is absent from the rebuilt navmesh.");
            RefreshDisplays();
            return;
        }
        if (_TopologyClearWitnesses.Num() > 0)
        {
            AddTrace("TOPOLOGY: waiting until removed-environment witness cells are walkable again.");
            RefreshDisplays();
            return;
        }
        RequestReachableTopologyPath();
    }

    private void PollEnvironmentTopology()
    {
        if (_AwaitingEnvironmentTopology == false || _AdmissionIssued || ck::Is_NOT_Valid(_QueueOwner)) { return; }

        FVector Projected;
        if (_EnvironmentMode == 1)
        {
            const auto Targets = GetConfiguredTargetTransforms();
            if (Targets.IsEmpty()) { return; }
            bool EveryTargetIsBlocked = true;
            for (const auto& Target : Targets)
            {
                if (utils_nav::Try_ProjectOntoNavmesh(_PcEntity, Target.GetLocation(), 20.0f, Projected, 300.0f))
                { EveryTargetIsBlocked = false; break; }
            }
            const bool ApproachProjects = utils_nav::Try_ProjectOntoNavmesh(_PcEntity, _TopologyProbeStart, 30.0f, Projected, 400.0f);
            if (EveryTargetIsBlocked && ApproachProjects)
            { AdmitAfterEnvironmentTopology("target-unreachable probe confirmed blocked targets while the approach remains navigable"); }
            return;
        }

        if (HasPhysicalEnvironment())
        {
            bool EveryBlockerIsBaked = _LayoutBlockers.Num() > 0;
            for (auto Blocker : _LayoutBlockers)
            {
                if (System::IsValid(Blocker) == false || utils_nav::Try_ProjectOntoNavmesh(_PcEntity, Blocker.GetActorLocation(), 20.0f, Projected, 300.0f))
                { EveryBlockerIsBaked = false; break; }
            }
            if (EveryBlockerIsBaked && _TopologyPathRequested == false) { RequestReachableTopologyPath(); }
            return;
        }

        if (_TopologyClearWitnesses.Num() > 0)
        {
            bool EveryWitnessIsWalkable = true;
            for (const auto& Witness : _TopologyClearWitnesses)
            {
                if (utils_nav::Try_ProjectOntoNavmesh(_PcEntity, Witness, 20.0f, Projected, 300.0f) == false)
                { EveryWitnessIsWalkable = false; break; }
            }
            if (EveryWitnessIsWalkable == false) { return; }
            _TopologyClearWitnesses.Empty();
        }
        if (_TopologyPathRequested == false) { RequestReachableTopologyPath(); }
    }

    private void RequestReachableTopologyPath()
    {
        if (_AwaitingEnvironmentTopology == false || _AdmissionIssued || _TopologyPathRequested || ck::Is_NOT_Valid(_NavProbeEntity)) { return; }
        _TopologyPathRequested = true;
        utils_nav::BindTo_OnPathReady(_NavProbeEntity, FCk_Delegate_Nav_OnPathReady(this, n"OnEnvironmentTopologyPathReady"), ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame, ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::BindTo_OnPathFailed(_NavProbeEntity, FCk_Delegate_Nav_OnPathFailed(this, n"OnEnvironmentTopologyPathFailed"), ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame, ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::Request_FindPath(_NavProbeEntity, FCk_Request_Nav_FindPath(_TopologyProbeGoal));
        AddTrace("TOPOLOGY: rebuilt reachable mode passed projection checks; requesting its path probe.");
        RefreshDisplays();
    }

    private void AdmitAfterEnvironmentTopology(const FString& InEvidence)
    {
        _TopologyValidated = true;
        if (_AdmissionIssued || !_AwaitingEnvironmentTopology || ck::Is_NOT_Valid(_Queue)
            || _RegisteredQueueCount != _Queues.Num())
        {
            if (_AdmissionIssued == false && _RegisteredQueueCount != _Queues.Num())
            { AddTrace("TOPOLOGY READY: waiting for all Queue registrations before admission."); }
            return;
        }
        _AdmissionIssued = true;
        _AwaitingEnvironmentTopology = false;
        if (_ReservationScatterPreset && _Population >= 2)
        {
            _ScatterNearAdmissionPending = true;
            _ScatterFarReservationDisplaySeconds = 0.0f;
            SpawnAndJoinAgents(Math::Min(2, _Population));
            AddTrace(f"SCATTER: admitting only the far pair first; nearby agents wait until both reservations remain visible for {ScatterFarReservationHoldSeconds}s.");
        }
        else { SpawnAndJoinAgents(_Population); }
        AddTrace(f"TOPOLOGY READY: {InEvidence}. Requested {_Population} agents for admission.");
        RefreshDisplays();
    }

    private bool HasPhysicalEnvironment() const
    {
        return _EnvironmentMode >= 2 && _EnvironmentMode <= 4;
    }

    private void ApplyEnvironment(bool InGeometryWasRemoved)
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_QueueOwner)) { return; }

        bool CreatedGeometry = false;
        if (_EnvironmentMode == 1)
        {
            const auto Targets = GetConfiguredTargetTransforms();
            for (const auto& Target : Targets)
            {
                auto Blocker = utils_nav_area_markup::Request_Create(_PcEntity, Target,
                    FVector(TargetBlockerHalfExtent, TargetBlockerHalfExtent, 300.0f), UNavArea_Null);
                if (ck::IsValid(Blocker)) { _TargetBlockers.Add(Blocker); CreatedGeometry = true; }
            }
        }
        else if (_EnvironmentMode == 2)
        {
            // Covers all 30 120cm ranks behind the target: the line cannot escape around a short wall end.
            if (SpawnLayoutBlocker(FVector(-1800.0f, 150.0f, 100.0f), FVector(3600.0f, 100.0f, 200.0f))) { CreatedGeometry = true; }
            if (SpawnLayoutBlocker(FVector(-1800.0f, -150.0f, 100.0f), FVector(3600.0f, 100.0f, 200.0f))) { CreatedGeometry = true; }
        }
        else if (_EnvironmentMode == 3)
        {
            CreatedGeometry = SpawnLayoutBlocker(FVector(-360.0f, 0.0f, 100.0f), FVector(100.0f, 100.0f, 200.0f));
        }
        else if (_EnvironmentMode == 4)
        {
            if (SpawnLayoutBlocker(FVector(-360.0f, 0.0f, 100.0f), FVector(90.0f, 90.0f, 200.0f))) { CreatedGeometry = true; }
            if (SpawnLayoutBlocker(FVector(-240.0f, -240.0f, 100.0f), FVector(90.0f, 90.0f, 200.0f))) { CreatedGeometry = true; }
            if (SpawnLayoutBlocker(FVector(120.0f, -120.0f, 100.0f), FVector(90.0f, 90.0f, 200.0f))) { CreatedGeometry = true; }
        }

        if (InGeometryWasRemoved || CreatedGeometry)
        {
            utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);
            AddTrace(f"OPTION: environment={GetEnvironmentLabel()}; navigation rebuilding before queue formation settles.");
        }
    }

    private bool SpawnLayoutBlocker(FVector InLocalCentre, FVector InSize)
    {
        const auto WorldTransform = FTransform(FRotator::ZeroRotator, InLocalCentre, FVector::OneVector) * Get_QueueOwnerTransform();
        auto Blocker = SpawnActor(ACk_CrowdPathingGym_NavBox, WorldTransform.GetLocation(), WorldTransform.Rotator(), NAME_None, true);
        if (Blocker == nullptr)
        {
            ck::Warning("Queue gym failed to spawn a physical environment blocker");
            return false;
        }
        Blocker.SetActorScale3D(FVector(InSize.X / 100.0f, InSize.Y / 100.0f, InSize.Z / 100.0f));
        FinishSpawningActor(Blocker);
        _LayoutBlockers.Add(Blocker);
        return true;
    }

    private bool ClearEnvironmentGeometry()
    {
        bool Removed = false;
        if (_EnvironmentMode == 1 && ck::IsValid(_QueueOwner))
        {
            for (const auto& Target : GetConfiguredTargetTransforms())
            { _TopologyClearWitnesses.Add(Target.GetLocation()); }
        }
        for (auto Blocker : _TargetBlockers)
        {
            if (ck::Is_NOT_Valid(Blocker)) { continue; }
            utils_nav_area_markup::Request_Destroy(Blocker);
            Removed = true;
        }
        _TargetBlockers.Empty();
        for (auto Blocker : _LayoutBlockers)
        {
            if (System::IsValid(Blocker) == false) { continue; }
            _TopologyClearWitnesses.Add(Blocker.GetActorLocation());
            Blocker.DestroyActor();
            Removed = true;
        }
        _LayoutBlockers.Empty();
        return Removed;
    }

    private TArray<FTransform> GetConfiguredTargetTransforms() const
    {
        auto Targets = TArray<FTransform>();
        if (ck::Is_NOT_Valid(_QueueOwner)) { return Targets; }
        Targets.Add(utils_transform::Get_EntityCurrentTransform(utils_transform::DoCastChecked(_QueueOwner)));
        return Targets;
    }

    private void DestroyFirstQueuedAgent()
    {
        const auto Queue = GetSelectedQueue();
        if (ck::Is_NOT_Valid(Queue)) { return; }
        for (auto Agent : _Agents)
        {
            if (ck::IsValid(Agent) && Queue.Get_IsMember(FCk_Handle(Agent)))
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
        for (int32 Index = 0; Index < _Agents.Num(); ++Index)
        {
            const auto Agent = _Agents[Index];
            if (FCk_Handle(Agent) != InRequestOwner) { continue; }
            utils_crowd_agent::Set_DebugColor(Agent, FLinearColor(1.0f, 0.05f, 0.05f, 1.0f));
            if (_RejectedAgents.Contains(Agent) == false) { _RejectedAgents.Add(Agent); }
            const auto OwnerTransform = Get_QueueOwnerTransform();
            const auto OverflowSide = Index % 2 == 0 ? -1.0f : 1.0f;
            const auto OverflowLane = float(Math::IntegerDivisionTrunc(Index, 2));
            auto ExitLocation = OwnerTransform.TransformPosition(
                FVector(-600.0f, OverflowSide * (1400.0f + OverflowLane * 160.0f), SpawnZ));
            FVector ProjectedExit;
            if (utils_nav::Try_ProjectOntoNavmesh(_PcEntity, ExitLocation, 250.0f, ProjectedExit, 400.0f))
            { ExitLocation = ProjectedExit; }
            _RejectedExitCorrelation = _RejectedExitCorrelation == 2147483647 ? 1 : _RejectedExitCorrelation + 1;
            if (_RejectedExitCorrelation == 0) { _RejectedExitCorrelation = 1; }
            auto Move = FCk_Request_CrowdAgent_MoveTo(ExitLocation);
            Move.Set_CorrelationId(_RejectedExitCorrelation)
                .Set_ForceRepath(true);
            TrackAgentIndexForGoal(Index, ExitLocation);
            utils_crowd_agent::Request_MoveTo(Agent, Move);
            AddTrace(f"OVERFLOW: agent {Index} has no eligible Queue remaining and is exiting the Queue bank.");
            return;
        }
    }

    private void RestoreAdmittedAgentColor(FCk_Handle InMember)
    {
        for (int32 Index = 0; Index < _Agents.Num(); ++Index)
        {
            const auto Agent = _Agents[Index];
            if (FCk_Handle(Agent) != InMember) { continue; }
            if (_RejectedAgents.Contains(Agent) == false) { return; }
            _RejectedAgents.Remove(Agent);
            if (ck::IsValid(Agent))
            {
                utils_crowd_agent::Set_DebugColor(Agent,
                    FLinearColor::MakeFromHSV8(uint8((Index * 47) % 255), 210, 240));
            }
            AddTrace(f"GOAP planner retry: member {InMember.ToString()} joined; restored normal debug color.");
            return;
        }
    }

    private void DrawScenarioDiagnostics()
    {
        const auto QueueCategory = utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym");
        for (const auto& Snapshot : utils_queue::Get_DebugSnapshots(_PcEntity))
        {
            if (Snapshot.Get_Category() != QueueCategory) { continue; }
            const auto Target = Snapshot.Get_OwnerWorldTransform();
            const auto Location = Target.GetLocation();
            const auto Cyan = FLinearColor(0.1f, 0.9f, 1.0f, 1.0f);
            const auto QueueIndex = FindQueueIndexByOwnerTransform(Target);
            utils_debug_draw::DrawDebugCross(Location, 85.0f, Cyan, 0.0f, 3.0f);
            utils_debug_draw::DrawDebugArrow(Location, Location + Target.Rotator().GetForwardVector() * 140.0f, 26.0f, Cyan, 0.0f, 3.0f);
            utils_debug_draw::DrawDebugString(Location + FVector(0.0f, 0.0f, 70.0f), f"Q{QueueIndex} TARGET", Cyan, 0.0f);

            if (_ContestedSlotRacePreset == false && _ReservationScatterPreset == false)
            {
                for (const auto& Member : Snapshot.Get_Members())
                {
                    if (Member.Get_HasMoverWorldTransform() == false || Member.Get_MoverWorldTransform().ContainsNaN()) { continue; }
                    const auto SelectedLabel = QueueIndex == -1 ? "Q?" : f"Q{QueueIndex}";
                    const auto MemberLocation = Member.Get_MoverWorldTransform().GetLocation();
                    utils_debug_draw::DrawDebugString(MemberLocation + FVector(0.0f, 0.0f, AgentHeight + 36.0f),
                        f"{SelectedLabel} ticket={Member.Get_Ticket()} rank={Member.Get_Rank()}", Cyan, 0.0f);
                }
            }

            if (_ContestedSlotRacePreset)
            {
                for (const auto& Member : Snapshot.Get_Members())
                {
                    const auto State = Member.Get_State();
                    const bool IsContender = State == ECk_Queue_MemberState::MovingToSlot;
                    const bool IsClaimed = State == ECk_Queue_MemberState::AtFront
                        || State == ECk_Queue_MemberState::AtSlot;
                    if ((IsContender == false && IsClaimed == false)
                        || Member.Get_AssignmentRevision() <= 0
                        || Member.Get_TargetWorldTransform().ContainsNaN())
                    { continue; }

                    if (Member.Get_HasMoverWorldTransform() == false
                        || Member.Get_MoverWorldTransform().ContainsNaN())
                    { continue; }

                    const auto MemberLocation = Member.Get_MoverWorldTransform().GetLocation();
                    const auto TargetLocation = Member.Get_TargetWorldTransform().GetLocation();
                    const auto DistanceToTarget = float((MemberLocation - TargetLocation).Size());
                    const auto SelectedLabel = QueueIndex == -1 ? "Q?" : f"Q{QueueIndex}";
                    const bool IsFirstWinner = IsClaimed
                        && Member.Get_Ticket() == _ContestedFirstWinnerTicket;
                    const auto Color = IsFirstWinner
                        ? FLinearColor(0.15f, 1.0f, 0.25f, 1.0f)
                        : IsClaimed
                            ? FLinearColor(0.2f, 0.65f, 1.0f, 1.0f)
                            : FLinearColor(1.0f, 0.75f, 0.05f, 1.0f);
                    const bool IsSettled = IsClaimed && DistanceToTarget <= _Queue.Get_SlotSettleRadiusUu();
                    const auto Label = IsFirstWinner
                        ? IsSettled ? "FIRST WINNER / SETTLED" : "FIRST WINNER / SETTLING"
                        : IsClaimed ? IsSettled ? "CLAIMED / SETTLED" : "CLAIMED / SETTLING"
                        : "CONTENDER";
                    if (IsClaimed == false || IsSettled == false)
                    { utils_debug_draw::DrawDebugLine(MemberLocation, TargetLocation, Color, 0.0f, 4.0f); }
                    utils_debug_draw::DrawDebugString(MemberLocation + FVector(0.0f, 0.0f, AgentHeight + 48.0f),
                        f"{SelectedLabel} {Label} ticket={Member.Get_Ticket()} rank={Member.Get_Rank()} assignment={Member.Get_AssignmentRevision()}", Color, 0.0f);
                }
            }

            if (_ReservationScatterPreset)
            {
                for (const auto& Member : Snapshot.Get_Members())
                {
                    if (Member.Get_HasMoverWorldTransform() == false || Member.Get_MoverWorldTransform().ContainsNaN())
                    { continue; }
                    const auto MemberLocation = Member.Get_MoverWorldTransform().GetLocation();
                    const auto SelectedLabel = QueueIndex == -1 ? "Q?" : f"Q{QueueIndex}";
                    const auto IsInitialFarTicket = Member.Get_Ticket() == 1 || Member.Get_Ticket() == 2;
                    const auto Color = IsInitialFarTicket
                        ? FLinearColor(0.75f, 0.25f, 1.0f, 1.0f)
                        : FLinearColor(0.15f, 0.95f, 1.0f, 1.0f);
                    const auto Label = IsInitialFarTicket ? "FAR INITIAL RESERVATION" : "NEAR LATER ADMISSION";
                    utils_debug_draw::DrawDebugLine(MemberLocation, Member.Get_TargetWorldTransform().GetLocation(), Color, 0.0f, 3.0f);
                    utils_debug_draw::DrawDebugString(MemberLocation + FVector(0.0f, 0.0f, AgentHeight + 48.0f),
                        f"{SelectedLabel} {Label} ticket={Member.Get_Ticket()} rank={Member.Get_Rank()} assignment={Member.Get_AssignmentRevision()}", Color, 0.0f);
                }
            }
        }

        if (_EnvironmentMode == 1 && _TargetBlockers.Num() > 0 && ck::IsValid(_QueueOwner))
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
            const auto ExitGoal = utils_crowd_agent::Get_ActiveGoal(Agent);
            utils_debug_draw::DrawDebugLine(Location, ExitGoal, FLinearColor(1.0f, 0.25f, 0.05f, 1.0f), 0.0f, 3.0f);
            utils_debug_draw::DrawDebugString(Location + FVector(0.0f, 0.0f, AgentHeight + 20.0f), "REJECTED: HARD LIMIT / EXITING", FLinearColor(1.0f, 0.05f, 0.05f, 1.0f), 0.0f);
        }
    }

    private FString GetPopulationLabel() const { return _Population == 32 ? f"32 (up to {_HardLimit * _QueueCount} across bank + overflow)" : f"{_Population}"; }
    private FString GetPrimaryOwnerMovedLabel() const { return _PrimaryOwnerMoved ? "moved" : "home"; }
    private FString GetPresetLabel() const
    {
        if (_ContestedSlotRacePreset) { return "Contested slot race (R)"; }
        if (_ReservationScatterPreset) { return "Reservation scatter (K)"; }
        return "Custom";
    }
    private FString GetLayoutLabel() const { return _Linear ? "Linear" : "Orthogonal snake"; }
    private FString GetSlotClaimingLabel() const { return _ClaimSlotsOnReach ? "Claim on reach" : "Reserve all"; }
    private FString GetReserveAssignmentPolicyLabel() const { return _ReserveByTicketOrder ? "Ticket order" : "Distance then ticket"; }
    private FString GetReserveAssignmentPhaseSpreadLabel() const { return _ReserveAssignmentPhaseSpread ? "Enabled" : "Disabled"; }
    private FString GetReserveAssignmentRefreshSecondsLabel() const { return f"{_ReserveAssignmentRefreshSeconds}s"; }
    private int32 GetConfiguredSoftLimit() const { return Math::Min(4, _HardLimit); }
    private FString GetQueueBankLabel() const { return f"{_QueueCount} independent Queue(s)"; }
    private FString GetCoordinatorPolicyLabel() const { return _CoordinatorNearestFirst ? "Nearest then least members" : "Least members then distance"; }
    private FString GetSelectedQueueLabel() const { return _Queues.IsValidIndex(_SelectedQueueIndex) ? f"Q{_SelectedQueueIndex}" : "Q?"; }
    private FCk_Handle_Queue GetSelectedQueue() const { return _Queues.IsValidIndex(_SelectedQueueIndex) ? _Queues[_SelectedQueueIndex] : FCk_Handle_Queue(); }
    private int32 GetQueueIndex(FCk_Handle_Queue InQueue) const
    {
        for (int32 Index = 0; Index < _Queues.Num(); ++Index)
        { if (_Queues[Index] == InQueue) { return Index; } }
        return -1;
    }
    private int32 GetQueueIndexFromHandle(FCk_Handle InQueue) const
    {
        for (int32 Index = 0; Index < _Queues.Num(); ++Index)
        { if (FCk_Handle(_Queues[Index]) == InQueue) { return Index; } }
        return -1;
    }
    private FString GetQueueLabel(FCk_Handle_Queue InQueue) const
    {
        const auto Index = GetQueueIndex(InQueue);
        return Index == -1 ? "Q?" : f"Q{Index}";
    }
    private int32 FindQueueIndexByOwnerTransform(FTransform InOwnerTransform) const
    {
        for (int32 Index = 0; Index < _QueueOwners.Num(); ++Index)
        {
            if (ck::Is_NOT_Valid(_QueueOwners[Index])) { continue; }
            const auto OwnerTransform = utils_transform::Get_EntityCurrentTransform(utils_transform::DoCastChecked(_QueueOwners[Index]));
            if (OwnerTransform.GetLocation().Equals(InOwnerTransform.GetLocation(), 1.0f)) { return Index; }
        }
        return -1;
    }
    private int32 GetAgentIndex(FCk_Handle InAgent) const
    {
        for (int32 Index = 0; Index < _Agents.Num(); ++Index)
        { if (FCk_Handle(_Agents[Index]) == InAgent) { return Index; } }
        return -1;
    }
    private FString GetEnvironmentLabel() const
    {
        if (_EnvironmentMode == 1) { return "Target unreachable"; }
        if (_EnvironmentMode == 2) { return "Tight corridor (30-slot)"; }
        if (_EnvironmentMode == 3) { return "90-degree corner"; }
        if (_EnvironmentMode == 4) { return "Constrained snake"; }
        return "Open";
    }

    private FVector StationLocal_To_World(FVector InLocalOffset)
    {
        return Get_StationAnchorTransform("Gym.Queue.Live", ECk_GymStation_Anchor::FootprintCenter).TransformPosition(InLocalOffset);
    }

    private FTransform Get_QueueOwnerTransform(int32 InQueueIndex = 0)
    {
        const auto StationTransform = Get_StationAnchorTransform("Gym.Queue.Live", ECk_GymStation_Anchor::FootprintCenter);
        auto Offset = FVector(QueueFwdOffset, 0.0f, 0.0f);
        if (_QueueCount == 2)
        {
            Offset.Y = (float(InQueueIndex) - 0.5f) * 900.0f;
        }
        else if (_QueueCount > 2)
        {
            const auto Column = InQueueIndex % 5;
            const auto Row = Math::IntegerDivisionTrunc(InQueueIndex, 5);
            Offset.Y = (float(Column) - 2.0f) * 900.0f;
            Offset.X += (float(Row) - 0.5f) * 900.0f;
        }
        if (InQueueIndex == 0 && _PrimaryOwnerMoved)
        { return FTransform((StationTransform.Rotator() + FRotator(0.0f, 90.0f, 0.0f)), StationTransform.TransformPosition(Offset + FVector(280.0f, 0.0f, 0.0f)), FVector::OneVector); }
        return FTransform(StationTransform.Rotator(), StationTransform.TransformPosition(Offset), FVector::OneVector);
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
        auto Entity = utils_entity_lifetime::Request_CreateEntity(_CoordinatorOwner);
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
            float X;
            float Y;
            if (_ContestedSlotRacePreset)
            {
                // Join order is Index order. Reverse the physical distances so late tickets can win the shared
                // provisional front target by arrival, then expose each live retarget with the visual oracle.
                X = -1500.0f + float(Index) * 240.0f;
                Y = (float(Index) - 2.5f) * 90.0f;
            }
            else if (_ReservationScatterPreset)
            {
                // The first pair joins before nearby agents. They therefore reserve ranks zero and one; the later
                // nearby admissions prove that proximity cannot steal an incumbent's established lower rank.
                if (Index < 2)
                {
                    X = -2600.0f + float(Index) * 220.0f;
                    Y = (float(Index) - 0.5f) * 160.0f;
                }
                else
                {
                    X = -280.0f + float(Index - 2) * 80.0f;
                    Y = (float(Index - 3) - 1.0f) * 110.0f;
                }
            }
            else
            {
                const auto RowOffset = float(Math::IntegerDivisionTrunc(Index, 6)) * 140.0f;
                // Physical environments occupy the formation side (negative X). Spawn on the open side so agents
                // enter the constrained queue instead of projecting out of walls or starting outside the corridor.
                X = HasPhysicalEnvironment() ? 300.0f + RowOffset : -500.0f + RowOffset;
                Y = (float(Index % 6) - 2.5f) * 130.0f;
            }
            auto Agent = SpawnAgent(QueueOwnerTransform.TransformPosition(FVector(X, Y, SpawnZ)), Index);
            _Agents.Add(Agent);
            _AgentDiagnosticGoals.Add(FVector::ZeroVector);
            _AgentHasDiagnosticGoal.Add(false);
            _AgentRoutes.Add(FCk_QueueGym_RouteState());
            _SelectionPendingAgents.Add(Agent);
        }
        SubmitPendingSelections();
    }

    private bool ResetScenario()
    {
        const bool RemovedEnvironmentGeometry = ClearEnvironmentGeometry();
        CancelEnvironmentTopologyProbe(false);
        for (auto Agent : _Agents) { if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); } }
        _Agents.Empty();
        _RejectedAgents.Empty();
        _AgentDiagnosticGoals.Empty();
        _AgentHasDiagnosticGoal.Empty();
        _SelectionPendingAgents.Empty();
        _AgentRoutes.Empty();
        _RegisteredQueueCount = 0;
        if (ck::IsValid(_CoordinatorOwner)) { utils_entity_lifetime::Request_DestroyEntity(_CoordinatorOwner); }
        _CoordinatorOwner = FCk_Handle();
        _Coordinator = FCk_Handle_QueueCoordinator();
        _QueueOwners.Empty();
        _Queues.Empty();
        _QueueOwner = FCk_Handle();
        _Queue = FCk_Handle_Queue();
        return RemovedEnvironmentGeometry;
    }

    private void EmitSnapshot()
    {
        if (ck::Is_NOT_Valid(_Coordinator)) { AddTrace("DIGEST: coordinator is invalid"); return; }
        AddTrace(f"DIGEST: services={_Coordinator.Get_Services().Num()}/{_Queues.Num()} coordinatorRevision={_Coordinator.Get_Revision()} rejected={_RejectedAgents.Num()}");
        for (int32 QueueIndex = 0; QueueIndex < _Queues.Num(); ++QueueIndex)
        {
            const auto Queue = _Queues[QueueIndex];
            if (ck::Is_NOT_Valid(Queue)) { continue; }
            const auto Pressure = Queue.Get_Pressure();
            AddTrace(f"  Q{QueueIndex}: count={Pressure.Get_MemberCount()} limit={Pressure.Get_HardLimit()} revision={Queue.Get_Revision()}");
        }
    }

    private void AddTrace(const FString& InLine)
    {
        _Trace.Add(InLine);
        if (_Trace.Num() > 7) { _Trace.RemoveAt(0); }
        ck::Trace(f"[QueueGym] {InLine}");
    }

    private void RefreshDisplays()
    {
        if (ck::Is_NOT_Valid(_Coordinator)) { return; }
        auto DisplayText = "GOAP-REACTIVE QUEUE\n";
        DisplayText = f"{DisplayText}preset={GetPresetLabel()} population={GetPopulationLabel()} bank={GetQueueBankLabel()} coordinator={GetCoordinatorPolicyLabel()} services={_Coordinator.Get_Services().Num()}/{_Queues.Num()} coordinatorRevision={_Coordinator.Get_Revision()} rejected={_RejectedAgents.Num()} selected={GetSelectedQueueLabel()}\n";
        if (ck::IsValid(_Queue))
        { DisplayText = f"{DisplayText}layout={GetLayoutLabel()} claims={GetSlotClaimingLabel()} reserve={GetReserveAssignmentPolicyLabel()} refresh={GetReserveAssignmentRefreshSecondsLabel()} phaseSpread={GetReserveAssignmentPhaseSpreadLabel()} claim={_Queue.Get_SlotClaimRadiusUu()}uu settle={_Queue.Get_SlotSettleRadiusUu()}uu reacquire={_Queue.Get_SlotReacquireRadiusUu()}uu environment={GetEnvironmentLabel()} visualization=Queue+AllCrowd\n"; }
        for (int32 QueueIndex = 0; QueueIndex < _Queues.Num(); ++QueueIndex)
        {
            const auto Queue = _Queues[QueueIndex];
            if (ck::Is_NOT_Valid(Queue)) { continue; }
            const auto Pressure = Queue.Get_Pressure();
            DisplayText = f"{DisplayText}Q{QueueIndex}: members={Pressure.Get_MemberCount()} limit={Pressure.Get_HardLimit()} soft={Pressure.Get_IsSoftLimited()} hard={Pressure.Get_IsHardLimited()} revision={Queue.Get_Revision()}\n";
        }
        if (_ContestedSlotRacePreset)
        {
            DisplayText = f"{DisplayText}ORACLE: yellow CONTENDER lines begin at shared rank 0; claimed members show SETTLING until they are within settle radius, then lose the tether and show SETTLED. FIRST WINNER records its ticket; losers retarget with newer rank/revision.\n";
            if (_ContestedFirstWinnerTicket > 0)
            { DisplayText = f"{DisplayText}firstWinner=ticket {_ContestedFirstWinnerTicket}; ticket 1 was admitted first.\n"; }
        }
        if (_ReservationScatterPreset)
        {
            DisplayText = f"{DisplayText}ORACLE: far tickets 1/2 reserve first, then near agents join behind them. Advance once the front arrives: ticket 2 must compact to rank 0 before any physically nearer later ticket.\n";
        }
        DisplayText = f"{DisplayText}joins={_JoinSucceeded}/{_JoinRejected} events={_EventCount}\n";
        for (auto Line : _Trace) { DisplayText = f"{DisplayText}{Line}\n"; }
        CkGym_Common::Update_StationDisplay(Get_StationHandle("Gym.Queue.Live"), "QUEUE: LIVE CROWD AGENTS", DisplayText,
            "Options: 0 Reset | 1 Population | 2 Layout | 3 Queue bank | 4 Environment | 5 Advance all ready queues | 6 Destroy agent | 7 Destroy selected Queue owner | 8 Slot claiming | L Queue limit reset | P Reserve policy | I Coordinator policy | B Selected queue | R Contested race | K Reservation scatter | T Phase spread | Y Refresh interval | M Move primary queue | G Snapshot | N Agent add step | J Add agents");
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
