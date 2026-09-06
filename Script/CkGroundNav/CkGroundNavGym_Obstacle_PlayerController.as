class ACk_GroundNavGym_Obstacle_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- Where the scene stands ------------------------------------------------------------------
    //
    // Every dimension below is LOCAL to the scene: the station is placed by
    // Request_ApplyDefaultGridLayout, so a hardcoded world position is wrong the moment the grid
    // changes. Stations face world -X, and this offset clears the slab's own 1800uu half-width by 500.

    private const FVector k_SceneOffset = FVector(-2300.0, 0.0, 0.0);

    // The corridor: 3600 x 1400, top face at scene-local Z 0. The engine cube is 100uu, so the scale
    // is the dimension in hundreds; Z scale 2 stays past the 0.5 below which a slab bakes zero tiles.
    private const FVector k_SlabCentre = FVector(0.0, 0.0, -100.0);
    private const FVector k_SlabScale  = FVector(36.0, 14.0, 2.0);

    // ---- The box that drops in --------------------------------------------------------------------
    //
    // 400 x 400 x 400 on the corridor's midpoint - centre at Z 200 because the cube is centred on its
    // own origin. It straddles all three lanes, so every walker has to bend around it.

    private const FVector k_BoxCentre      = FVector(0.0, 0.0, 200.0);
    private const FVector k_BoxScale       = FVector(4.0, 4.0, 4.0);
    private const FVector k_BoxHalfExtents = FVector(200.0, 200.0, 200.0);

    // The ground a drop or a lift leaves untrustworthy: the box footprint grown by 100uu on every
    // side, so the repair opens clear of the body's own edge rather than exactly along it.
    private const FVector k_BoxDirtyMin = FVector(-300.0, -300.0, -100.0);
    private const FVector k_BoxDirtyMax = FVector(300.0, 300.0, 500.0);

    // Three lanes 150uu apart, west to east and back. The posts stop 300uu short of the slab's own
    // edge so nothing here is about the perimeter cliff. Z 100 is where a 180uu body's centre stands.
    private const int32   k_WalkerCount     = 3;
    // 150 and not 300: the box is 400 wide, so at 300 only the middle lane meets it and the outer
    // two walk past untouched. At 150 all three lanes lie inside its footprint and all three bend.
    private const float   k_LaneSpacingUu   = 150.0f;
    private const FVector k_WalkerWestPoint = FVector(-1500.0, 0.0, 100.0);
    private const FVector k_WalkerEastPoint = FVector(1500.0, 0.0, 100.0);

    // The volume: the slab and nothing else, with 200uu of margin on every side so the perimeter
    // cliff is inside the region rather than clipped by it.
    private const FVector k_VolumeMin = FVector(-2000.0, -900.0, -300.0);
    private const FVector k_VolumeMax = FVector(2000.0, 900.0, 500.0);

    // The same 25uu lattice every GroundNav gym bakes on, so the volumes are directly comparable. The
    // 800uu tiles are what a local repair is local WITH RESPECT TO. The agent is the default 34uu body
    // at 180uu standing height.
    private const float k_CellSizeUu        = 25.0f;
    private const float k_CellHeightUu      = 10.0f;
    private const float k_TileSizeUu        = 800.0f;
    private const float k_AgentRadiusUu     = 34.0f;
    private const float k_AgentHalfHeightUu = 90.0f;
    private const float k_WalkerHeightUu    = 180.0f;

    // 0.05s a poll, so this is thirty seconds of waiting on a NAMED condition before the gym gives up
    // and says so in the Verdict rather than hanging silently.
    private const int32 k_SettlePollCeiling = 600;

    // A repair is DEFERRED and the plates only change once the derive has republished, so the picture
    // is redrawn on a named condition - epoch moved, surface quiet - and not at the keypress. At 0.05s
    // a poll this ceiling is ten seconds, after which it redraws anyway.
    private const int32 k_OverlayPollCeiling = 200;

    // The picture. The extent is a HALF-extent and 1900 covers the slab's 3600x1400 top - about
    // twenty-three thousand columns on the 25uu lattice, inside the ceiling below. Only the REGION is
    // stated here: every filter the bake runs is pushed off the volume by Request_BakeDebugFieldAt,
    // so the picture and the field cannot describe different ground.
    private const FVector k_BakeCentre        = FVector(0.0, 0.0, 100.0);
    private const float   k_DebugBakeExtentUu = 1900.0f;
    private const float   k_DebugBakeHeightUu = 400.0f;
    private const int32   k_DebugBakeMaxCells = 40000;

    // Frames the whole corridor and the box's landing spot from the scene's south-east.
    private const FVector  k_ViewOffset   = FVector(2000.0, -1700.0, 1500.0);
    private const FRotator k_ViewRotation = FRotator(-33.0, 118.0, 0.0);

    // PLATES, because that is the mode a repair reads as anything in: reopened ground is a plate that
    // was not there before, and the box's own footprint is a plate that vanishes when it lands.
    private const int32 k_PlateDrawMode = 0;

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Layout: 0 "This shows", 1 Verdict, 2 Walkers (the three CkGroundNavDemo header rows), then
    // 3 the box, 4 auto-repair, and 5 the T picture row LAST. Nothing here is variable-length, so no
    // index can move between frames - which matters because the panel dispatches on the index.

    private const int32 k_Row_Box        = 3;
    private const int32 k_Row_AutoRepair = 4;
    private const int32 k_Row_DrawMode   = 5;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FVector _Origin = FVector::ZeroVector;
    private bool _GeometryIsBuilt = false;

    // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and the slab is a spawned actor
    // that nothing here holds a handle to - so a second pass would stack a second slab into the Jolt
    // static world, invisible to every row. Spawned once per controller.
    private bool _SceneSpawned = false;

    private FCkGroundNavGym_Field _Field;
    private FCkGroundNavGym_OverlayRefresh _OverlayRefresh;
    private FCkGroundNavDemo_WalkerSet _Walkers;

    private int32 _DrawModeIndex = k_PlateDrawMode;

    // The box is kept as an ACTOR because lifting it is a Jolt round trip - Request_RemoveActor takes
    // the actor, and so does DestroyActor. Whether one is down is read off this handle rather than off
    // a bool, so nothing can disagree with the world.
    private AStaticMeshActor _BoxActor = nullptr;

    // The posts the walkers patrol between, in WORLD space, kept so Tick can draw them with their
    // labels. Built when the walkers are spawned and never after.
    private TArray<FVector> _PostsWest;
    private TArray<FVector> _PostsEast;

    // Default ON: the gym's headline is that a local repair closes the hole a dropped body opens, and
    // key 4 is how a reader takes that away to see what it was doing.
    private bool _AutoRepair = true;

    // ---- This gym's own arithmetic about its own requests -------------------------------------------
    //
    // None of these mirrors engine state. _EpochAtRepair is a SNAPSHOT of a live readback taken at the
    // instant of the request - a measurement, not a copy of something the volume goes on holding.

    private int32 _ChangesRun = 0;        // drops plus lifts
    private int32 _RepairsAtChange = 0;   // repairs completed when the last change went in
    private int32 _RepairsRun = 0;
    private bool _RepairIsPending = false;
    private int64 _EpochAtRepair = 0;
    private ECk_Request_OperationResult _LastRepairResult = ECk_Request_OperationResult::Failed;

    // ---- Station ---------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // No Transform: the base grid places it, and the scene is built off the anchor it lands on.
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavObstacle");
        Station.AutoSize = true;
        Station.Title = FText::FromString("GroundNav - Dynamic Obstacle");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Three walkers patrol a corridor on lanes 300uu apart, over a field this gym bakes for itself."));
        Description.Add(FText::FromString("Press 3 to drop a 400uu box onto the middle of that corridor, and again to lift it out - the field repairs under it and the walkers re-route."));
        Description.Add(FText::FromString("Press 4 to turn the repair off: a drop then leaves the field stale and the walkers walk straight through the box. T cycles what the picture shows."));
        Station.Description = Description;

        Stations.Add(Station);

        return Stations;
    }

    // ---- Startup ---------------------------------------------------------------------------------

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _PcEntity = ck::ToEntity(this);

        if (ck::Is_NOT_Valid(_PcEntity))
        {
            ck::groundnav::Warning("GroundNav obstacle gym: PC entity invalid; cannot start");
            return;
        }

        _Origin = Get_StationAnchorLocation("GroundNavObstacle", ECk_GymStation_Anchor::FootprintCenter);

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav obstacle gym: the corridor failed to bake into the Jolt static world - the field has nothing to bake over", n"GroundNavGym.Scene", 10.0);
        }

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        DoArm_Field();

        ck::groundnav::Log("GroundNav obstacle gym: corridor built - the walkers are released once the field settles");
    }

    // Scene-local to world. Everything this gym spawns, bakes, repairs and walks goes through here, so
    // the scene is one translation away from the station the grid layout happened to place.
    private FVector Get_ScenePoint(FVector InLocal)
    {
        return _Origin + k_SceneOffset + InLocal;
    }

    private bool DoBuildScene()
    {
        // Guarded, not idempotent by luck: a restart keeps the corridor it already spawned, which is
        // also the corridor the volume was baked over.
        if (_SceneSpawned)
        { return true; }

        _SceneSpawned = true;

        return CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_SlabCentre), k_SlabScale);
    }

    private void DoBringPlayerToViewpoint()
    {
        CkGroundNavGym::Request_FlyToStation(this, "GroundNavObstacle",
            k_SceneOffset + k_ViewOffset, k_ViewRotation);
    }

    // Mirrors the gym base private WaitOneFrame - a one-shot timer on the PC's own entity.
    private void DoWaitOneFrame(FName InCallbackName)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);

        auto Timer = utils_timer::Add(_PcEntity, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }

    UFUNCTION()
    private void OnViewpointSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        // Retry - the pawn may not have been possessed yet when the gym started.
        DoBringPlayerToViewpoint();
    }

    // ---- The field --------------------------------------------------------------------------------

    private void DoArm_Field()
    {
        if (_GeometryIsBuilt == false)
        {
            _Field.Set_Stage("the corridor is not in the Jolt static world - nothing to bake over");
            return;
        }

        // A restart re-runs Request_StartGym on the same controller and a field is minted ONCE, so the
        // mint below is turned away and no settle poll ever fires again. The retained draw is
        // command-driven, so the picture is owed here instead.
        if (_Field.Get_IsBuilt())
        {
            DoRefresh_Picture();
            return;
        }

        auto Config = FCk_GroundNav_BakeConfig(k_CellSizeUu, k_CellHeightUu);
        Config.Set_TileSizeUu(k_TileSizeUu);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(k_AgentHalfHeightUu, k_AgentRadiusUu)));

        // The slab ENDS inside the volume, so at the default sensitivity the ledge filter would demote
        // its whole perimeter - and the lanes run out towards that edge, so bodies released on them
        // would be standing on ground the filter had thrown away.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(Get_ScenePoint(k_VolumeMin), Get_ScenePoint(k_VolumeMax));

        _Field.Request_Mint(_PcEntity, n"GroundNavGym_ObstacleField", Bounds, Config, Profile,
            NAME_None, k_SettlePollCeiling,
            FCk_Delegate_Request_OnCompleted(this, n"OnFieldBuildCompleted"),
            FCk_Delegate_Timer(this, n"OnFieldSettlePoll"));
    }

    UFUNCTION()
    private void OnFieldBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Field.Notify_BuildCompleted(InResult);
    }

    // The one named condition worth waiting on after a bake: nothing in flight and nothing pending, so
    // the field the volume publishes is the one every route answers from.
    UFUNCTION()
    private void OnFieldSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Step = _Field.Do_PollSettle();

        if (Step == ECkGroundNavGym_Settle::Settled)
        {
            DoRefresh_Picture();

            if (_Walkers.Get_Count() == 0)
            { DoSpawn_Walkers(); }

            return;
        }

        if (Step == ECkGroundNavGym_Settle::GaveUp)
        {
            _Field.Set_Stage("the surface never settled - the walkers have nothing to stand on");
            ck::groundnav::Log("GroundNav obstacle gym: the field never settled - no walkers were released");
        }
    }

    // The DEBUG bake, which is a picture and belongs to no volume - but it reads the same Jolt static
    // world the volume bakes from, which is the whole point of this gym: with the repair off, the
    // picture shows the box and the PUBLISHED field the walkers route through does not.
    private void DoRefresh_Picture()
    {
        CkGroundNavGym::Request_BakeDebugFieldAt(_Field, Get_ScenePoint(k_BakeCentre),
            k_DebugBakeExtentUu, k_DebugBakeHeightUu, k_DebugBakeMaxCells, _DrawModeIndex);
    }

    private void DoArm_OverlayRefresh()
    {
        _OverlayRefresh.Request_Arm(_PcEntity, _Field, k_OverlayPollCeiling,
            FCk_Delegate_Timer(this, n"OnOverlayRefreshPoll"));
    }

    UFUNCTION()
    private void OnOverlayRefreshPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_OverlayRefresh.Do_Poll(_Field) == false)
        { return; }

        DoRefresh_Picture();

        // HERE and nowhere earlier: a route is worth re-planning at the moment the field the planner
        // reads has actually changed, and at no other.
        _Walkers.Request_ReplanAll();
    }

    // ---- The walkers -------------------------------------------------------------------------------

    private void DoSpawn_Walkers()
    {
        _PostsWest.Empty();
        _PostsEast.Empty();

        for (int32 Index = 0; Index < k_WalkerCount; Index++)
        {
            // Lanes centred on the corridor, so the middle one runs straight through the box's landing
            // spot and its neighbours pass just clear of the footprint's edge.
            const auto LaneY = (float(Index) - (float(k_WalkerCount - 1) * 0.5f)) * k_LaneSpacingUu;

            // Declared locals of the concrete type rather than `auto`: `auto` preserves const, and
            // Request_Add takes its posts BY VALUE.
            FVector West = Get_ScenePoint(k_WalkerWestPoint + FVector(0.0, LaneY, 0.0));
            FVector East = Get_ScenePoint(k_WalkerEastPoint + FVector(0.0, LaneY, 0.0));

            if (_Walkers.Request_Add(_PcEntity, FName(f"GroundNavGym_ObstacleWalker{Index}"),
                    West, East, k_AgentRadiusUu, k_WalkerHeightUu,
                    CkGroundNavDemo::Get_WalkerColor(Index),
                    FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerGoalReached"),
                    FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerGoalFailed")) == false)
            { continue; }

            _PostsWest.Add(West);
            _PostsEast.Add(East);
        }
    }

    UFUNCTION()
    private void OnWalkerGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        _Walkers.Notify_GoalReached(InAgent);
    }

    UFUNCTION()
    private void OnWalkerGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        _Walkers.Notify_GoalFailed(InAgent);
    }

    // ---- The box -----------------------------------------------------------------------------------

    private void DoToggle_Box()
    {
        if (ck::IsValid(_BoxActor))
        {
            DoLift_Box();
            return;
        }

        DoDrop_Box();
    }

    // Spawn_BoxActor bakes the body into the Jolt static world on its way out, which is what makes the
    // published field stale: a GroundNav bake reads that world and nothing else.
    private void DoDrop_Box()
    {
        auto BoxActor = CkGroundNavGym::Spawn_BoxActor(this,
            Get_ScenePoint(k_BoxCentre), FRotator::ZeroRotator, k_BoxScale);

        if (BoxActor == nullptr)
        {
            ck::groundnav::Warning("GroundNav obstacle gym: the box could not be dropped - nothing was added to the Jolt static world");
            return;
        }

        _BoxActor = BoxActor;

        DoNotify_GroundChanged();

        ck::groundnav::Log("GroundNav obstacle gym: the box is down on the corridor - the ground under it is stale until a repair opens over it");
    }

    // OUT of the static world before the actor goes, and in that order: the static world holds its own
    // copy of the shape, so a body destroyed without the removal leaves its collision standing as far
    // as every bake is concerned.
    private void DoLift_Box()
    {
        if (ck::Is_NOT_Valid(_BoxActor))
        { return; }

        utils_jolt_static_world::Request_RemoveActor(_BoxActor);

        _BoxActor.DestroyActor();
        _BoxActor = nullptr;

        DoNotify_GroundChanged();

        ck::groundnav::Log("GroundNav obstacle gym: the box is lifted out - the field still carries the ground it stood on until a repair opens over it");
    }

    // What every drop and every lift owes. The picture is redrawn IMMEDIATELY - the Jolt round trip is
    // synchronous, so a debug bake this frame already reads the corridor as it now stands, while the
    // published field the walkers route through does not. That disagreement IS the staleness, and with
    // auto-repair off it is what the reader is here to see.
    private void DoNotify_GroundChanged()
    {
        _ChangesRun += 1;
        _RepairsAtChange = _RepairsRun;

        DoRefresh_Picture();

        if (_AutoRepair == false)
        { return; }

        DoRepair_BoxGround();
    }

    private void DoRepair_BoxGround()
    {
        // A declared local rather than the call inline: Request_Repair takes the volume BY VALUE, and
        // a const value cannot be handed to a by-value parameter.
        FCk_Handle_GroundNavVolume Volume = _Field.Get_Volume();

        if (ck::Is_NOT_Valid(Volume))
        { return; }

        const auto DirtyBounds = FBox(Get_ScenePoint(k_BoxDirtyMin), Get_ScenePoint(k_BoxDirtyMax));

        // Read IMMEDIATELY before the request, so the number the verdict compares against is the epoch
        // the field was standing at when this repair was asked for - a measurement taken at the instant
        // of the action, not a copy of something the volume goes on holding.
        _EpochAtRepair = utils_ground_nav_volume::Get_BuildEpoch(Volume);
        _RepairIsPending = true;

        utils_ground_nav_volume::Request_Repair(Volume,
            FCk_Request_GroundNavVolume_Repair(DirtyBounds),
            FCk_Delegate_Request_OnCompleted(this, n"OnRepairCompleted"));
    }

    UFUNCTION()
    private void OnRepairCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RepairsRun += 1;
        _LastRepairResult = InResult;
        _RepairIsPending = false;

        // The repair reopened ground, and reopened ground is a plate that was not there before - which
        // is invisible until the derive republishes and the picture is re-run over it.
        DoArm_OverlayRefresh();
    }

    // Auto-repair is flipped and nothing else happens: the reader who turned it back on is told to
    // press 3, so the next drop or lift is the one that shows the repair running.
    private void DoToggle_AutoRepair()
    {
        _AutoRepair = _AutoRepair == false;

        ck::groundnav::Log(f"GroundNav obstacle gym: auto-repair is now {_AutoRepair} - press 3 to drop or lift the box and watch what the field does");
    }

    // Whether the published field still describes ground that has moved. This gym's own arithmetic and
    // not a mirror of the volume's: a refused repair leaves the corridor exactly as stale as it was,
    // and the footprint must go on saying so.
    private bool Get_FieldIsStale()
    {
        if (_ChangesRun == 0)
        { return false; }

        if (_RepairIsPending)
        { return true; }

        if (_RepairsRun <= _RepairsAtChange)
        { return true; }

        return _LastRepairResult != ECk_Request_OperationResult::Succeeded;
    }

    // ---- Per-frame drawing ---------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        _Walkers.Do_Tick();

        for (int32 Index = 0; Index < _PostsWest.Num(); Index++)
        {
            CkGroundNavDemo::Draw_GoalPost(_PostsWest[Index], f"W{Index}", CkGroundNavDemo::Get_WalkerColor(Index));
            CkGroundNavDemo::Draw_GoalPost(_PostsEast[Index], f"E{Index}", CkGroundNavDemo::Get_WalkerColor(Index));
        }

        CkGroundNavDemo::Draw_WorldCaption(Get_ScenePoint(FVector(0.0, 0.0, 700.0)), Get_Caption());

        DoDraw_BoxFootprint();
    }

    // The footprint the repair is aimed at, drawn where the box stands: RED while the published field
    // still carries the ground the box is sitting on, GREEN once a repair has opened over it. Zero
    // duration, so a Clear cannot take it and it can never lag the state it describes.
    private void DoDraw_BoxFootprint()
    {
        if (ck::Is_NOT_Valid(_BoxActor))
        { return; }

        // Declared non-const locals: DrawDebugBox takes its extent, colour and rotation BY VALUE.
        FVector Centre = Get_ScenePoint(k_BoxCentre);
        FVector Extent = k_BoxHalfExtents;
        FRotator Rotation = FRotator::ZeroRotator;

        FLinearColor Color = FLinearColor(0.20, 1.00, 0.35, 1.0);
        FString Label = "box down - the field has been repaired under it";

        if (Get_FieldIsStale())
        {
            Color = FLinearColor(1.00, 0.20, 0.20, 1.0);
            Label = "box down - the field under it is STALE";
        }

        utils_debug_draw::DrawDebugBox(Centre, Extent, Color, Rotation, 0.0f, 6.0f);
        utils_debug_draw::DrawDebugString(Centre + FVector(0.0, 0.0, 260.0), Label, Color, 0.0f);
    }

    // ---- The verdict ---------------------------------------------------------------------------------
    //
    // The claim is about LOCALITY: a repair over the box footprint republishes the field, and the epoch
    // on either side of THAT request is the only thing that can honestly be checked against it.
    // _EpochAtRepair is snapshotted at the request and the epoch is read live here.

    private TArray<FString> Get_VerdictFailures()
    {
        auto Failures = TArray<FString>();

        const auto Failed = _Walkers.Get_FailedCount();

        if (Failed > 0)
        { Failures.Add(f"{Failed} of {_Walkers.Get_Count()} walkers have no route and are holding"); }

        if (_RepairsRun == 0 || _RepairIsPending)
        { return Failures; }

        if (_LastRepairResult != ECk_Request_OperationResult::Succeeded)
        {
            Failures.Add(f"the last repair answered {_LastRepairResult} - the corridor is still stale");
            return Failures;
        }

        const auto EpochNow = utils_ground_nav_volume::Get_BuildEpoch(_Field.Get_Volume());

        if (EpochNow <= _EpochAtRepair)
        { Failures.Add(f"a repair completed but the epoch never moved off {_EpochAtRepair} - nothing republished"); }

        return Failures;
    }

    // Gated on the same two things Get_VerdictLine gates on, so the row cannot go red while it is
    // reading a pending line.
    private bool Get_VerdictIsFailing()
    {
        if (_Field.Get_IsBuilt() == false)
        { return false; }

        if (_Walkers.Get_AnyHasWalked() == false)
        { return false; }

        return Get_VerdictFailures().Num() > 0;
    }

    private FString Get_VerdictLine()
    {
        if (_Field.Get_IsBuilt() == false || _Walkers.Get_AnyHasWalked() == false)
        { return CkGroundNavDemo::Get_VerdictPendingText(_Field); }

        const auto Failures = Get_VerdictFailures();

        if (Failures.Num() > 0)
        { return CkGroundNavGym::Get_VerdictText("", Failures); }

        // A repair in flight, or a redraw still owed: the field is moving, and a body cannot have a
        // route worth judging until it has stopped.
        if (_RepairIsPending || _OverlayRefresh.Get_IsWaiting())
        { return "repairing - the field is republishing, verdict pending"; }

        const auto Count = _Walkers.Get_Count();

        if (_Walkers.Get_AllHaveWalked() == false)
        { return f"walkers starting - {_Walkers.Get_WalkingCount()} of {Count} moving, verdict pending"; }

        const auto Stale = Get_FieldIsStale();

        if (ck::IsValid(_BoxActor))
        {
            if (Stale)
            { return "OK - box down, field STALE by choice - walkers cross it; press 4 then 3"; }

            const auto Delta = utils_ground_nav_volume::Get_BuildEpoch(_Field.Get_Volume()) - _EpochAtRepair;

            return f"OK - box down, repaired (epoch +{Delta}), {Count} walkers re-routed";
        }

        if (Stale)
        { return "OK - box lifted, field STALE by choice - its old footprint is still blocked; press 4 then 3"; }

        if (_ChangesRun > 0)
        { return f"OK - box lifted, repaired, {Count} walkers back on the straight route"; }

        return f"OK - clear corridor, {Count} walkers crossing";
    }

    // ---- Control panel ---------------------------------------------------------------------------

    private FString Get_Caption()
    {
        return "A box drops into the corridor - the field repairs under it and the walkers re-route";
    }

    FString Get_ControlPanelTitle() override
    {
        return "GROUNDNAV: DYNAMIC OBSTACLE";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        auto Header = CkGroundNavDemo::Get_HeaderRows(Get_Caption(), Get_VerdictLine(),
            Get_VerdictIsFailing(), _Walkers.Get_StatusText());

        for (int32 Index = 0; Index < Header.Num(); Index++)
        { Rows.Add(Header[Index]); }

        Rows.Add(CkGym_Control::ToggleNamed(EKeys::Three, "3",
            "The box (a 400uu cube on the corridor's middle - it bakes into Jolt, which is the only world a GroundNav bake reads)",
            ck::IsValid(_BoxActor), "down on the corridor", "lifted out"));

        Rows.Add(CkGym_Control::ToggleNamed(EKeys::Four, "4",
            "Auto-repair (a local repair over the box footprint after every drop and every lift)",
            _AutoRepair, "on - the field follows the box", "off - a drop leaves the field STALE"));

        Rows.Add(CkGroundNavDemo::Get_DrawModeRow(_DrawModeIndex));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (HasAuthority() == false)
        { return; }

        if (InRowIndex == k_Row_Box)
        {
            DoToggle_Box();
            return;
        }

        if (InRowIndex == k_Row_AutoRepair)
        {
            DoToggle_AutoRepair();
            return;
        }

        if (InRowIndex == k_Row_DrawMode)
        {
            _DrawModeIndex = (_DrawModeIndex + 1) % CkGroundNavGym::Get_DrawModeCount();

            if (_Field.Get_IsBuilt() == false)
            { return; }

            DoRefresh_Picture();
        }
    }
}
