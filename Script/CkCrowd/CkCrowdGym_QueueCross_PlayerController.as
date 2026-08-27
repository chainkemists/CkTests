// --------------------------------------------------------------------------------------------------------------------
// Crowd Queue-Cross Gym - PlayerController
//
// See CkCrowdGym_QueueCross_GameMode.as for the console surface and what to watch.
//
// Layout (station-local; +X is toward the player camera after the cycler's rotation):
//   - 14 line members parked in a row along Y at local X = LineOffset, 95cm spacing - close enough
//     that their painted markup discs merge into one band.
//   - 6 crossers spawn 600 before the line; each goal sits only 200 PAST the line at a Y between
//     two members, so the straight route always crosses the band mid-line.
//   - Crossers dispatch only after every member's markup is CONFIRMED on the navmesh (with a
//     bounded wait), because unpainted members are invisible to planning.
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_QueueCross_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _PcEntity;
    private FCk_Handle _StationHandle;
    private FCk_Handle _NavProbeEntity;
    private TArray<FCk_Handle_CrowdAgent> _LineMembers;
    private TArray<FCk_Handle_CrowdAgent> _Crossers;
    private bool _AutoSpawned = false;
    private bool _CrossersDispatched = false;
    private float _ConfirmWaitSec = 0.0;

    private const float SpawnZ           = 100.0;
    private const float LineOffset       = 800.0;
    private const float LineSpacingY     = 95.0;
    private const int32 LineCount        = 14;
    private const int32 CrosserCount     = 6;
    private const float CrosserApproach  = 600.0;
    private const float CrosserOvershoot = 200.0;
    private const float ConfirmPollSec   = 0.5;
    private const float ConfirmTimeoutSec = 12.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.QueueCross");
            Station.AutoSize = true;
            Station.Title = FText::FromString("CROWD QUEUE CROSS (goal just past a line)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("14 parked agents form a line; 6 crossers auto-dispatch to goals just 200cm past it."));
            Description.Add(FText::FromString("Expected: every crosser routes AROUND an end of the line; the queue never moves."));
            Description.Add(FText::FromString("Defect: crossers plan straight through, press into bodies, jitter, never arrive."));
            Description.Add(FText::FromString("Console: Ck_GymCrowd_QueueCross_Spawn / _Reset / _Digest"));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _PcEntity = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_PcEntity))
        {
            ck::crowd::Warning("QueueCross gym: PC entity invalid; cannot start");
            return;
        }

        _StationHandle = Get_StationHandle("Gym.Crowd.QueueCross");
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::crowd::Warning("QueueCross gym: station handle invalid at StartGym");
            return;
        }

        SpawnFloor();
        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);

        const auto ProbeStart = Local_To_World(FVector(LineOffset - CrosserApproach, 0.0, SpawnZ));
        const auto ProbeGoal  = Local_To_World(FVector(LineOffset + CrosserOvershoot, 300.0, SpawnZ));
        _NavProbeEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        utils_transform::Add(_NavProbeEntity,
            FTransform(FRotator::ZeroRotator, ProbeStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::BindTo_OnPathReady(_NavProbeEntity,
            FCk_Delegate_Nav_OnPathReady(this, n"OnNavProbeReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::BindTo_OnPathFailed(_NavProbeEntity,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnNavProbeFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::Request_FindPath(_NavProbeEntity, FCk_Request_Nav_FindPath(ProbeGoal));

        ck::crowd::Log("QueueCross gym started - the line auto-spawns once the navmesh probe resolves; crossers follow when its markup confirms.");
    }

    UFUNCTION()
    private void OnNavProbeReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (_AutoSpawned)
        { return; }

        _AutoSpawned = true;
        Ck_GymCrowd_QueueCross_Spawn();
    }

    UFUNCTION()
    private void OnNavProbeFailed(FCk_Handle InHandle)
    {
        ck::crowd::Log("QueueCross gym: navmesh probe failed - auto-spawn skipped; run Ck_GymCrowd_QueueCross_Spawn manually once the navmesh is visible.");
    }

    // ---- Geometry ----------------------------------------------------------------------------------

    private FVector Local_To_World(FVector InLocalOffset)
    {
        const auto StationXform = Get_StationAnchorTransform("Gym.Crowd.QueueCross", ECk_GymStation_Anchor::FootprintCenter);
        return StationXform.TransformPosition(InLocalOffset);
    }

    private void SpawnFloor()
    {
        // Z SCALE MUST BE >= 0.5 - thinner and the navmesh bake silently produces no tiles.
        auto Floor = SpawnActor(ACk_Gym_Floor, FVector::ZeroVector, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::crowd::Warning("QueueCross gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FVector(75.0, 75.0, 0.5));
        FinishSpawningActor(Floor);
    }

    // ---- Console commands ----------------------------------------------------------------------------

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // A queue that has already dispersed shows nothing, so re-spawning it is how this gym is watched
    // more than once.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "CROWD: QUEUE CROSS";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::S, "S", "Spawn the line + crossers"));
        Rows.Add(CkGym_Control::Action(EKeys::C, "C", "Reset - destroy agents"));
        Rows.Add(CkGym_Control::Action(EKeys::D, "D", "Emit per-agent digest"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Ck_GymCrowd_QueueCross_Spawn(); }
        else if (InRowIndex == 1) { Ck_GymCrowd_QueueCross_Reset(); }
        else if (InRowIndex == 2) { Ck_GymCrowd_QueueCross_Digest(); }
    }

    UFUNCTION(Exec, DisplayName="Crowd QueueCross - Spawn Line + Crossers")
    void Ck_GymCrowd_QueueCross_Spawn()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        // The line: parked (no MoveTo), so each member paints stationary markup where it stands.
        const auto SpanY = float(LineCount - 1) * LineSpacingY;
        for (int32 i = 0; i < LineCount; ++i)
        {
            const auto SlotY = (float(i) * LineSpacingY) - (SpanY * 0.5);
            const auto Loc = Local_To_World(FVector(LineOffset, SlotY, SpawnZ));
            _LineMembers.Add(SpawnAgent(Loc, Loc, FLinearColor(0.55, 0.55, 0.6, 1.0), FName(f"QueueLine_{i}"), false));
        }

        _CrossersDispatched = false;
        _ConfirmWaitSec = 0.0;

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(ConfirmPollSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(_PcEntity, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnConfirmPoll"));

        ck::crowd::Log(f"QueueCross gym: parked {LineCount} line members - crossers dispatch once their markup confirms");
    }

    UFUNCTION()
    private void OnConfirmPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_CrossersDispatched)
        { return; }

        _ConfirmWaitSec += ConfirmPollSec;

        auto AllConfirmed = _LineMembers.Num() > 0;
        for (auto Member : _LineMembers)
        {
            if (ck::Is_NOT_Valid(Member) ||
                utils_crowd_agent::Get_IsStationaryMarkupConfirmed(Member) == false)
            {
                AllConfirmed = false;
                break;
            }
        }

        if (AllConfirmed == false && _ConfirmWaitSec < ConfirmTimeoutSec)
        { return; }

        if (AllConfirmed == false)
        {
            ck::crowd::Log(f"QueueCross gym: markup not fully confirmed after {ConfirmTimeoutSec}s - dispatching crossers anyway (planning may not see the whole line)");
        }

        DispatchCrossers();
    }

    private void DispatchCrossers()
    {
        _CrossersDispatched = true;

        // Goals sit BETWEEN member Y positions so a straight route always crosses the band
        // mid-line, never conveniently at an end.
        for (int32 i = 0; i < CrosserCount; ++i)
        {
            const auto SlotY = (float(i) - (float(CrosserCount - 1) * 0.5)) * (LineSpacingY * 1.5);
            const auto SpawnLoc = Local_To_World(FVector(LineOffset - CrosserApproach, SlotY, SpawnZ));
            const auto GoalLoc  = Local_To_World(FVector(LineOffset + CrosserOvershoot, SlotY, SpawnZ));

            const auto HueDeg = (360.0 / float(CrosserCount)) * float(i);
            const auto Color = FLinearColor::MakeFromHSV8(uint8(HueDeg * 255.0 / 360.0), 220, 240);
            _Crossers.Add(SpawnAgent(SpawnLoc, GoalLoc, Color, FName(f"QueueCrosser_{i}"), true));
        }

        ck::crowd::Log(f"QueueCross gym: dispatched {CrosserCount} crossers to goals {CrosserOvershoot}cm past the line");
    }

    UFUNCTION(Exec, DisplayName="Crowd QueueCross - Reset (Destroy Agents)")
    void Ck_GymCrowd_QueueCross_Reset()
    {
        if (HasAuthority() == false)
        { return; }

        auto Count = 0;
        for (auto Agent : _LineMembers)
        {
            if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); Count += 1; }
        }
        for (auto Agent : _Crossers)
        {
            if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); Count += 1; }
        }
        _LineMembers.Empty();
        _Crossers.Empty();
        _CrossersDispatched = false;
        ck::crowd::Log(f"QueueCross gym: destroyed {Count} agents");
    }

    UFUNCTION(Exec, DisplayName="Crowd QueueCross - Emit Per-Agent Digest")
    void Ck_GymCrowd_QueueCross_Digest()
    {
        if (HasAuthority() == false)
        { return; }

        for (int32 i = 0; i < _LineMembers.Num(); ++i)
        {
            if (ck::Is_NOT_Valid(_LineMembers[i])) { continue; }
            utils_crowd_agent_diag::EmitDigest_ForAgent(_LineMembers[i], 0, "QueueCrossLine", i);
        }
        for (int32 i = 0; i < _Crossers.Num(); ++i)
        {
            if (ck::Is_NOT_Valid(_Crossers[i])) { continue; }
            utils_crowd_agent_diag::EmitDigest_ForAgent(_Crossers[i], 0, "QueueCrosser", i);
        }
        ck::crowd::Log("QueueCross gym: emitted digests - grep [CrowdDiag]");
    }

    // ---- Agent factory ---------------------------------------------------------------------------

    private FCk_Handle_CrowdAgent SpawnAgent(FVector InSpawnLoc, FVector InTargetLoc, FLinearColor InColor, FName InDebugName, bool InIssueMove)
    {
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        AgentEntity.Set_DebugName(InDebugName);

        // Grounding is displacement-driven (ConstrainToNavmesh only moves an agent that moves), so
        // a parked line member spawned above the floor hovers there forever. Snap every spawn to
        // the mesh.
        auto GroundedSpawn = InSpawnLoc;
        FVector Snapped;
        if (utils_nav::Try_ProjectOntoNavmesh(_PcEntity, InSpawnLoc, 200.0, Snapped, 300.0))
        { GroundedSpawn = Snapped; }

        const auto LookDir   = InTargetLoc - InSpawnLoc;
        const auto PlanarDir = FVector(LookDir.X, LookDir.Y, 0.0);
        const auto Rot       = PlanarDir.Size() < 1.0 ? FRotator::ZeroRotator : PlanarDir.GetSafeNormal().Rotation();

        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(Rot, GroundedSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_crowd_agent::Set_DebugColor(Agent, InColor);

        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        if (InIssueMove)
        {
            utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(InTargetLoc));
        }

        utils_crowd_agent_diag::Track(Agent, InSpawnLoc, InTargetLoc);

        return Agent;
    }
}
