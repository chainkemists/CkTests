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
    private TArray<AActor> _LayoutBlockers;
    private ACk_Gym_Floor _Floor = nullptr;
    private TArray<FString> _Trace;
    private int32 _JoinSucceeded = 0;
    private int32 _JoinRejected = 0;
    private int32 _EventCount = 0;
    private int32 _Population = 6;
    private int32 _OriginMode = 0;
    // 0 Open, 1 Target unreachable, 2 Tight corridor, 3 90-degree corner, 4 Constrained snake.
    private int32 _EnvironmentMode = 0;
    private bool _Linear = false;
    private bool _ClaimSlotsOnReach = false;
    // This is a complete authored scenario, not a configuration the normal controls happen to resemble.
    // Reset intentionally keeps it true so the visual race is replayable.
    private bool _ContestedSlotRacePreset = false;
    private int64 _ContestedFirstWinnerTicket = 0;
    private bool _QueueVisualization = true;
    private bool _PreviousQueueVisualization = false;
    private bool _CapturedQueueVisualization = false;
    private bool _AutoStarted = false;
    private bool _AwaitingEnvironmentTopology = false;
    private bool _AdmissionIssued = false;
    private bool _TopologyPathRequested = false;
    private bool _AdvancePending = false;
    private bool _PlannerRetryPending = false;
    private int32 _PlannerRetriesAwaiting = 0;
    private FCk_Handle_CrowdAgent _AdvancingAgent;
    private FCk_Handle_CrowdAgent _ServedExitAgent;
    private FVector _ServedExitFrontLocation;
    private FVector _ServedExitGoal;
    private int32 _ServedExitCorrelation = 0;
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
    private const int32 MaxServedExitAttempts = 3;
    private const int32 HardLimit = 30;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false) { return TArray<FCkGym_Station_SpawnParams_Payload>(); }
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        AddStation(Stations, n"Gym.Queue.Live", "QUEUE: LIVE CROWD AGENTS",
            "Use the numbered options panel for direct queue scenarios. Press R for the contested-slot race: later tickets start closer, so arrival claims each shared provisional slot. With visualization on, lines and labels are the visual oracle.");
        return Stations;
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(MakeNumberedControl(0, "Reset demo"));
        Rows.Add(MakeNumberedControl(1, "Population", GetPopulationLabel()));
        Rows.Add(MakeNumberedControl(2, "Layout", GetLayoutLabel()));
        const bool EnvironmentIsOpen = _EnvironmentMode == 0;
        Rows.Add(MakeNumberedControl(3, "Origins", GetOriginModeLabel(), EnvironmentIsOpen));
        Rows.Add(MakeNumberedControl(4, "Environment", GetEnvironmentLabel()));
        Rows.Add(MakeNumberedControl(5, "Queue visualization", _QueueVisualization ? "On" : "Off"));
        Rows.Add(MakeNumberedControl(6, "Advance origin", GetAdvanceStatusLabel(), Get_CanAdvanceOriginZero()));
        Rows.Add(MakeNumberedControl(7, "Destroy first queued agent"));
        Rows.Add(MakeNumberedControl(8, "Destroy queue owner"));
        Rows.Add(MakeNumberedControl(9, "Slot claiming", GetSlotClaimingLabel()));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Run contested slot race"));
        return Rows;
    }

    FString Get_ControlPanelTitle() override { return "QUEUE GYM OPTIONS"; }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (HasAuthority() == false) { return; }
        if (InRowIndex == 0) { Ck_GymQueue_Start(); return; }
        if (InRowIndex == 1) { CyclePopulation(); return; }
        if (InRowIndex == 2) { CycleLayout(); return; }
        if (InRowIndex == 3) { CycleOrigins(); return; }
        if (InRowIndex == 4) { CycleEnvironment(); return; }
        if (InRowIndex == 5) { CycleVisualization(); return; }
        if (InRowIndex == 6) { Ck_GymQueue_Advance(0); return; }
        if (InRowIndex == 7) { DestroyFirstQueuedAgent(); return; }
        if (InRowIndex == 8) { Ck_GymQueue_DestroyOwner(); return; }
        if (InRowIndex == 9) { CycleSlotClaiming(); return; }
        if (InRowIndex == 10) { Ck_GymQueue_ContestedRace(); }
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

    // Compatibility entry point. The menu is primary; this rebuilds exactly the selected configuration.
    UFUNCTION(Exec, DisplayName="Queue - Start / Reset Live Demo")
    void Ck_GymQueue_Start()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_LiveStation)) { return; }
        _AutoStarted = true;
        ApplyVisualizationSetting();
        CancelServedExit();
        const bool RemovedEnvironmentGeometry = ResetScenario();
        _Trace.Empty();
        _JoinSucceeded = 0;
        _JoinRejected = 0;
        _EventCount = 0;
        _AdvancePending = false;
        _PlannerRetryPending = false;
        _PlannerRetriesAwaiting = 0;
        _AdvancingAgent = FCk_Handle_CrowdAgent();
        _ContestedFirstWinnerTicket = 0;

        const auto QueueOwnerTransform = Get_QueueOwnerTransform();
        _QueueOwner = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        utils_transform::Add(_QueueOwner, QueueOwnerTransform, ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Fragment_Queue_ParamsData(GetConfiguredOrigins());
        Params.Set_Category(utils_gameplay_tag::ResolveGameplayTag(n"Queue.Category.Gym"));
        Params.Set_SlotSpacingUu(GetConfiguredSlotSpacingUu());
        Params.Set_SlotClaimRadiusUu(30.0f);
        Params.Set_SlotSettleRadiusUu(10.0f);
        Params.Set_SlotReacquireRadiusUu(20.0f);
        Params.Set_HardLimit(HardLimit);
        Params.Set_SoftLimit(4);
        Params.Set_AgentRadiusUu(AgentRadius);
        Params.Set_AgentHalfHeightUu(AgentHeight * 0.5f);
        Params.Set_LayoutAlgorithm(_Linear ? ECk_Queue_LayoutAlgorithm::Linear : ECk_Queue_LayoutAlgorithm::OrthogonalSnake);
        Params.Set_SlotClaimPolicy(_ClaimSlotsOnReach
            ? ECk_Queue_SlotClaimPolicy::ClaimFirstAvailableOnReach
            : ECk_Queue_SlotClaimPolicy::ReserveOnFormation);
        _Queue = utils_queue::Add(_QueueOwner, Params);
        _Queue.BindTo_OnQueueMemberStateChanged(FCk_Delegate_Queue_OnMemberStateChanged(this, n"OnMemberEvent"));
        _Queue.BindTo_OnQueuePressureChanged(FCk_Delegate_Queue_OnPressureChanged(this, n"OnPressure"));
        _Queue.BindTo_OnQueueFormationStateChanged(FCk_Delegate_Queue_OnFormationStateChanged(this, n"OnFormation"));
        _Queue.BindTo_OnQueueInvalidated(FCk_Delegate_Queue_OnInvalidated(this, n"OnInvalidated"));

        ApplyEnvironment(RemovedEnvironmentGeometry);
        BeginEnvironmentTopologyProbe();
        AddTrace(f"START: {GetPopulationLabel()} selected; layout={GetLayoutLabel()} origins={GetOriginModeLabel()} environment={GetEnvironmentLabel()}; waiting for rebuilt topology before admission.");
        RefreshDisplays();
    }

    // Compatibility entry point. It changes source state then creates an exact new scenario, not an incremental mystery population.
    UFUNCTION(Exec, DisplayName="Queue - Add Agents")
    void Ck_GymQueue_AddAgents(int32 InCount = 5)
    {
        if (InCount <= 0) { return; }
        ClearContestedSlotRacePreset();
        _Population = Math::Min(32, _Population + InCount);
        Ck_GymQueue_Start();
    }

    UFUNCTION(Exec, DisplayName="Queue - Move Origin (Reflow)")
    void Ck_GymQueue_MoveOrigin()
    {
        const bool WasContestedSlotRace = ClearContestedSlotRacePreset();
        if (SelectOpenEnvironmentForOrigins())
        {
            _OriginMode = 1;
            Ck_GymQueue_Start();
            AddTrace("COMPAT: Environment returned to Open before MoveOrigin; fresh topology-gated queue started.");
            RefreshDisplays();
            return;
        }
        _OriginMode = 1;
        if (WasContestedSlotRace)
        {
            Ck_GymQueue_Start();
            return;
        }
        ApplyOriginsLive();
    }

    UFUNCTION(Exec, DisplayName="Queue - Use Two Weighted Origins")
    void Ck_GymQueue_TwoOrigins()
    {
        const bool WasContestedSlotRace = ClearContestedSlotRacePreset();
        if (SelectOpenEnvironmentForOrigins())
        {
            _OriginMode = 2;
            Ck_GymQueue_Start();
            AddTrace("COMPAT: Environment returned to Open before TwoOrigins; fresh topology-gated queue started.");
            RefreshDisplays();
            return;
        }
        _OriginMode = 2;
        if (WasContestedSlotRace)
        {
            Ck_GymQueue_Start();
            return;
        }
        ApplyOriginsLive();
    }

    UFUNCTION(Exec, DisplayName="Queue - Advance Origin")
    void Ck_GymQueue_Advance(int32 InOrigin = 0)
    {
        if (HasAuthority() == false || InOrigin != 0 || Get_CanAdvanceOriginZero() == false)
        {
            AddTrace("ACTION: advance rejected by gym gate; origin 0 needs a rank-0 AtFront member and no pending advance.");
            RefreshDisplays();
            return;
        }
        _AdvancePending = true;
        _AdvancingAgent = FCk_Handle_CrowdAgent();
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(InOrigin),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvanceCompleted"));
        AddTrace("ACTION: advance requested for origin 0; waiting for queue completion.");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Toggle Orthogonal Snake / Linear")
    void Ck_GymQueue_ToggleLayout() { CycleLayout(); }

    UFUNCTION(Exec, DisplayName="Queue - Make Target Unreachable")
    void Ck_GymQueue_Impossible() { ClearContestedSlotRacePreset(); _EnvironmentMode = 1; Ck_GymQueue_Start(); }

    UFUNCTION(Exec, DisplayName="Queue - Restore Target Navigation")
    void Ck_GymQueue_RestoreNav() { ClearContestedSlotRacePreset(); _EnvironmentMode = 0; Ck_GymQueue_Start(); }

    UFUNCTION(Exec, DisplayName="Queue - Overfill Hard Limit")
    void Ck_GymQueue_Overfill() { ClearContestedSlotRacePreset(); _Population = 32; Ck_GymQueue_Start(); }

    // The later tickets deliberately start closer. ClaimFirstAvailableOnReach therefore proves that
    // physical arrival, not ticket order, owns each provisional slot.
    UFUNCTION(Exec, DisplayName="Queue - Run Contested Slot Race")
    void Ck_GymQueue_ContestedRace()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_LiveStation)) { return; }
        _ContestedSlotRacePreset = true;
        _Population = 6;
        _OriginMode = 0;
        _EnvironmentMode = 0;
        _Linear = true;
        _ClaimSlotsOnReach = true;
        _QueueVisualization = true;
        Ck_GymQueue_Start();
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

    UFUNCTION(Exec, DisplayName="Queue - Destroy Queue Owner")
    void Ck_GymQueue_DestroyOwner()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_QueueOwner)) { return; }
        CancelEnvironmentTopologyProbe();
        CancelServedExit();
        _AdvancePending = false;
        _PlannerRetryPending = false;
        _PlannerRetriesAwaiting = 0;
        _AdvancingAgent = FCk_Handle_CrowdAgent();
        if (ClearEnvironmentGeometry()) { utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity); }
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
        if (_PlannerRetriesAwaiting > 0)
        {
            _PlannerRetriesAwaiting--;
            _PlannerRetryPending = _PlannerRetriesAwaiting > 0;
        }
        AddTrace(f"GOAP completion: Join result={InResult}");
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnAdvanceCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (InRequestOwner != FCk_Handle(_Queue) || _AdvancePending == false) { return; }
        _AdvancePending = false;
        if (InResult != ECk_Request_OperationResult::Succeeded)
        {
            AddTrace(f"GOAP completion: Advance origin 0 failed ({InResult}); no served exit move issued.");
            RefreshDisplays();
            return;
        }

        AddTrace("GOAP completion: Advance origin 0 succeeded.");
        BeginServedExit();
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
        if (InEvent.Get_Reason() == ECk_Queue_EventReason::Advanced
            && Member.Get_State() == ECk_Queue_MemberState::Serving)
        {
            for (auto Agent : _Agents)
            {
                if (FCk_Handle(Agent) == Member.Get_Mover())
                {
                    _AdvancingAgent = Agent;
                    _ServedExitFrontLocation = Member.Get_TargetWorldTransform().GetLocation();
                    break;
                }
            }
            AddTrace(f"GOAP event: serving member captured for exit={Member.Get_Member().ToString()}");
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
        AddTrace(f"GOAP event: {InEvent.Get_Reason()} member={Member.Get_Member().ToString()} rank={Member.Get_Rank()} rev={InEvent.Get_QueueRevision()}");
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnPressure(FCk_Handle_Queue InQueue, FCk_Queue_Pressure InPressure)
    {
        if (InQueue != _Queue) { return; }
        AddTrace(f"GOAP pressure: count={InPressure.Get_MemberCount()} soft={InPressure.Get_IsSoftLimited()} hard={InPressure.Get_IsHardLimited()}");
        RequestPlannerRetryWhenCapacityReturns(InPressure);
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
        ClearContestedSlotRacePreset();
        if (_Population == 6) { _Population = 12; }
        else if (_Population == 12) { _Population = 24; }
        else if (_Population == 24) { _Population = 30; }
        else if (_Population == 30) { _Population = 32; }
        else { _Population = 6; }
        Ck_GymQueue_Start();
    }

    private void CycleLayout()
    {
        const bool WasContestedSlotRace = ClearContestedSlotRacePreset();
        _Linear = !_Linear;
        if (WasContestedSlotRace)
        {
            Ck_GymQueue_Start();
            return;
        }
        if (ck::IsValid(_Queue))
        {
            const auto Layout = _Linear ? ECk_Queue_LayoutAlgorithm::Linear : ECk_Queue_LayoutAlgorithm::OrthogonalSnake;
            _Queue.Request_SetLayout(FCk_Request_Queue_SetLayout(Layout));
            AddTrace(f"OPTION: layout changed to {GetLayoutLabel()}; all slots receive a new revision.");
        }
        RefreshDisplays();
    }

    private void CycleSlotClaiming()
    {
        ClearContestedSlotRacePreset();
        _ClaimSlotsOnReach = !_ClaimSlotsOnReach;
        AddTrace(f"OPTION: slot claiming changed to {GetSlotClaimingLabel()}; rebuilding selected scenario.");
        Ck_GymQueue_Start();
    }

    private bool Get_CanAdvanceOriginZero() const
    {
        if (_AdvancePending || Get_IsServedExitClearanceActive() || ck::Is_NOT_Valid(_Queue)) { return false; }
        for (const auto Member : _Queue.Get_Members())
        {
            if (Member.Get_OriginIndex() == 0
                && Member.Get_Rank() == 0
                && Member.Get_State() == ECk_Queue_MemberState::AtFront)
            { return true; }
        }
        return false;
    }

    private FString GetAdvanceStatusLabel() const
    {
        if (_AdvancePending) { return "Request pending"; }
        if (Get_IsServedExitClearanceActive()) { return "Clearing served agent"; }
        return Get_CanAdvanceOriginZero() ? "Ready" : "Waiting for front";
    }

    private bool Get_IsServedExitClearanceActive() const
    {
        return _ServedExitDestroyRequested || ck::IsValid(_ServedExitAgent);
    }

    private void BeginServedExit()
    {
        if (ck::Is_NOT_Valid(_AdvancingAgent))
        {
            AddTrace("SERVICE EXIT: advance succeeded but the serving event carried no valid CrowdAgent.");
            return;
        }

        CancelServedExit();
        _ServedExitAgent = _AdvancingAgent;
        _AdvancingAgent = FCk_Handle_CrowdAgent();
        _ServedExitAttempts = 0;
        _ServedExitDestroyRequested = false;
        RequestNextServedExitMove("initial served exit");
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
        auto Offset = AgentLocation - _ServedExitFrontLocation;
        Offset.Z = 0.0f;
        if (Offset.Size() >= ServedExitClearanceRadiusUu)
        {
            CompleteServedExitClearance("served agent cleared the front reservation radius");
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
        const auto OwnerTransform = Get_QueueOwnerTransform();
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
        _ServedExitAwaitingDispatch = true;
        _ServedExitAttemptElapsedSeconds = 0.0f;
        utils_crowd_agent::Request_MoveTo(_ServedExitAgent, Move);
        AddTrace(f"SERVICE EXIT: attempt {_ServedExitAttempts}/{MaxServedExitAttempts} ({InReason}) goal={ExitLocation} lane={LaneIndex}.");
    }

    private void CompleteServedExitClearance(const FString& InReason)
    {
        AddTrace(f"SERVICE EXIT: clearance complete ({InReason}); next advance may proceed.");
        _ServedExitAgent = FCk_Handle_CrowdAgent();
        _ServedExitFrontLocation = FVector::ZeroVector;
        _ServedExitGoal = FVector::ZeroVector;
        _ServedExitAttempts = 0;
        _ServedExitDestroyRequested = false;
        _ServedExitAwaitingDispatch = false;
        _ServedExitAttemptElapsedSeconds = 0.0f;
    }

    private void CancelServedExit()
    {
        if (ck::IsValid(_ServedExitAgent)
            && utils_crowd_agent::Get_ActiveMoveCorrelationId(_ServedExitAgent) == _ServedExitCorrelation)
        { utils_crowd_agent::Request_Stop(_ServedExitAgent); }
        _ServedExitAgent = FCk_Handle_CrowdAgent();
        _ServedExitFrontLocation = FVector::ZeroVector;
        _ServedExitGoal = FVector::ZeroVector;
        _ServedExitAttempts = 0;
        _ServedExitDestroyRequested = false;
        _ServedExitAwaitingDispatch = false;
        _ServedExitAttemptElapsedSeconds = 0.0f;
    }

    private void RequestPlannerRetryWhenCapacityReturns(FCk_Queue_Pressure InPressure)
    {
        if (_PlannerRetryPending || _RejectedAgents.IsEmpty()
            || InPressure.Get_MemberCount() >= InPressure.Get_HardLimit()
            || ck::Is_NOT_Valid(_Queue))
        { return; }

        const auto Capacity = InPressure.Get_HardLimit() - InPressure.Get_MemberCount();
        if (Capacity <= 0) { return; }

        auto Retried = 0;
        for (auto Index = _RejectedAgents.Num() - 1; Index >= 0 && Retried < Capacity; --Index)
        {
            auto Agent = _RejectedAgents[Index];
            _RejectedAgents.RemoveAt(Index);
            if (ck::Is_NOT_Valid(Agent)) { continue; }
            Agent.Request_JoinQueue(_Queue, FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
            ++Retried;
        }
        if (Retried <= 0) { return; }
        _PlannerRetriesAwaiting = Retried;
        _PlannerRetryPending = true;
        AddTrace(f"GOAP planner retry: capacity={Capacity}; resubmitted {Retried} terminally rejected agent(s).");
    }

    private void CycleOrigins()
    {
        const bool WasContestedSlotRace = ClearContestedSlotRacePreset();
        const bool ClearedEnvironment = SelectOpenEnvironmentForOrigins();
        _OriginMode = (_OriginMode + 1) % 3;
        if (ClearedEnvironment || WasContestedSlotRace)
        {
            AddTrace("OPTION: origins changed from a preset or non-open environment; resetting and topology-gating the fresh queue.");
            Ck_GymQueue_Start();
            return;
        }
        ApplyOriginsLive();
    }

    private void CycleEnvironment()
    {
        ClearContestedSlotRacePreset();
        _EnvironmentMode = (_EnvironmentMode + 1) % 5;
        if (HasPhysicalEnvironment()) { _OriginMode = 0; }
        Ck_GymQueue_Start();
    }
    private void CycleVisualization() { _QueueVisualization = !_QueueVisualization; ApplyVisualizationSetting(); RefreshDisplays(); }

    private void ApplyOriginsLive()
    {
        if (ck::Is_NOT_Valid(_Queue)) { return; }
        const bool RemovedEnvironmentGeometry = ClearEnvironmentGeometry();
        _Queue.Request_SetOrigins(FCk_Request_Queue_SetOrigins(GetConfiguredOrigins()));
        ApplyEnvironment(RemovedEnvironmentGeometry);
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

    private bool ClearContestedSlotRacePreset()
    {
        const bool WasActive = _ContestedSlotRacePreset;
        _ContestedSlotRacePreset = false;
        _ContestedFirstWinnerTicket = 0;
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
        if (_AdmissionIssued || !_AwaitingEnvironmentTopology || ck::Is_NOT_Valid(_Queue)) { return; }
        _AdmissionIssued = true;
        _AwaitingEnvironmentTopology = false;
        SpawnAndJoinAgents(_Population);
        AddTrace(f"TOPOLOGY READY: {InEvidence}. Admitted exactly {_Population} requested agents.");
        RefreshDisplays();
    }

    private bool HasPhysicalEnvironment() const
    {
        return _EnvironmentMode >= 2 && _EnvironmentMode <= 4;
    }

    private bool SelectOpenEnvironmentForOrigins()
    {
        if (_EnvironmentMode == 0) { return false; }
        _EnvironmentMode = 0;
        return true;
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

                    const auto Location = Member.Get_MoverWorldTransform().GetLocation();
                    const auto TargetLocation = Member.Get_TargetWorldTransform().GetLocation();
                    const auto DistanceToTarget = float((Location - TargetLocation).Size());
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
                    { utils_debug_draw::DrawDebugLine(Location, TargetLocation, Color, 0.0f, 4.0f); }
                    utils_debug_draw::DrawDebugString(Location + FVector(0.0f, 0.0f, AgentHeight + 48.0f),
                        f"{Label} ticket={Member.Get_Ticket()} rank={Member.Get_Rank()} assignment={Member.Get_AssignmentRevision()}", Color, 0.0f);
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
            utils_debug_draw::DrawDebugString(Location + FVector(0.0f, 0.0f, AgentHeight + 20.0f), "REJECTED: HARD LIMIT", FLinearColor(1.0f, 0.05f, 0.05f, 1.0f), 0.0f);
        }
    }

    private FString GetPopulationLabel() const { return _Population == 32 ? "32 (30 admitted + 2 rejected)" : f"{_Population}"; }
    private FString GetPresetLabel() const { return _ContestedSlotRacePreset ? "Contested slot race (R)" : "Custom"; }
    private FString GetLayoutLabel() const { return _Linear ? "Linear" : "Orthogonal snake"; }
    private FString GetSlotClaimingLabel() const { return _ClaimSlotsOnReach ? "Claim on reach" : "Reserve all"; }
    private FString GetOriginModeLabel() const { if (_OriginMode == 1) { return "Moved / rotated"; } if (_OriginMode == 2) { return "Two weighted"; } return "Single"; }
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
            float X;
            float Y;
            if (_ContestedSlotRacePreset)
            {
                // Join order is Index order. Reverse the physical distances so late tickets can win the shared
                // provisional front target by arrival, then expose each live retarget with the visual oracle.
                X = -1500.0f + float(Index) * 240.0f;
                Y = (float(Index) - 2.5f) * 90.0f;
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
            Agent.Request_JoinQueue(_Queue, FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
        }
    }

    private bool ResetScenario()
    {
        const bool RemovedEnvironmentGeometry = ClearEnvironmentGeometry();
        CancelEnvironmentTopologyProbe(false);
        for (auto Agent : _Agents) { if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); } }
        _Agents.Empty();
        _RejectedAgents.Empty();
        if (ck::IsValid(_QueueOwner)) { utils_entity_lifetime::Request_DestroyEntity(_QueueOwner); }
        _QueueOwner = FCk_Handle();
        _Queue = FCk_Handle_Queue();
        return RemovedEnvironmentGeometry;
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
        DisplayText = f"{DisplayText}preset={GetPresetLabel()} population={GetPopulationLabel()} members={Pressure.Get_MemberCount()} rejected={_RejectedAgents.Num()} soft={Pressure.Get_IsSoftLimited()} hard={Pressure.Get_IsHardLimited()}\n";
        DisplayText = f"{DisplayText}layout={GetLayoutLabel()} claims={GetSlotClaimingLabel()} claim={_Queue.Get_SlotClaimRadiusUu()}uu settle={_Queue.Get_SlotSettleRadiusUu()}uu reacquire={_Queue.Get_SlotReacquireRadiusUu()}uu origins={GetOriginModeLabel()} environment={GetEnvironmentLabel()} visualization={_QueueVisualization}\n";
        if (_ContestedSlotRacePreset)
        {
            DisplayText = f"{DisplayText}ORACLE: yellow CONTENDER lines begin at shared rank 0; claimed members show SETTLING until they are within settle radius, then lose the tether and show SETTLED. FIRST WINNER records its ticket; losers retarget with newer rank/revision.\n";
            if (_ContestedFirstWinnerTicket > 0)
            { DisplayText = f"{DisplayText}firstWinner=ticket {_ContestedFirstWinnerTicket}; ticket 1 was admitted first.\n"; }
        }
        DisplayText = f"{DisplayText}revision={_Queue.Get_Revision()} joins={_JoinSucceeded}/{_JoinRejected} events={_EventCount}\n";
        for (auto Line : _Trace) { DisplayText = f"{DisplayText}{Line}\n"; }
        CkGym_Common::Update_StationDisplay(Get_StationHandle("Gym.Queue.Live"), "QUEUE: LIVE CROWD AGENTS", DisplayText,
            "Options: 1 Reset | 2 Population | 3 Layout | 4 Origins | 5 Environment | 6 Visualization | 7 Advance | 8 Destroy agent | 9 Destroy owner | 0 Slot claiming | R Contested slot race: late tickets start closer; target lines and CLAIMED labels are the visual oracle | Ck_GymQueue_Digest snapshot");
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
