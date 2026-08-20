// --------------------------------------------------------------------------------------------------------------------
// Crowd Narrow-Gap Gym — PlayerController
//
// See CkCrowdGym_NarrowGap_GameMode.as for the console surface and what to watch.
//
// Layout (station-local; +X is toward the player camera after the cycler's rotation):
//   - Wall line perpendicular to the approach at local X = WallLineOffset, split by a GapWidth
//     opening at local Y = 0. Wall boxes carve the navmesh (ACk_CrowdPathingGym_NavBox — nav-only,
//     player walks through).
//   - Walkers spawn in two staggered rows before the wall; each goal is the mirrored point past
//     the wall at the same Y, so every route's shortest form crosses the gap.
//   - Optional flank caps extend the wall line past the floor edge so no detour exists.
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_NarrowGap_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _PcEntity;
    private FCk_Handle _StationHandle;
    private FCk_Handle _NavProbeEntity;
    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private TArray<AActor> _FlankWalls;
    private bool _AutoSpawned = false;

    private const float SpawnZ          = 100.0;
    private const float WallLineOffset  = 800.0;
    private const float GapWidth        = 110.0;
    private const float WallSpanY       = 1000.0;   // each wall: from GapWidth/2 out to GapWidth/2 + WallSpanY
    private const float WallThickness   = 100.0;
    private const float WallHeight      = 200.0;
    private const float ApproachOffset  = 700.0;    // spawn/goal distance before/past the wall line
    private const float RowSpacingY     = 100.0;
    private const int32 DefaultCount    = 20;
    private const int32 AutoSpawnCount  = 20;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.NarrowGap");
            Station.AutoSize = true;
            Station.Title = FText::FromString("CROWD NARROW GAP (110cm pinch)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("20 walkers auto-spawn and funnel through a 110cm gap between nav walls."));
            Description.Add(FText::FromString("Expected: clean single-file traversal — no oscillation inside the pinch."));
            Description.Add(FText::FromString("SpawnBlocked parks one agent IN the gap: walkers must detour around the wall ends."));
            Description.Add(FText::FromString("Flank 1 closes the detour: expect a calm hold / clean goal-failed, never a perpetual press."));
            Description.Add(FText::FromString("Console: Ck_GymCrowd_NarrowGap_Spawn / _SpawnBlocked / _Flank / _Reset / _Digest"));
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
            ck::crowd::Warning("NarrowGap gym: PC entity invalid; cannot start");
            return;
        }

        _StationHandle = Get_StationHandle("Gym.Crowd.NarrowGap");
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::crowd::Warning("NarrowGap gym: station handle invalid at StartGym");
            return;
        }

        SpawnFloor();
        SpawnWalls();

        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);

        // Auto-spawn gate: a probe path from the spawn side through the gap proves the bake
        // (including the wall carve) finished; a timer would race the async tile build.
        const auto ProbeStart = Local_To_World(FVector(WallLineOffset - ApproachOffset, 0.0, SpawnZ));
        const auto ProbeGoal  = Local_To_World(FVector(WallLineOffset + ApproachOffset, 0.0, SpawnZ));
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

        ck::crowd::Log(f"NarrowGap gym started — auto-spawning {AutoSpawnCount} walkers once the navmesh probe resolves.");
    }

    UFUNCTION()
    private void OnNavProbeReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (_AutoSpawned || _Agents.Num() > 0)
        { return; }

        _AutoSpawned = true;
        Ck_GymCrowd_NarrowGap_Spawn(AutoSpawnCount);
    }

    UFUNCTION()
    private void OnNavProbeFailed(FCk_Handle InHandle)
    {
        ck::crowd::Log("NarrowGap gym: navmesh probe failed — auto-spawn skipped; run Ck_GymCrowd_NarrowGap_Spawn manually once the navmesh is visible.");
    }

    // ---- Geometry ----------------------------------------------------------------------------------

    private FVector Local_To_World(FVector InLocalOffset)
    {
        const auto StationXform = Get_StationAnchorTransform("Gym.Crowd.NarrowGap", ECk_GymStation_Anchor::FootprintCenter);
        return StationXform.TransformPosition(InLocalOffset);
    }

    private void SpawnFloor()
    {
        // Z SCALE MUST BE >= 0.5 — thinner and the navmesh bake silently produces no tiles.
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(75.0, 75.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::crowd::Warning("NarrowGap gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);
    }

    private AActor SpawnWallBox(FVector InLocalCentre, FVector InScale)
    {
        const auto WorldLoc = Local_To_World(InLocalCentre);
        auto Wall = SpawnActor(ACk_CrowdPathingGym_NavBox, WorldLoc, FRotator::ZeroRotator, NAME_None, true);
        if (Wall == nullptr)
        {
            ck::crowd::Warning("NarrowGap gym: failed to spawn wall box");
            return nullptr;
        }
        Wall.SetActorScale3D(InScale);
        FinishSpawningActor(Wall);
        return Wall;
    }

    private void SpawnWalls()
    {
        const auto HalfGap    = GapWidth * 0.5;
        const auto WallCentreY = HalfGap + (WallSpanY * 0.5);
        const auto Scale = FVector(WallThickness / 100.0, WallSpanY / 100.0, WallHeight / 100.0);

        SpawnWallBox(FVector(WallLineOffset, WallCentreY, WallHeight * 0.5), Scale);
        SpawnWallBox(FVector(WallLineOffset, -WallCentreY, WallHeight * 0.5), Scale);
    }

    // ---- Console commands ----------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Crowd NarrowGap - Spawn Walkers Through The Gap")
    void Ck_GymCrowd_NarrowGap_Spawn(int32 InCount = 20)
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        const auto Count = InCount > 0 ? InCount : DefaultCount;
        SpawnWalkers(Count, 0);
        ck::crowd::Log(f"NarrowGap gym: dispatched {Count} walkers through the gap");
    }

    UFUNCTION(Exec, DisplayName="Crowd NarrowGap - Spawn Parked Blocker + Walkers")
    void Ck_GymCrowd_NarrowGap_SpawnBlocked(int32 InCount = 20)
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        const auto Count = InCount > 1 ? InCount : DefaultCount;

        // The blocker gets no MoveTo: parked and still, it paints stationary markup and becomes
        // exactly the immovable body the walkers' strict plans must route around.
        const auto BlockerLoc = Local_To_World(FVector(WallLineOffset, 0.0, SpawnZ));
        _Agents.Add(SpawnAgent(BlockerLoc, BlockerLoc, FLinearColor::Red, FName("NarrowGapBlocker"), false));

        SpawnWalkers(Count - 1, 1);
        ck::crowd::Log(f"NarrowGap gym: parked 1 blocker in the gap and dispatched {Count - 1} walkers");
    }

    UFUNCTION(Exec, DisplayName="Crowd NarrowGap - Toggle Flank Caps (1 = no detour exists)")
    void Ck_GymCrowd_NarrowGap_Flank(int32 InClosed = 1)
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        for (auto Wall : _FlankWalls)
        {
            if (Wall != nullptr) { Wall.DestroyActor(); }
        }
        _FlankWalls.Empty();

        if (InClosed != 0)
        {
            // Extend the wall line past the floor's edge (floor half-size 3750) on both sides.
            const auto InnerY  = (GapWidth * 0.5) + WallSpanY;
            const auto FlankLen = 3900.0 - InnerY;
            const auto CentreY = InnerY + (FlankLen * 0.5);
            const auto Scale = FVector(WallThickness / 100.0, FlankLen / 100.0, WallHeight / 100.0);

            _FlankWalls.Add(SpawnWallBox(FVector(WallLineOffset, CentreY, WallHeight * 0.5), Scale));
            _FlankWalls.Add(SpawnWallBox(FVector(WallLineOffset, -CentreY, WallHeight * 0.5), Scale));
        }

        utils_nav::Request_NavigationRebuild_ForTesting(_PcEntity);
        const auto FlankState = InClosed != 0 ? FString("CLOSED (no detour)") : FString("OPEN");
        ck::crowd::Log(f"NarrowGap gym: flank caps {FlankState} — navmesh rebuilding");
    }

    UFUNCTION(Exec, DisplayName="Crowd NarrowGap - Reset (Destroy Agents)")
    void Ck_GymCrowd_NarrowGap_Reset()
    {
        if (HasAuthority() == false)
        { return; }

        const auto Count = _Agents.Num();
        for (auto Agent : _Agents)
        {
            if (ck::IsValid(Agent)) { utils_entity_lifetime::Request_DestroyEntity(Agent); }
        }
        _Agents.Empty();
        ck::crowd::Log(f"NarrowGap gym: destroyed {Count} agents");
    }

    UFUNCTION(Exec, DisplayName="Crowd NarrowGap - Emit Per-Agent Digest")
    void Ck_GymCrowd_NarrowGap_Digest()
    {
        if (HasAuthority() == false)
        { return; }

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (ck::Is_NOT_Valid(_Agents[i])) { continue; }
            utils_crowd_agent_diag::EmitDigest_ForAgent(_Agents[i], 0, "NarrowGap", i);
        }
        ck::crowd::Log(f"NarrowGap gym: emitted digest for {_Agents.Num()} agents — grep [CrowdDiag]");
    }

    // ---- Agent factory ---------------------------------------------------------------------------

    private void SpawnWalkers(int32 InCount, int32 InColorIndexBase)
    {
        // Two staggered rows before the wall, spanning less than the wall span so the gap is every
        // walker's shortest route. Goals mirror each spawn across the wall line at the same Y.
        const auto SpawnX = WallLineOffset - ApproachOffset;
        const auto GoalX  = WallLineOffset + ApproachOffset;
        const auto PerRow = Math::IntegerDivisionTrunc(InCount + 1, 2);

        for (int32 i = 0; i < InCount; ++i)
        {
            const auto Row     = Math::IntegerDivisionTrunc(i, PerRow);
            const auto Slot    = i - (Row * PerRow);
            const auto RowX    = SpawnX - (float(Row) * 120.0);
            const auto SpanY   = float(PerRow - 1) * RowSpacingY;
            const auto SlotY   = (float(Slot) * RowSpacingY) - (SpanY * 0.5) + (float(Row) * (RowSpacingY * 0.5));

            const auto SpawnLoc = Local_To_World(FVector(RowX, SlotY, SpawnZ));
            const auto GoalLoc  = Local_To_World(FVector(GoalX, SlotY, SpawnZ));

            const auto HueDeg = (360.0 / float(InCount)) * float(InColorIndexBase + i);
            const auto Color = FLinearColor::MakeFromHSV8(uint8(HueDeg * 255.0 / 360.0), 200, 220);
            _Agents.Add(SpawnAgent(SpawnLoc, GoalLoc, Color, FName(f"NarrowGapWalker_{_Agents.Num()}"), true));
        }
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FVector InSpawnLoc, FVector InTargetLoc, FLinearColor InColor, FName InDebugName, bool InIssueMove)
    {
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        AgentEntity.Set_DebugName(InDebugName);

        const auto LookDir   = InTargetLoc - InSpawnLoc;
        const auto PlanarDir = FVector(LookDir.X, LookDir.Y, 0.0);
        const auto Rot       = PlanarDir.Size() < 1.0 ? FRotator::ZeroRotator : PlanarDir.GetSafeNormal().Rotation();

        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(Rot, InSpawnLoc, FVector::OneVector), ECk_Replication::DoesNotReplicate);
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
