// --------------------------------------------------------------------------------------------------------------------
// Crowd Narrow-Gap Gym - PlayerController
//
// See CkCrowdGym_NarrowGap_GameMode.as for the console surface and what to watch.
//
// Layout (station-local; +X is toward the player camera after the cycler's rotation):
//   - Wall line perpendicular to the approach at local X = WallLineOffset, split by a GapWidth
//     opening at local Y = 0. Wall boxes carve the navmesh (ACk_CrowdPathingGym_NavBox - nav-only,
//     player walks through).
//   - Walkers spawn in staggered rows before the wall; each goal is the mirrored point past
//     the wall at the same Y, so every route's shortest form crosses the gap.
//   - Optional flank caps extend the wall line past the floor edge so no detour exists.
//
// Two map constraints size everything below - both were learned from a PIE session where the
// default state had NO route at all (every path Partial, the whole crowd piled at the wall):
//   - The wall boxes are PHYSICAL rasterized obstacles, so Recast erodes the walkable surface
//     around them by the nav agent radius (~35cm per side). GapWidth is the PHYSICAL gap; the
//     navmesh corridor through it is ~70cm narrower, and under ~150cm physical the gap bakes
//     shut entirely. (The headless autotests carve with nav-area markup instead, which does not
//     erode - their 110cm figure does not transfer here.)
//   - The cycler map's NavMeshBoundsVolume is origin-centred and does not reach much past
//     ~1000cm, so every spawn, goal, and wall END (the SpawnBlocked detour route) must stay
//     inside that envelope or the detour silently doesn't exist.
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_NarrowGap_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _PcEntity;
    private FCk_Handle _StationHandle;
    private FVector _ProbeStart;
    private FVector _ProbeGoal;
    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private TArray<AActor> _FlankWalls;
    private bool _AutoSpawned = false;
    private bool _NavProbeFailed = false;

    private const float SpawnZ          = 100.0;
    private const float WallLineOffset  = 600.0;
    private const float GapWidth        = 170.0;    // physical; ~100cm on the navmesh after obstacle erosion
    private const float WallSpanY       = 600.0;    // each wall: from GapWidth/2 out to GapWidth/2 + WallSpanY
    private const float WallThickness   = 100.0;
    private const float WallHeight      = 200.0;
    private const float ApproachOffset  = 400.0;    // spawn/goal distance before/past the wall line
    private const float RowSpacingY     = 100.0;
    private const int32 SpawnRows       = 4;
    private const int32 DefaultCount    = 20;
    private const int32 AutoSpawnCount  = 20;
    private const float NavProbePollSec = 0.5;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.NarrowGap");
            Station.AutoSize = true;
            Station.Title = FText::FromString("CROWD NARROW GAP (170cm pinch)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("20 walkers auto-spawn and funnel through a 170cm gap (~100cm of navmesh) between nav walls."));
            Description.Add(FText::FromString("Expected: clean single-file traversal — no oscillation inside the pinch."));
            Description.Add(FText::FromString("B parks one agent IN the gap: walkers must detour around the wall ends."));
            Description.Add(FText::FromString("F CLOSED removes the detour: expect a calm hold / clean goal-failed, never a perpetual press."));
            Description.Add(FText::FromString("Panel: G walkers / B blocker+walkers / F flank caps / Z reset / J digest"));
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

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        // Auto-spawn gate: a probe path from the spawn side through the gap proves the bake
        // (including the wall carve) finished; a timer would race the async tile build.
        _ProbeStart = Local_To_World(FVector(WallLineOffset - ApproachOffset, 0.0, SpawnZ));
        _ProbeGoal  = Local_To_World(FVector(WallLineOffset + ApproachOffset, 0.0, SpawnZ));

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(NavProbePollSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(_PcEntity, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnNavProbePoll"));

        ck::crowd::Log(f"NarrowGap gym started - auto-spawning {AutoSpawnCount} walkers once the navmesh probe resolves.");
    }

    // Retried every NavProbePollSec until the surface answers Success: the rebuild kicked in
    // Request_StartGym is async, so the first few polls can legitimately read Unbuilt while the
    // bake finishes.
    UFUNCTION()
    private void OnNavProbePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_AutoSpawned || _Agents.Num() > 0 || _NavProbeFailed)
        { return; }

        auto ProbeQuery = FCk_NavSurface_PathQuery(_ProbeStart, _ProbeGoal);
        const auto Result = utils_nav_surface::Try_FindPathSync(ProbeQuery);

        if (Result.Get_Status() == ECk_NavSurface_QueryStatus::Unbuilt) { return; }

        if (Result.Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            _NavProbeFailed = true;
            ck::crowd::Log("NarrowGap gym: navmesh probe failed - auto-spawn skipped; press G on the control panel once the navmesh is visible.");
            return;
        }

        // A "Success" path to a goal the end-projection pulled back onto the near side looks
        // exactly like success - the one PIE symptom this gym ever shipped with. Require the path
        // to actually reach the far side before trusting the bake.
        auto Waypoints = Result.Get_Waypoints();
        if (Waypoints.Num() > 0)
        {
            auto EndDelta = Waypoints[Waypoints.Num() - 1] - _ProbeGoal;
            EndDelta.Z = 0.0;
            if (EndDelta.Size() > 200.0)
            {
                _NavProbeFailed = true;
                ck::crowd::Warning(f"NarrowGap gym: probe path stops {EndDelta.Size()}cm short of the far side - the gap failed to bake or the map's NavMeshBoundsVolume doesn't cover the layout. Auto-spawn skipped.");
                return;
            }
        }

        _AutoSpawned = true;
        Ck_GymCrowd_NarrowGap_Spawn(AutoSpawnCount);
    }

    // ---- Geometry ----------------------------------------------------------------------------------

    private FVector Local_To_World(FVector InLocalOffset)
    {
        const auto StationXform = Get_StationAnchorTransform("Gym.Crowd.NarrowGap", ECk_GymStation_Anchor::FootprintCenter);
        return StationXform.TransformPosition(InLocalOffset);
    }

    private void SpawnFloor()
    {
        // Z SCALE MUST BE >= 0.5 - thinner and the navmesh bake silently produces no tiles.
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

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // The flank row reports whether the walls actually EXIST rather than mirroring the last command
    // sent: the walls ARE the state, and a mirror would be a second answer to a question the world
    // already answers.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "CROWD: NARROW GAP";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Action(EKeys::G, "G", "Spawn 20 walkers"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Spawn blocker + 20 walkers"));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::F, "F", "Flank caps", _FlankWalls.Num() > 0, "CLOSED", "OPEN"));
        Rows.Add(CkGym_Control::Action(EKeys::Z, "Z", "Reset - destroy agents"));
        Rows.Add(CkGym_Control::Action(EKeys::J, "J", "Emit per-agent digest"));
        Rows.Add(CkGym_Control::Status("Another walker count", "Ck_GymCrowd_NarrowGap_Spawn <count>"));
        Rows.Add(CkGym_Control::Status("...with a blocker parked in the gap", "Ck_GymCrowd_NarrowGap_SpawnBlocked <count>"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Ck_GymCrowd_NarrowGap_Spawn(20); }
        else if (InRowIndex == 1) { Ck_GymCrowd_NarrowGap_SpawnBlocked(20); }
        else if (InRowIndex == 2) { Request_SetFlankCaps(_FlankWalls.Num() == 0); }
        else if (InRowIndex == 3) { Request_ResetAgents(); }
        else if (InRowIndex == 4) { Request_EmitDigest(); }
    }

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

    // Closed means no detour exists around the wall ends, so the gap is the only route.
    private void Request_SetFlankCaps(bool InClosed)
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        for (auto Wall : _FlankWalls)
        {
            if (Wall != nullptr) { Wall.DestroyActor(); }
        }
        _FlankWalls.Empty();

        if (InClosed)
        {
            // Extend the wall line past the floor's edge (floor half-size 3750) on both sides.
            const auto InnerY  = (GapWidth * 0.5) + WallSpanY;
            const auto FlankLen = 3900.0 - InnerY;
            const auto CentreY = InnerY + (FlankLen * 0.5);
            const auto Scale = FVector(WallThickness / 100.0, FlankLen / 100.0, WallHeight / 100.0);

            _FlankWalls.Add(SpawnWallBox(FVector(WallLineOffset, CentreY, WallHeight * 0.5), Scale));
            _FlankWalls.Add(SpawnWallBox(FVector(WallLineOffset, -CentreY, WallHeight * 0.5), Scale));
        }

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
        const auto FlankState = InClosed ? FString("CLOSED (no detour)") : FString("OPEN");
        ck::crowd::Log(f"NarrowGap gym: flank caps {FlankState} - navmesh rebuilding");
    }

    private void Request_ResetAgents()
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

    private void Request_EmitDigest()
    {
        if (HasAuthority() == false)
        { return; }

        for (int32 i = 0; i < _Agents.Num(); ++i)
        {
            if (ck::Is_NOT_Valid(_Agents[i])) { continue; }
            utils_crowd_agent_diag::EmitDigest_ForAgent(_Agents[i], 0, "NarrowGap", i);
        }
        ck::crowd::Log(f"NarrowGap gym: emitted digest for {_Agents.Num()} agents - grep [CrowdDiag]");
    }

    // ---- Agent factory ---------------------------------------------------------------------------

    private void SpawnWalkers(int32 InCount, int32 InColorIndexBase)
    {
        // Staggered rows before the wall, kept narrow (~+/-200 at 20 walkers) so the gap is every
        // walker's shortest route - a wide line puts the rim walkers closer to the wall ENDS than
        // to the gap and half the crowd legitimately detours instead of funnelling. Goals mirror
        // each spawn across the wall line at the same Y.
        const auto SpawnX = WallLineOffset - ApproachOffset;
        const auto GoalX  = WallLineOffset + ApproachOffset;
        const auto PerRow = Math::IntegerDivisionTrunc(InCount + SpawnRows - 1, SpawnRows);

        for (int32 i = 0; i < InCount; ++i)
        {
            const auto Row     = Math::IntegerDivisionTrunc(i, PerRow);
            const auto Slot    = i - (Row * PerRow);
            const auto RowX    = SpawnX - (float(Row) * 120.0);
            const auto SpanY   = float(PerRow - 1) * RowSpacingY;
            const auto SlotY   = (float(Slot) * RowSpacingY) - (SpanY * 0.5) + (float(Row % 2) * (RowSpacingY * 0.5));

            const auto SpawnLoc = Local_To_World(FVector(RowX, SlotY, SpawnZ));
            const auto GoalLoc  = Local_To_World(FVector(GoalX, SlotY, SpawnZ));

            const auto HueDeg = (360.0 / float(InCount)) * float(InColorIndexBase + i);
            const auto Color = FLinearColor::MakeFromHSV8(uint8(HueDeg * 255.0 / 360.0), 200, 220);
            _Agents.Add(SpawnAgent(SpawnLoc, GoalLoc, Color, FName(f"NarrowGapWalker_{_Agents.Num()}"), true));
        }
    }

    private FCk_NavSurface_ProjectionResult Do_ProjectOntoSurface(FVector InPoint, FVector InSearchHalfExtents) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(InSearchHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query);
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FVector InSpawnLoc, FVector InTargetLoc, FLinearColor InColor, FName InDebugName, bool InIssueMove)
    {
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        AgentEntity.Set_DebugName(InDebugName);

        // Grounding is displacement-driven (ConstrainToNavmesh only moves an agent that moves), so
        // a parked agent spawned above the floor hovers there forever. Snap every spawn to the mesh.
        auto GroundedSpawn = InSpawnLoc;
        const auto SpawnProjection = Do_ProjectOntoSurface(InSpawnLoc, FVector(200.0, 200.0, 300.0));
        if (SpawnProjection.Get_Status() == ECk_NavSurface_QueryStatus::Success)
        { GroundedSpawn = SpawnProjection.Get_Location(); }

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
