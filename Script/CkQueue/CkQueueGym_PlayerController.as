// Language=angelscript
// --------------------------------------------------------------------------------------------------------------------
// QUEUE GYM
//
// A live CrowdAgent adapter demo for the framework queue.  The commands deliberately exercise the
// semantic queue boundary, rather than writing queue fragments: events/completions below are the surface a
// GOAP planner would bind to.  All geometry is procedural so this gym needs no new assets.
// --------------------------------------------------------------------------------------------------------------------

class ACk_QueueGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _PcEntity;
    private FCk_Handle _QueueOwner;
    private FCk_Handle_Queue _Queue;
    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private UCk_NavAreaMarkup_UE _ImpossibleMarkup = nullptr;
    private TArray<FString> _Trace;
    private int32 _JoinSucceeded = 0;
    private int32 _JoinRejected = 0;
    private int32 _EventCount = 0;
    private bool _Linear = false;

    private const float SpawnZ = 110.0f;
    private const float AgentRadius = 42.0f;
    private const float AgentHeight = 192.0f;
    private const int32 HardLimit = 6;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false) { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        AddStation(Stations, n"Gym.Queue.Live", "QUEUE: LIVE CROWD AGENTS",
            "Ck_GymQueue_Start spawns six CrowdAgents and joins them through the CrowdQueue adapter.\nWatch each agent move to its assigned queue slot; event trace is below.");
        AddStation(Stations, n"Gym.Queue.Reflow", "QUEUE: ORIGIN MOVE + REFLOW",
            "Ck_GymQueue_MoveOrigin moves the queue origin; every member gets a revisioned new target.\nCk_GymQueue_Advance 0 releases the current front.");
        AddStation(Stations, n"Gym.Queue.Split", "QUEUE: MULTIPLE ORIGINS",
            "Ck_GymQueue_TwoOrigins configures weight 1:2 origins and reflows the six live agents.\nSnapshot ranks/origin assignment are printed in the trace.");
        AddStation(Stations, n"Gym.Queue.Navigation", "QUEUE: TIGHT / IMPOSSIBLE NAV",
            "Ck_GymQueue_Impossible paints a NavArea_Null hole over the slots, then rebuilds.\nCk_GymQueue_RestoreNav removes it: retry waits for a navigation generation change.");
        AddStation(Stations, n"Gym.Queue.Contracts", "QUEUE: LIMITS, DESTRUCTION, GOAP EVENTS",
            "Ck_GymQueue_Overfill requests two extra joins (hard limit completes Failed).\nCk_GymQueue_DestroyAgent 0 and Ck_GymQueue_DestroyOwner demonstrate resilient teardown.\nCk_GymQueue_ToggleLayout switches orthogonal snake / linear and reflows.");

        const float StationSpacing = 1600.0f;
        const auto RowStartOffset = -(Stations.Num() - 1) * StationSpacing * 0.5f;
        for (int32 Index = 0; Index < Stations.Num(); Index++)
        {
            auto StationTransform = FTransform::Identity;
            StationTransform.SetLocation(FVector(
                500.0f,
                RowStartOffset + Index * StationSpacing,
                DefaultStationGridZ));
            StationTransform.SetRotation(FRotator(0.0f, 180.0f, 0.0f).Quaternion());
            Stations[Index].Transform = StationTransform;
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false) { return; }
        _PcEntity = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_PcEntity)) { ck::Warning("Queue gym requires its PlayerController entity"); return; }
        Ck_GymQueue_Start();
    }

    UFUNCTION(Exec, DisplayName="Queue - Start / Reset Live Demo")
    void Ck_GymQueue_Start()
    {
        if (HasAuthority() == false) { return; }
        ResetScenario();
        _Trace.Empty();
        _JoinSucceeded = 0;
        _JoinRejected = 0;
        _EventCount = 0;

        const auto Origin = Get_StationAnchorTransform("Gym.Queue.Live", ECk_GymStation_Anchor::FootprintCenter);
        _QueueOwner = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        utils_transform::Add(_QueueOwner, Origin, ECk_Replication::DoesNotReplicate);

        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform::Identity));
        auto Params = FCk_Fragment_Queue_ParamsData(Origins);
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

        for (int32 i = 0; i < HardLimit; ++i)
        {
            const auto X = -500.0f - float(Math::IntegerDivisionTrunc(i, 3)) * 120.0f;
            const auto Y = (float(i % 3) - 1.0f) * 130.0f;
            auto Agent = SpawnAgent(Origin.TransformPosition(FVector(X, Y, SpawnZ)), i);
            _Agents.Add(Agent);
            Agent.Request_JoinQueue(_Queue,
                FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
        }
        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);
        AddTrace("START: six CrowdAgents requested queue admission through the adapter");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Move Origin (Reflow)")
    void Ck_GymQueue_MoveOrigin()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_Queue)) { return; }
        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform(FRotator(0.0f, 90.0f, 0.0f), FVector(280.0f, 0.0f, 0.0f), FVector::OneVector)));
        _Queue.Request_SetOrigins(FCk_Request_Queue_SetOrigins(Origins));
        AddTrace("COMMAND: origin moved + rotated; queue will reflow with fresh assignment revisions");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Use Two Weighted Origins")
    void Ck_GymQueue_TwoOrigins()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_Queue)) { return; }
        auto Origins = TArray<FCk_Queue_Origin>();
        auto Left = FCk_Queue_Origin(FTransform(FRotator::ZeroRotator, FVector(0.0f, -280.0f, 0.0f), FVector::OneVector));
        Left.Set_Weight(1);
        auto Right = FCk_Queue_Origin(FTransform(FRotator::ZeroRotator, FVector(0.0f, 280.0f, 0.0f), FVector::OneVector));
        Right.Set_Weight(2);
        Origins.Add(Left);
        Origins.Add(Right);
        _Queue.Request_SetOrigins(FCk_Request_Queue_SetOrigins(Origins));
        AddTrace("COMMAND: two origins configured (left weight 1, right weight 2); inspect origin/rank snapshots");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Advance Origin")
    void Ck_GymQueue_Advance(int32 InOrigin = 0)
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_Queue)) { return; }
        _Queue.Request_AdvanceOrigin(FCk_Request_Queue_AdvanceOrigin(InOrigin));
        AddTrace(f"COMMAND: advance requested at origin {InOrigin}");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Toggle Orthogonal Snake / Linear")
    void Ck_GymQueue_ToggleLayout()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_Queue)) { return; }
        _Linear = !_Linear;
        const auto Layout = _Linear ? ECk_Queue_LayoutAlgorithm::Linear : ECk_Queue_LayoutAlgorithm::OrthogonalSnake;
        _Queue.Request_SetLayout(FCk_Request_Queue_SetLayout(Layout));
        AddTrace(f"COMMAND: layout switched to {Layout}; all slots receive a new revision");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Make Formation Impossible")
    void Ck_GymQueue_Impossible()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_QueueOwner)) { return; }
        RestoreMarkup();
        const auto OwnerTransform = utils_transform::Get_EntityCurrentTransform(utils_transform::DoCastChecked(_QueueOwner));
        _ImpossibleMarkup = utils_nav_area_markup::Request_Create(_PcEntity,
            OwnerTransform, FVector(900.0f, 900.0f, 300.0f), UNavArea_Null);
        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);
        AddTrace("COMMAND: NavArea_Null covers every slot. Formation should retry then wait for nav revision.");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Restore Navigation")
    void Ck_GymQueue_RestoreNav()
    {
        if (HasAuthority() == false) { return; }
        RestoreMarkup();
        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);
        AddTrace("COMMAND: NavArea_Null removed and test rebuild requested; NavigationChanged should reopen formation.");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Overfill Hard Limit")
    void Ck_GymQueue_Overfill()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_Queue)) { return; }
        const auto Origin = Get_StationAnchorTransform("Gym.Queue.Contracts", ECk_GymStation_Anchor::FootprintCenter);
        for (int32 i = 0; i < 2; ++i)
        {
            auto Agent = SpawnAgent(Origin.TransformPosition(FVector(-400.0f, float(i) * 100.0f, SpawnZ)), 100 + i);
            _Agents.Add(Agent);
            Agent.Request_JoinQueue(_Queue,
                FCk_Delegate_Request_OnCompleted(this, n"OnJoinCompleted"));
        }
        AddTrace("COMMAND: two extra agents requested. Hard-limit completion and event are planner-visible feedback.");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Destroy Agent By Index")
    void Ck_GymQueue_DestroyAgent(int32 InIndex = 0)
    {
        if (HasAuthority() == false || InIndex < 0 || InIndex >= _Agents.Num()) { return; }
        if (ck::IsValid(_Agents[InIndex]))
        {
            utils_entity_lifetime::Request_DestroyEntity(_Agents[InIndex]);
            AddTrace(f"COMMAND: agent {InIndex} destroyed without Leave; reconciliation must reflow survivors.");
        }
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Destroy Queue Owner")
    void Ck_GymQueue_DestroyOwner()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_QueueOwner)) { return; }
        utils_entity_lifetime::Request_DestroyEntity(_QueueOwner);
        AddTrace("COMMAND: queue owner destroyed. Invalidated event must arrive before adapter callbacks can re-enter.");
        RefreshDisplays();
    }

    UFUNCTION(Exec, DisplayName="Queue - Print Snapshot / GOAP Trace")
    void Ck_GymQueue_Digest()
    {
        if (HasAuthority() == false) { return; }
        EmitSnapshot();
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnJoinCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
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
        AddTrace(f"GOAP event: {InEvent.Get_Reason()} member={Member.Get_Member().ToString()} rank={Member.Get_Rank()} rev={InEvent.Get_QueueRevision()}");
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnPressure(FCk_Handle_Queue InQueue, FCk_Queue_Pressure InPressure)
    {
        if (InQueue != _Queue) { return; }
        AddTrace(f"GOAP pressure: count={InPressure.Get_MemberCount()} soft={InPressure.Get_IsSoftLimited()} hard={InPressure.Get_IsHardLimited()}");
    }

    UFUNCTION()
    private void OnFormation(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        if (InQueue != _Queue) { return; }
        AddTrace(f"GOAP formation: {InState.Get_State()} reason={InState.Get_Reason()} retry={InState.Get_RetryEpisode()}");
        RefreshDisplays();
    }

    UFUNCTION()
    private void OnInvalidated(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        AddTrace(f"GOAP invalidated: reason={InState.Get_Reason()} rev={InState.Get_QueueRevision()}");
        RefreshDisplays();
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
        const auto Hue = uint8((InIndex * 47) % 255);
        utils_crowd_agent::Set_DebugColor(Agent, FLinearColor::MakeFromHSV8(Hue, 210, 240));
        utils_velocity::Add(Entity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Entity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Entity);
        return Agent;
    }

    private void ResetScenario()
    {
        RestoreMarkup();
        for (auto Agent : _Agents)
        { if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); } }
        _Agents.Empty();
        if (ck::IsValid(_QueueOwner)) { utils_entity_lifetime::Request_DestroyEntity(_QueueOwner); }
        _QueueOwner = FCk_Handle();
        _Queue = FCk_Handle_Queue();
    }

    private void RestoreMarkup()
    {
        if (ck::IsValid(_ImpossibleMarkup)) { utils_nav_area_markup::Request_Destroy(_ImpossibleMarkup); }
        _ImpossibleMarkup = nullptr;
    }

    private void EmitSnapshot()
    {
        if (ck::Is_NOT_Valid(_Queue)) { AddTrace("DIGEST: queue is invalid"); return; }
        const auto Members = _Queue.Get_Members();
        const auto Pressure = _Queue.Get_Pressure();
        AddTrace(f"DIGEST: count={Pressure.Get_MemberCount()} hard={Pressure.Get_IsHardLimited()} revision={_Queue.Get_Revision()} layout={_Queue.Get_LayoutAlgorithm()}");
        for (auto Member : Members)
        { AddTrace(f"  ticket={Member.Get_Ticket()} origin={Member.Get_OriginIndex()} rank={Member.Get_Rank()} state={Member.Get_State()} assignment={Member.Get_AssignmentRevision()}"); }
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
        auto TraceText = "GOAP-REACTIVE QUEUE TRACE\n";
        TraceText = f"{TraceText}joins accepted={_JoinSucceeded} rejected={_JoinRejected} events={_EventCount}\n";
        for (auto Line : _Trace) { TraceText = f"{TraceText}{Line}\n"; }
        CkGym_Common::Update_StationDisplay(Get_StationHandle("Gym.Queue.Contracts"), "QUEUE: LIMITS, DESTRUCTION, GOAP EVENTS", TraceText,
            "Commands: Ck_GymQueue_Overfill | _DestroyAgent 0 | _DestroyOwner | _Digest");

        const auto Pressure = _Queue.Get_Pressure();
        auto LiveText = f"members={Pressure.Get_MemberCount()} soft={Pressure.Get_IsSoftLimited()} hard={Pressure.Get_IsHardLimited()}\n";
        LiveText = f"{LiveText}layout={_Queue.Get_LayoutAlgorithm()} revision={_Queue.Get_Revision()}\n";
        LiveText = f"{LiveText}Ck_GymQueue_MoveOrigin | _TwoOrigins | _Advance 0 | _ToggleLayout";
        CkGym_Common::Update_StationDisplay(Get_StationHandle("Gym.Queue.Live"), "QUEUE: LIVE CROWD AGENTS", LiveText,
            "Crowd agents receive movement only through the queue adapter's assignments.");
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
