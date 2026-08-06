// --------------------------------------------------------------------------------------------------------------------
// Crowd Diagnostic Gym — PlayerController
//
// Auto-cycling driver. See CkCrowdGym_Diag_GameMode.as for the cycle timeline.
//
// Layout: TWO stations (HeadOn + Cluster) registered via Get_RequiredStations and placed by
// the cycler grid layout — so they appear in the same place every other gym's stations do
// (relative to player spawn). Agents and floor are anchored to the actual station transforms
// via Get_StationAnchorTransform + TransformPosition, so wherever the cycler puts the stations,
// the content follows.
//
// EmitDigest() is a stub here; Task E swaps in per-agent digest emission backed by the C++
// FProcessor_CrowdAgent_DiagRecorder samples (Task D).
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Diag_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _HeadOnStation;
    private FCk_Handle _ClusterStation;
    private TArray<FCk_Handle_CrowdAgent> _HeadOnAgents;
    private TArray<FCk_Handle_CrowdAgent> _ClusterAgents;

    // ---- Auto-cycle state ----------------------------------------------------------------------

    private bool  _AutoCycleEnabled = true;
    private bool  _CycleActive = false;
    private bool  _DigestEmittedForCycle = false;
    private bool  _OverlapWaveFiredForCycle = false;
    private int32 _CycleNumber = 0;
    private float _CycleElapsedSec = 0.0;

    // 100ms phase tracker — coarse on purpose. The C++ recorder samples at ck.Crowd.DiagSampleHz
    // independently so visual cycling and data sampling decouple.
    private const float TickIntervalSec   = 0.1;
    private const float OverlapWaveAtSec  = 4.5;   // originals have converged near goal; spawn 2nd wave on top
    private const float DigestAtSec       = 9.0;
    private const float CleanupAtSec      = 10.0;

    // ---- Per-station spawn offsets (in station-LOCAL space) ------------------------------------

    // After the cycler's 180° rotation, station-local +X maps to "in front of the alcove" (toward
    // the player camera). Putting agents at +X local means they spawn in front of their station
    // and are visible from the default player viewpoint. Y splits agents side-to-side.
    private const float SpawnZ           = 100.0;
    private const float HeadOnFwdOffset  = 600.0;   // 600cm in front of HeadOn station
    private const float HeadOnHalfSpan   = 750.0;   // ±750cm sideways → 1500cm head-on apart
    private const float ClusterFwdOffset = 800.0;  // 800cm in front of Cluster station
    private const float ClusterRadius    = 600.0;
    private const int32 ClusterCount     = 5;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        // Default grid layout would place these 800cm apart in Y — too close: HeadOn agents fan
        // out ±750cm and Cluster has a 600cm radius, so the regions would touch the moment they
        // spawn. Set explicit transforms with 3000cm Y spacing so the regions are well clear of
        // each other (≥4× the head-on agents' goal distance of 750cm). X=500 + Yaw=180 mirrors
        // what Request_ApplyDefaultGridLayout would set if we didn't override.
        const auto StationX     = 500.0;
        const auto StationYHalf = 1500.0;
        const auto StationRot   = FRotator(0.0, 180.0, 0.0);

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.Diag.HeadOn");
            Station.AutoSize = true;
            Station.Transform = FTransform(StationRot, FVector(StationX, +StationYHalf, 0.0), FVector::OneVector);
            Station.Title = FText::FromString("HEAD-ON (auto-cycle)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("2 agents 1500cm apart on a head-on collision course."));
            Description.Add(FText::FromString("Cycles every 10s; digest log at +9s; overlap wave at +4.5s."));
            Description.Add(FText::FromString("Console: Ck_GymCrowd_Diag_Pause / Resume / DumpNow / SpawnOverlapNow"));
            Station.Description = Description;
            Stations.Add(Station);
        }
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.Diag.Cluster");
            Station.AutoSize = true;
            Station.Transform = FTransform(StationRot, FVector(StationX, -StationYHalf, 0.0), FVector::OneVector);
            Station.Title = FText::FromString("CLUSTER (auto-cycle)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("5 agents on a 600cm circle, all targeting the centre."));
            Description.Add(FText::FromString("Breadcrumb trail: ck.Crowd.DiagDrawBreadcrumb 1 (default on)."));
            Description.Add(FText::FromString("Overlap wave at +4.5s: 5 more agents spawn ON TOP of the originals (Z-bug repro)."));
            Station.Description = Description;
            Stations.Add(Station);
        }
        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _HeadOnStation = Get_StationHandle("Gym.Crowd.Diag.HeadOn");
        _ClusterStation = Get_StationHandle("Gym.Crowd.Diag.Cluster");
        if (ck::Is_NOT_Valid(_HeadOnStation) || ck::Is_NOT_Valid(_ClusterStation))
        {
            ck::crowd::Warning("Diag gym: station handle(s) invalid at StartGym");
            return;
        }

        SpawnFloor();

        // Recurring 100ms ticker drives the cycle state machine. Owned by the HeadOn station so
        // it cascade-destroys on gym change.
        auto TickerParams = FCk_Timer_Spec(FCk_Time(TickIntervalSec));
        TickerParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Ticker = utils_timer::Add(_HeadOnStation, TickerParams);
        Ticker.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCycleTick"));

        BeginCycle();

        ck::crowd::Log("Diag gym started. Auto-cycling on; pause via Ck_GymCrowd_Diag_Pause.");
    }

    private void SpawnFloor()
    {
        // Single big floor at world origin — the cycler map's NavMeshBoundsVolume is centred
        // at origin, so a floor at origin lands fully inside it. 7500x7500x50cm covers both
        // stations (placed at X=500, Y=±1500) plus their spawn radii with margin.
        //
        // Z SCALE MUST BE >= 0.5 — anything thinner and the navmesh bake silently produces
        // no walkable tiles on the surface (grey floor in the navmesh viewer). Recast's tile
        // generator filters out geometry below a height threshold relative to the agent's
        // CellHeight; 50cm slabs sit comfortably above it.
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(75.0, 75.0, 0.5);   // 7500x7500x50cm

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::crowd::Warning("Diag gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);

        ck::crowd::Log(f"Diag gym: floor spawned at {FloorLocation} scale={FloorScale}");
    }

    // ---- Station-local -> world ----------------------------------------------------------------

    // Project a station-LOCAL offset into world space using the station's actual placed transform.
    // Station-local +X maps to "in front of station's alcove" (toward the player camera) after the
    // cycler's 180° rotation. So local +X offsets always land in the visible play area regardless
    // of where the grid layout positioned the station.
    private FVector StationLocal_To_World(FString InStationTag, FVector InLocalOffset)
    {
        const auto StationXform = Get_StationAnchorTransform(InStationTag, ECk_GymStation_Anchor::FootprintCenter);
        return StationXform.TransformPosition(InLocalOffset);
    }

    // ---- Cycle driver --------------------------------------------------------------------------

    private void BeginCycle()
    {
        ++_CycleNumber;
        _CycleElapsedSec = 0.0;
        _CycleActive = true;
        _DigestEmittedForCycle = false;
        _OverlapWaveFiredForCycle = false;

        SpawnHeadOnAgents();
        SpawnClusterAgents();

        ck::crowd::Log(f"[CrowdDiag][C{_CycleNumber}] cycle started: 2 head-on + 5 cluster agents dispatched");
    }

    private void EndCycle()
    {
        DestroyAgents();
        _CycleActive = false;
        ck::crowd::Log(f"[CrowdDiag][C{_CycleNumber}] cycle ended: agents destroyed");
    }

    UFUNCTION()
    void OnCycleTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (HasAuthority() == false) { return; }
        if (_AutoCycleEnabled == false) { return; }

        if (_CycleActive == false)
        {
            BeginCycle();
            return;
        }

        _CycleElapsedSec += TickIntervalSec;

        if (_OverlapWaveFiredForCycle == false && _CycleElapsedSec >= OverlapWaveAtSec)
        {
            SpawnOverlapWave();
            _OverlapWaveFiredForCycle = true;
        }

        if (_DigestEmittedForCycle == false && _CycleElapsedSec >= DigestAtSec)
        {
            EmitDigest();
            _DigestEmittedForCycle = true;
        }

        if (_CycleElapsedSec >= CleanupAtSec)
        {
            EndCycle();
        }
    }

    // ---- Stations ------------------------------------------------------------------------------

    private void SpawnHeadOnAgents()
    {
        const auto SpawnA = StationLocal_To_World("Gym.Crowd.Diag.HeadOn", FVector(HeadOnFwdOffset, +HeadOnHalfSpan, SpawnZ));
        const auto SpawnB = StationLocal_To_World("Gym.Crowd.Diag.HeadOn", FVector(HeadOnFwdOffset, -HeadOnHalfSpan, SpawnZ));
        _HeadOnAgents.Add(SpawnAgent(SpawnA, SpawnB, FLinearColor(0.42, 0.85, 1.0, 0.6), n"DiagAgent_HeadOn_W0_0"));
        _HeadOnAgents.Add(SpawnAgent(SpawnB, SpawnA, FLinearColor(1.0, 0.42, 0.85, 0.6), n"DiagAgent_HeadOn_W0_1"));
    }

    private void SpawnClusterAgents()
    {
        const auto Centre = StationLocal_To_World("Gym.Crowd.Diag.Cluster", FVector(ClusterFwdOffset, 0.0, SpawnZ));
        const auto AngleStep = (2.0 * Math::PI) / float(ClusterCount);
        for (int32 i = 0; i < ClusterCount; ++i)
        {
            const auto Angle = AngleStep * float(i);
            const auto Offset = FVector(ClusterRadius * Math::Cos(Angle), ClusterRadius * Math::Sin(Angle), 0.0);
            const auto SpawnLoc = Centre + Offset;
            const auto HueDeg = (360.0 / float(ClusterCount)) * float(i);
            const auto Color = FLinearColor::MakeFromHSV8(uint8(HueDeg * 255.0 / 360.0), 200, 220);
            _ClusterAgents.Add(SpawnAgent(SpawnLoc, Centre, Color, FName(f"DiagAgent_Cluster_W0_{i}")));
        }
    }

    // Spawn a second wave AT the current world positions of every existing agent. The fresh
    // agent and the original instantly occupy the same XY (and Z) — push-apart engages on the
    // same frame. This is the canonical repro for the Z-offset / floor-clip bug: under enough
    // overlap pressure, push-apart is observed to shove one capsule downward through the floor.
    //
    // Targets are reused from each station's "centre" (HeadOnFwdOffset / ClusterFwdOffset along
    // local +X) so the new wave has somewhere to walk and the recorder collects path data.
    // For HeadOn, originals have already arrived near (and past) centre, so the new wave walks
    // to the alcove-front midpoint. For Cluster, the centre IS where originals are clumped.
    private void SpawnOverlapWave()
    {
        const auto OrigHeadOnCount  = _HeadOnAgents.Num();
        const auto OrigClusterCount = _ClusterAgents.Num();

        const auto HeadOnTarget = StationLocal_To_World("Gym.Crowd.Diag.HeadOn", FVector(HeadOnFwdOffset, 0.0, SpawnZ));
        for (int32 i = 0; i < OrigHeadOnCount; ++i)
        {
            const auto OrigAgent = _HeadOnAgents[i];
            if (ck::Is_NOT_Valid(OrigAgent)) { continue; }
            const auto CurLoc = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(OrigAgent)));
            // Orange-ish tint so wave-1 is visually distinct from wave-0's cyan/pink in PIE.
            const auto Color = FLinearColor(1.0, 0.55, 0.15, 0.6);
            _HeadOnAgents.Add(SpawnAgent(CurLoc, HeadOnTarget, Color, FName(f"DiagAgent_HeadOn_W1_{i}")));
        }

        const auto ClusterTarget = StationLocal_To_World("Gym.Crowd.Diag.Cluster", FVector(ClusterFwdOffset, 0.0, SpawnZ));
        for (int32 i = 0; i < OrigClusterCount; ++i)
        {
            const auto OrigAgent = _ClusterAgents[i];
            if (ck::Is_NOT_Valid(OrigAgent)) { continue; }
            const auto CurLoc = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(OrigAgent)));
            // Hue-shift wave-1 cluster colours by +30° so they're distinguishable from wave-0's
            // even-spaced ring colours.
            const auto HueDeg = (360.0 / float(OrigClusterCount)) * float(i) + 30.0;
            const auto Color = FLinearColor::MakeFromHSV8(uint8(HueDeg * 255.0 / 360.0), 200, 220);
            _ClusterAgents.Add(SpawnAgent(CurLoc, ClusterTarget, Color, FName(f"DiagAgent_Cluster_W1_{i}")));
        }

        ck::crowd::Log(f"[CrowdDiag][C{_CycleNumber}] overlap wave: {OrigHeadOnCount} HeadOn + {OrigClusterCount} Cluster spawned on top of originals");
    }

    private void DestroyAgents()
    {
        for (auto Agent : _HeadOnAgents)
        {
            if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); }
        }
        _HeadOnAgents.Empty();

        for (auto Agent : _ClusterAgents)
        {
            if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); }
        }
        _ClusterAgents.Empty();
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FVector SpawnLoc, FVector TargetLoc, FLinearColor InColor, FName InDebugName)
    {
        // Each agent is a child of the registry transient, not a station entity;
        // DestroyAgents still destroys each explicitly at cycle end.
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        AgentEntity.Set_DebugName(InDebugName);
        // Project the look direction to planar — crowd agents are yaw-only (capsule walks on the
        // navmesh). Without this, overlap-wave agents whose spawn Z ≠ target Z spawn pitched
        // (~30-45° tilt) since FaceAngle's per-tick yaw lerp can't correct pitch.
        const auto LookDir   = TargetLoc - SpawnLoc;
        const auto PlanarDir = FVector(LookDir.X, LookDir.Y, 0.0);
        const auto Rot       = PlanarDir.GetSafeNormal().Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(Rot, SpawnLoc, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        // Stamp the agent's identity colour so every visualisation (DrawBody capsule + cone,
        // breadcrumb path, planned-path overlay, debugger swatch) coordinates on the same color.
        utils_crowd_agent::Set_DebugColor(Agent, InColor);
        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        // Body capsule + forward cone come from FProcessor_CrowdAgent_DrawBody (CkCrowd
        // framework). Color comes from the Set_DebugColor fragment above. Enable in PIE via
        // the Crowd Debugger's "Agent Body" checkbox or `ck.Crowd.Debug.AgentBody 1`.

        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(TargetLoc));

        // Opt this agent into the diagnostic recorder so the path-recorder processor samples it
        // and the cycle-end digest (Task E) has data to dump. The breadcrumb-draw processor
        // (default-on) will draw the trail in PIE.
        utils_crowd_agent_diag::Track(Agent, SpawnLoc, TargetLoc);

        return Agent;
    }

    // ---- Cycle digest --------------------------------------------------------------------------

    // For every tracked agent in this cycle, emit grep-able [CrowdDiag] log lines summarising
    // its run: start/goal, reached + time-to-goal, path length + efficiency, min-sep, dir
    // reversals + max angular delta, and an RDP-simplified breadcrumb of its actual path.
    // Devs grep Saved/Logs/CkTests.log for [CrowdDiag] to compare cycle-to-cycle metrics
    // without staring at the viewport.
    private void EmitDigest()
    {
        // Wave-0 = original spawn (first 2 HeadOn / first ClusterCount Cluster). Wave-1 = overlap.
        // Index in label resets per wave so cycle-to-cycle comparison stays clean even if wave-0
        // spawn count changes later.
        const auto HeadOnWave0Count = 2;
        for (int32 i = 0; i < _HeadOnAgents.Num(); ++i)
        {
            const auto WaveIdx        = i < HeadOnWave0Count ? 0 : 1;
            const auto AgentIdxInWave = i < HeadOnWave0Count ? i : i - HeadOnWave0Count;
            utils_crowd_agent_diag::EmitDigest_ForAgent(_HeadOnAgents[i], _CycleNumber, f"HeadOn_W{WaveIdx}", AgentIdxInWave);
        }
        for (int32 i = 0; i < _ClusterAgents.Num(); ++i)
        {
            const auto WaveIdx        = i < ClusterCount ? 0 : 1;
            const auto AgentIdxInWave = i < ClusterCount ? i : i - ClusterCount;
            utils_crowd_agent_diag::EmitDigest_ForAgent(_ClusterAgents[i], _CycleNumber, f"Cluster_W{WaveIdx}", AgentIdxInWave);
        }
    }

    // ---- Console commands ----------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Crowd Diag - Pause Auto-Cycling")
    void Ck_GymCrowd_Diag_Pause()
    {
        _AutoCycleEnabled = false;
        ck::crowd::Log("Diag gym: auto-cycling PAUSED (current cycle continues until cleanup)");
    }

    UFUNCTION(Exec, DisplayName="Crowd Diag - Resume Auto-Cycling")
    void Ck_GymCrowd_Diag_Resume()
    {
        _AutoCycleEnabled = true;
        ck::crowd::Log("Diag gym: auto-cycling RESUMED");
    }

    UFUNCTION(Exec, DisplayName="Crowd Diag - Dump Cycle Digest Now")
    void Ck_GymCrowd_Diag_DumpNow()
    {
        EmitDigest();
        ck::crowd::Log("Diag gym: forced digest dump — cycle continues");
    }

    UFUNCTION(Exec, DisplayName="Crowd Diag - Spawn Overlap Wave Now")
    void Ck_GymCrowd_Diag_SpawnOverlapNow()
    {
        if (HasAuthority() == false) { return; }
        if (_CycleActive == false)
        {
            ck::crowd::Warning("Diag gym: no active cycle to overlap (wait for next cycle to start)");
            return;
        }
        SpawnOverlapWave();
        // Suppress the auto-fire for this cycle so we don't get a third wave on top.
        _OverlapWaveFiredForCycle = true;
        ck::crowd::Log("Diag gym: manually fired overlap wave");
    }
}
