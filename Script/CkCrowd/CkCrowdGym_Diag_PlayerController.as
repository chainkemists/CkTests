// --------------------------------------------------------------------------------------------------------------------
// Crowd Diagnostic Gym — PlayerController
//
// Auto-cycling driver. See CkCrowdGym_Diag_GameMode.as for the cycle timeline.
//
// Layout: TWO stations (HeadOn + Cluster), MANUALLY placed (bypass cycler grid layout) so the
// spacing between them is controlled — Cluster sits 3000cm from HeadOn (≥4× the head-on agents'
// goal distance of 750cm) so the two test regions can't influence each other.
//
// EmitDigest() is a stub here; Task E swaps in per-agent digest emission backed by the C++
// FProcessor_CrowdDiag_PathRecorder samples (Task D adds the recorder).
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

    // 100ms phase tracker — coarse on purpose. The C++ recorder (Task D) samples agents
    // independently at ck.Crowd.DiagSampleHz so visual cycling and data sampling decouple.
    private const float TickIntervalSec = 0.1;
    private const float DigestAtSec     = 9.0;
    private const float CleanupAtSec    = 10.0;

    // ---- Layout (hand-placed station world locations) ------------------------------------------

    // Stations placed manually so spacing is controllable. Both at X=-3000 (in front of player
    // who spawns near origin, looking toward -X), split along ±Y by 3000cm. With default
    // rotation the alcove opens toward +X (toward the player), so station-local +X is "in front".
    private const FVector HeadOnStationWorld  = FVector(-3000.0, +1500.0, 0.0);
    private const FVector ClusterStationWorld = FVector(-3000.0, -1500.0, 0.0);

    // Spawn offsets are in station-LOCAL space. Local +X is the station's forward (alcove side),
    // which after default-rotation placement maps to world +X.
    private const float SpawnZ           = 100.0;
    private const float HeadOnFwdOffset  = 600.0;   // 600cm in front of HeadOn station
    private const float HeadOnHalfSpan   = 750.0;   // ±750cm sideways → 1500cm head-on apart, mirrors HeadOnPass autotest
    private const float ClusterFwdOffset = 800.0;  // 800cm in front of Cluster station
    private const float ClusterRadius    = 600.0;   // mirrors Convergence autotest
    private const int32 ClusterCount     = 5;

    // Bypass the cycler grid layout — we want manual control over station spacing. Spawn happens
    // in Request_StartGym via Request_SpawnEntity instead.
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        return TArray<FCkGym_Station_SpawnParams_Payload>();
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        SpawnStation("Gym.Crowd.Diag.HeadOn", HeadOnStationWorld,
            "HEAD-ON (auto-cycle)",
            "2 agents 1500cm apart, head-on collision course.");

        SpawnStation("Gym.Crowd.Diag.Cluster", ClusterStationWorld,
            "CLUSTER (auto-cycle)",
            "5 agents on a 600cm circle, all targeting the centre.");

        SpawnFloor();

        // Recurring 100ms ticker drives the cycle state machine. Owner is the world transient
        // entity (not a station) so the ticker survives even if a station entity is mid-spawn
        // when the ticker's owner-check would otherwise fire.
        auto TickerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(TickIntervalSec));
        TickerParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto TransientOwner = ck::TransientEntity();
        auto Ticker = utils_timer::Add(TransientOwner, TickerParams);
        Ticker.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnCycleTick"));

        ck::crowd::Log(f"Diag gym started. Stations placed at {HeadOnStationWorld} and {ClusterStationWorld}.");
    }

    private void SpawnStation(FString InTag, FVector InWorldLocation, FString InTitle, FString InDescription)
    {
        auto Params = FCk_GymStation_SpawnParams();
        Params.InitialTransform = FTransform(FRotator::ZeroRotator, InWorldLocation, FVector(1.0, 1.0, 1.0));
        Params.TitleText = FText::FromString(InTitle);
        Params.DescriptionText.Add(FText::FromString(InDescription));
        Params.DescriptionText.Add(FText::FromString("Cycles every 10s; digest log at +9s."));
        Params.StationTags.Add(FName(InTag));

        utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_EntityScript_GymStation,
            FInstancedStruct::Make(Params));
    }

    private void SpawnFloor()
    {
        // Hardcoded floor centred between the two known station positions (we placed them
        // ourselves above). 8000x8000cm gives generous margin for spawn radii + nav projection.
        const auto FloorLocation = (HeadOnStationWorld + ClusterStationWorld) * 0.5;
        const auto FloorScale    = FVector(80.0, 80.0, 0.5);

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
    // With default-rotation placement, station-local +X maps to world +X (so +X local = "in front
    // of station's alcove" = visible to player).
    private FVector StationLocal_To_World(FString InStationTag, FVector InLocalOffset)
    {
        const auto StationXform = Get_StationAnchorTransform(InStationTag, ECk_GymStation_Anchor::FootprintCenter);
        return StationXform.TransformPosition(InLocalOffset);
    }

    // ---- Cycle driver --------------------------------------------------------------------------

    private void BeginCycle()
    {
        // Cache station handles on first use — by the time the startup grace expires, the
        // manually-spawned station entities have completed Request_SpawnEntity construction.
        if (ck::Is_NOT_Valid(_HeadOnStation))  { _HeadOnStation  = Get_StationHandle("Gym.Crowd.Diag.HeadOn"); }
        if (ck::Is_NOT_Valid(_ClusterStation)) { _ClusterStation = Get_StationHandle("Gym.Crowd.Diag.Cluster"); }
        if (ck::Is_NOT_Valid(_HeadOnStation) || ck::Is_NOT_Valid(_ClusterStation))
        {
            ck::crowd::Warning("Diag gym: station handle(s) still invalid at BeginCycle — postponing one tick");
            return;
        }

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
            // Just resumed or first tick after cleanup — start the next cycle.
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
            // Next tick's _CycleActive==false branch starts the next cycle, giving one frame
            // of "agents gone" visual gap before respawn.
        }
    }

    // ---- Stations ------------------------------------------------------------------------------

    private void SpawnHeadOnAgents()
    {
        // Both agents in front of the HeadOn station, separated 1500cm side-to-side along the
        // station's local Y axis. Targets reversed → head-on collision near (HeadOnFwdOffset, 0).
        const auto SpawnA = StationLocal_To_World("Gym.Crowd.Diag.HeadOn", FVector(HeadOnFwdOffset, +HeadOnHalfSpan, SpawnZ));
        const auto SpawnB = StationLocal_To_World("Gym.Crowd.Diag.HeadOn", FVector(HeadOnFwdOffset, -HeadOnHalfSpan, SpawnZ));
        _HeadOnAgents.Add(SpawnAgent(_HeadOnStation, SpawnA, SpawnB, FLinearColor(0.42, 0.85, 1.0, 0.6)));
        _HeadOnAgents.Add(SpawnAgent(_HeadOnStation, SpawnB, SpawnA, FLinearColor(1.0, 0.42, 0.85, 0.6)));
    }

    private void SpawnClusterAgents()
    {
        // 5 agents on a 600cm circle in front of the Cluster station, all targeting that centre.
        const auto Centre = StationLocal_To_World("Gym.Crowd.Diag.Cluster", FVector(ClusterFwdOffset, 0.0, SpawnZ));
        const auto AngleStep = (2.0 * Math::PI) / float(ClusterCount);
        for (int32 i = 0; i < ClusterCount; ++i)
        {
            const auto Angle = AngleStep * float(i);
            const auto Offset = FVector(ClusterRadius * Math::Cos(Angle), ClusterRadius * Math::Sin(Angle), 0.0);
            const auto SpawnLoc = Centre + Offset;
            // Hue varies around the wheel so individuals are distinguishable in the cluster.
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
        // Same spawn recipe as the Separation gym — agent + Transform + Velocity + Acceleration +
        // EulerIntegrator started, capsule body + forward cone for visuals, MoveTo issued. Owner
        // is the station so the agent cascade-destroys when the gym tears the station down.
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto Agent = utils_crowd_agent::Add(InOwnerStation, Params);

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
        return Agent;
    }

    // ---- Digest stub (filled in by Task E) -----------------------------------------------------

    private void EmitDigest()
    {
        // Task E will replace this with full per-agent digest emission backed by the
        // FProcessor_CrowdDiag_PathRecorder samples (Task D). For Task C we just log the
        // cycle phase boundary so the auto-cycle is visible in the log even before the
        // recorder lands.
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
