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
    private int32 _CycleNumber = 0;
    private float _CycleElapsedSec = 0.0;

    // 100ms phase tracker — coarse on purpose. The C++ recorder samples at ck.Crowd.DiagSampleHz
    // independently so visual cycling and data sampling decouple.
    private const float TickIntervalSec = 0.1;
    private const float DigestAtSec     = 9.0;
    private const float CleanupAtSec    = 10.0;

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
            Description.Add(FText::FromString("Cycles every 10s; digest log at +9s."));
            Description.Add(FText::FromString("Console: Ck_GymCrowd_Diag_Pause / Resume / DumpNow"));
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
        auto TickerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(TickIntervalSec));
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

        auto Floor = SpawnActor(ACk_CrowdGym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
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
        _HeadOnAgents.Add(SpawnAgent(_HeadOnStation, SpawnA, SpawnB, FLinearColor(0.42, 0.85, 1.0, 0.6)));
        _HeadOnAgents.Add(SpawnAgent(_HeadOnStation, SpawnB, SpawnA, FLinearColor(1.0, 0.42, 0.85, 0.6)));
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
            _ClusterAgents.Add(SpawnAgent(_ClusterStation, SpawnLoc, Centre, Color));
        }
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

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwnerStation, FVector SpawnLoc, FVector TargetLoc, FLinearColor InColor)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto Agent = utils_crowd_agent::Add(InOwnerStation, Params);

        // Stamp the agent's identity colour so all visualisations (capsule, breadcrumb path,
        // planned-path overlay, debugger swatch) coordinate. The capsule/cone below still pass
        // InColor directly for now; refactor to read the fragment is a follow-up.
        utils_crowd_agent::Set_DebugColor(Agent, InColor);

        FCk_Handle Generic = Agent;
        const auto Rot = (TargetLoc - SpawnLoc).GetSafeNormal().Rotation();
        utils_transform::Add(Generic, FTransform(Rot, SpawnLoc, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        utils_velocity::Add(Generic, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Generic, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Generic);

        // Capsule body
        auto CapsuleHandle = utils_pmg_basic_shapes::Create_Capsule(
            Generic, FTransform::Identity,
            42.0f, 96.0f, 16, 8,
            ECk_Plane_Axis::XY,
            InColor, true, 2.0f, -1.0f);
        FCk_Handle CapsuleGeneric = CapsuleHandle;
        auto CapsuleXform = utils_transform::DoCastChecked(CapsuleGeneric);
        auto AgentXform = utils_transform::DoCastChecked(Generic);
        const auto CapsuleLocalOffset = FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 96.0), FVector::OneVector);
        utils_scene_node::Add(CapsuleXform, AgentXform, CapsuleLocalOffset);

        // Forward cone
        const auto ConeColor = FLinearColor(InColor.R * 0.8, InColor.G * 0.8, InColor.B * 0.8, 0.85);
        auto ConeHandle = utils_pmg_basic_shapes::Create_Cone(
            Generic, FTransform::Identity,
            15.0f, 60.0f, 12,
            ECk_Plane_Axis::XY,
            ConeColor, true, 1.5f, -1.0f);
        FCk_Handle ConeGeneric = ConeHandle;
        auto ConeXform = utils_transform::DoCastChecked(ConeGeneric);
        const auto ConeLocalOffset = FTransform(FRotator(-90.0, 0.0, 0.0), FVector(60.0, 0.0, 96.0), FVector::OneVector);
        utils_scene_node::Add(ConeXform, AgentXform, ConeLocalOffset);

        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(TargetLoc));

        // Opt this agent into the diagnostic recorder so the path-recorder processor samples it
        // and the cycle-end digest (Task E) has data to dump. The breadcrumb-draw processor
        // (default-on) will draw the trail in PIE.
        utils_crowd_agent_diag::Track(Agent, SpawnLoc, TargetLoc);

        return Agent;
    }

    // ---- Digest stub (filled in by Task E) -----------------------------------------------------

    private void EmitDigest()
    {
        ck::crowd::Log(f"[CrowdDiag][C{_CycleNumber}] cycle digest — TODO(Task E): per-agent metrics + RDP-simplified path");
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
}
