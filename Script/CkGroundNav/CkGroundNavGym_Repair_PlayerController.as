class ACk_GroundNavGym_Repair_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- Where the scene stands ------------------------------------------------------------------
    //
    // Every dimension below is LOCAL to the scene, and the scene is placed off the station's own
    // footprint anchor rather than at a world constant: the station is placed by
    // Request_ApplyDefaultGridLayout, so a hardcoded world position is wrong the moment the grid
    // changes. Stations face world -X, so the scene is pushed into -X in front of the board.
    //
    // The offset clears the slab's own half-width (1600uu) by 500uu, so the board never stands on the
    // ground the volume is baking.

    private const FVector k_SceneOffset = FVector(-2100.0, 0.0, 0.0);

    // ---- The slab ---------------------------------------------------------------------------------
    //
    // Top face at Z 0, so the scene's local Z 0 is the ground everything here stands on. The X scale
    // is the old range slab's unchanged - it is what puts 2800uu of corridor under the walkers. The Y
    // scale is 16 rather than the old 24 because three of the old range's five bands (the ramp, the
    // multi-tile crossing and the no-route pocket) are the Routing gym's, and a slab with nothing on
    // two thirds of it would put tiles in this volume that no control here can reach.

    private const FVector k_SlabCentre = FVector(0.0, 0.0, -100.0);
    private const FVector k_SlabScale  = FVector(32.0, 16.0, 2.0);

    // ---- The moved obstacle -----------------------------------------------------------------------
    //
    // 400uu square, 300uu tall, standing on the slab; the nudge row swaps it between the two
    // positions, which are one 800uu tile apart.

    private const FVector k_ObstacleHomeCentre  = FVector(-400.0, 300.0, 150.0);
    private const FVector k_ObstacleMovedCentre = FVector(400.0, 300.0, 150.0);
    private const FVector k_ObstacleScale       = FVector(4.0, 4.0, 3.0);

    // The ground a nudge leaves untrustworthy: the UNION of both footprints, grown by 100uu on every
    // side so the repair opens clear of the body's own edge rather than exactly along it.
    private const FVector k_ObstacleDirtyMin = FVector(-700.0, 0.0, -100.0);
    private const FVector k_ObstacleDirtyMax = FVector(700.0, 600.0, 400.0);

    // ---- The painted markup, which is also the walkers' corridor ------------------------------------
    //
    // The paint lands across the middle of the route the walkers are already on, so what it does to
    // them is visible without having to go and look for it.

    private const FVector k_MarkupCentre      = FVector(0.0, -300.0, 100.0);
    private const FVector k_MarkupHalfExtents = FVector(250.0, 250.0, 200.0);

    private const FVector k_WalkerWestPoint = FVector(-1400.0, -300.0, 100.0);
    private const FVector k_WalkerEastPoint = FVector(1400.0, -300.0, 100.0);
    private const float   k_WalkerRadiusUu  = 34.0f;
    private const float   k_WalkerHeightUu  = 180.0f;

    // Spread across the corridor rather than stacked on one point: eight bodies born inside each other
    // spend their first seconds pushing apart, which is avoidance and says nothing about routing.
    private const float k_WalkerSpacingUu = 90.0f;

    // What the crowd row offers. Zero is a state worth having: it is how the corridor reads with
    // nothing standing on it.
    private const int32 k_WalkerCountLow  = 1;
    private const int32 k_WalkerCountHigh = 8;

    // ---- The volume --------------------------------------------------------------------------------
    //
    // The slab and nothing else, with 200uu of margin on every side so the perimeter cliff is inside
    // the region rather than clipped by it.

    private const FVector k_VolumeMin = FVector(-1800.0, -1000.0, -300.0);
    private const FVector k_VolumeMax = FVector(1800.0, 1000.0, 500.0);

    // The same 25uu lattice the other GroundNav gyms bake on, so the volumes are directly comparable.
    // The 800uu tiles are what make "the obstacle moved one tile" a true sentence, and they are what a
    // local repair is local WITH RESPECT TO. The agent is the default 34uu body at 180uu standing
    // height.
    private const float k_CellSizeUu        = 25.0f;
    private const float k_CellHeightUu      = 10.0f;
    private const float k_TileSizeUu        = 800.0f;
    private const float k_AgentRadiusUu     = 34.0f;
    private const float k_AgentHalfHeightUu = 90.0f;

    // 0.05s a poll, so this is a minute of waiting on a NAMED condition before the gym gives up and
    // says so in its own status row rather than hanging silently. A minute rather than the links deck's
    // thirty seconds because this slab carries several times the tiles.
    private const int32 k_SettlePollCeiling = 1200;

    // Frames the obstacle band and the corridor from the scene's south-east.
    private const FVector  k_ViewOffset   = FVector(1900.0, -1600.0, 1400.0);
    private const FRotator k_ViewRotation = FRotator(-33.0, 118.0, 0.0);

    // The draw state this gym is worth looking at in, pushed once the field publishes.
    //
    // Mode 0 - PLATES - is the mode the old range opened in, and it is the only one in which a repair
    // reads as anything: a repair reopens ground, and reopened ground is a plate that was not there
    // before. DrawMarkup already defaults to 1, but it is pushed anyway so a session that turned it off
    // in another gym does not leave the paint row describing something invisible.
    private const int32 k_PlateDrawMode = 0;

    // ---- The debug bake the gym runs for the reader --------------------------------------------------
    //
    // A draw MODE is not a draw: nothing in the retained layer redraws on its own, so plates appear
    // only once ck.GroundNav.BakeFieldAt has run. It is run here, aimed at the middle of the slab's
    // walkable surface, so a repair reads as what it is - reopened ground is a plate that was not
    // there before, and there is nothing to compare against without a picture.
    //
    // The extent is a half-extent and 1800 covers the slab's 3200x1600 top; on the debug bake's 25uu
    // lattice that is about twenty thousand columns, which is why the cell ceiling is pushed past its
    // own default of twenty thousand. The height is centred 100uu over the top face, so the picture
    // reaches from under the slab to over the obstacle's 300uu head.
    //
    // Only the REGION is stated here. Every filter the bake runs - the lattice, the agent capsule, the
    // slope limits, the ledge sensitivity this slab needs pinned off because it ends inside the region -
    // is pushed from the volume by Request_BakeDebugFieldAt, so the picture and the rows above it
    // cannot end up describing different fields.
    private const FVector k_SlabBakeCentre = FVector(0.0, 0.0, 100.0);
    private const float k_DebugBakeExtentUu = 1800.0f;
    private const float k_DebugBakeHeightUu = 400.0f;
    private const int32 k_DebugBakeMaxCells = 40000;

    // The plate picture is redrawn a publish AFTER whatever made the field stale, not at the keypress:
    // a paint, a nudge and a repair are all deferred, and a bake run at the press draws the field the
    // press is about to change. At 0.05s a poll this ceiling is ten seconds, after which it redraws
    // anyway so a request the derive never answered still leaves a truthful picture.
    private const int32 k_DrawRefreshPollCeiling = 200;

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Header and Status rows never reach Request_ControlActivated but they DO occupy an index. These
    // constants sit next to each other so a row inserted in one place and not renumbered here is a
    // visible edit rather than a silent off-by-one. There is no variable-length block in this panel,
    // so nothing below these can move.

    private const int32 k_Row_Provider      = 6;
    private const int32 k_Row_PaintMarkup   = 7;
    private const int32 k_Row_NudgeObstacle = 8;
    private const int32 k_Row_Repair        = 10;
    private const int32 k_Row_Walkers       = 11;
    private const int32 k_Row_PathDraw      = 13;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FVector _Origin = FVector::ZeroVector;
    private bool _GeometryIsBuilt = false;

    private FCkGroundNavGym_Field _Field;

    // The one scene box kept as an actor: the nudge row moves this body and re-bakes it, which is the
    // only way ground in this scene goes stale in the first place. WHERE it is standing is read off the
    // actor, so no member says which of the two positions it is at.
    private AStaticMeshActor _ObstacleActor = nullptr;

    // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and the slab is a spawned actor
    // that nothing here holds a handle to - so a second pass would stack a second slab into the Jolt
    // static world on top of the first, invisible to every row. Spawned once per controller.
    private bool _SceneSpawned = false;

    // The paint's lifetime IS this handle - releasing the paint is destroying the markup entity - so
    // whether the corridor is painted is read off the handle rather than off a bool.
    private FCk_Handle_NavSurfaceMarkup _Markup;

    // ---- The gym's own arithmetic about its own requests --------------------------------------------
    //
    // None of these mirrors engine state. They count what THIS panel asked for, and the two Epoch
    // members are SNAPSHOTS of a live readback taken at the instant of an action - a measurement, not a
    // copy of something the volume goes on holding.

    private int32 _NudgesRun = 0;

    // The volume's build epoch as it was the instant BEFORE the repair was asked for, and the verdict's
    // whole claim about locality is the difference between this and the epoch read now.
    //
    // Snapshotted at the REPAIR and not at the nudge, which is a narrower window on purpose: between
    // the two keypresses the field can be republished by anything else this panel offers - the paint,
    // a provider swap, a derive the nudge itself provoked - and every one of those would land the epoch
    // somewhere other than nudge-plus-one and be reported as a repair that was not local. What "a local
    // repair is one publish" can honestly be checked against is the epoch on either side of THE REPAIR.
    private int64 _EpochAtRepair = 0;

    // How many repairs had completed when the nudge was pressed, so "a repair has run SINCE the nudge"
    // is a comparison rather than a flag that a second nudge would leave lying.
    private int32 _RepairsAtNudge = 0;

    private int32 _RepairsRun = 0;
    private ECk_Request_OperationResult _LastRepairResult = ECk_Request_OperationResult::Failed;

    // The epoch as it was when the paint was applied, for the same reason.
    private int64 _EpochAtPaint = 0;

    private TArray<FCk_Handle> _WalkerEntities;
    private TArray<FCk_Handle_CrowdAgent> _Walkers;

    // One flag per walker, parallel to _Walkers: whether a live readback of that agent has EVER said
    // Walking. It is a snapshot of a readback and not a mirror of one - the movement state says what an
    // agent is doing now, and nothing in ECk_CrowdAgent_MovementState says whether it has ever started.
    //
    // The verdict needs the difference. A body spawned this frame reads Idle until the crowd has given
    // it a corridor, which is pending and not a fault; a body that WAS walking and now reads Idle has
    // stopped having anywhere to go, which is the failure this gym is looking for. Same shape as the
    // Routing gym's Get_ProbeHasAnswered, kept per body because each one starts on its own schedule.
    private TArray<bool> _WalkerHasWalked;

    // What was ASKED for. The live count is _Walkers.Num(), and the verdict compares the two rather
    // than trusting either alone.
    private int32 _WalkerCountIndex = 0;

    // Nothing outside this gym holds this. ck.GroundNav.PathAt is a COMMAND, not a cvar, so there is
    // no console state saying whether a route is on screen - only this controller's own record of
    // having asked for one, and of the Clear that is the single thing which takes it down.
    private bool _PathDrawEnabled = false;

    // The deferred picture refresh every stale-making control here arms. See k_DrawRefreshPollCeiling.
    private FCkGroundNavGym_OverlayRefresh _DrawRefresh;

    // ---- Station ---------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // No Transform: the base grid places it, and the scene is built off the anchor it lands on.
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavRepair");
        Station.AutoSize = true;
        Station.Title = FText::FromString("GroundNav - Repair and Markup");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("One slab, one volume, and the three things that make a published field stale: a body that moved, a paint dropped on the ground, and a backend swapped out from under both. Everything here is asked OF the volume this gym mints - a repair and a paint are requests, and the debug bake is a picture that no volume holds and no request can be aimed at."));
        Description.Add(FText::FromString("A 400uu box stands on the north band. Press 3 and it jumps one 800uu tile east, out of the Jolt static world and back into it at the new place - which is the only way the published field goes stale. Nothing repairs it for you: the OBSTACLE row turns amber and says the ground the body LEFT is still blocked."));
        Description.Add(FText::FromString("Press 4 and the repair opens over the UNION of both footprints, which is the only box that reopens the old half and closes the new one in one pass. A repair aimed only at where the body arrived would leave its old footprint blocked for the rest of the field's life, because nothing else will ever revisit that ground."));
        Description.Add(FText::FromString("Press 2 to drop a 500uu impassable box across the south band and again to release it. The request is the provider-NEUTRAL one, the same call the crowd goes through: it names a shape and a place and nothing about which backend answers it, so one keypress carves Recast and GroundNav alike. The row reads the markup handle back, so it reports the paint the surface holds rather than the one this panel last asked for."));
        Description.Add(FText::FromString("Press 5 first to put crowd walkers on that same band. They cross it end to end and turn round, so a paint dropped in front of them is answered by a replan you can watch rather than by a number. Press 6 to draw that corridor as a route - it bakes a debug field over the slab first, because ck.GroundNav.PathAt reads the DEBUG field and not the volume's published one, and turning it off puts the plate view back."));
        Description.Add(FText::FromString("Press 1 to swap the world's nav provider. It is a per-WORLD choice: the volume stays baked either way, but on Recast nothing routes through it and the VERDICT row says so first, before anything else it could say."));
        Description.Add(FText::FromString("The VERDICT row at the top is the whole station in one line, and every criterion in it is read live: the provider off the facade, the epoch off the volume, the paint off the markup handle, and each walker's movement state off its own agent."));
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
            ck::groundnav::Warning("GroundNav repair gym: PC entity invalid; cannot start");
            return;
        }

        _Origin = Get_StationAnchorLocation("GroundNavRepair", ECk_GymStation_Anchor::FootprintCenter);

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav repair gym: the scene failed to bake into the Jolt static world - the field has nothing to bake over", n"GroundNavGym.Scene", 10.0);
        }

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        DoArm_Field();

        ck::groundnav::Log("GroundNav repair gym: scene built - the obstacle, the paint and the walkers are live once the field settles");
    }

    // Scene-local to world. Everything the gym spawns, bakes, paints and walks goes through here, so
    // the scene is one translation away from the station the grid layout happened to place.
    private FVector Get_ScenePoint(FVector InLocal)
    {
        return _Origin + k_SceneOffset + InLocal;
    }

    // ---- The volume ------------------------------------------------------------------------------

    private void DoArm_Field()
    {
        if (_GeometryIsBuilt == false)
        {
            _Field.Set_Stage("the scene is not in the Jolt static world - nothing to bake over");
            return;
        }

        auto Config = FCk_GroundNav_BakeConfig(k_CellSizeUu, k_CellHeightUu);
        Config.Set_TileSizeUu(k_TileSizeUu);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(k_AgentHalfHeightUu, k_AgentRadiusUu)));

        // The slab ENDS inside the volume, so at the default sensitivity the ledge filter would demote
        // its whole perimeter - and the walkers' corridor runs 1400uu out towards that edge, so bodies
        // released on it would be standing on ground the filter had thrown away.
        //
        // The slope limit is deliberately left at the profile default of 45 degrees. Nothing in this
        // gym is pitched, so moving it would change what the field says without changing what any
        // control here does.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(Get_ScenePoint(k_VolumeMin), Get_ScenePoint(k_VolumeMax));

        _Field.Request_Mint(_PcEntity, n"GroundNavGym_RepairField", Bounds, Config, Profile,
            NAME_None, k_SettlePollCeiling,
            FCk_Delegate_Request_OnCompleted(this, n"OnFieldBuildCompleted"),
            FCk_Delegate_Timer(this, n"OnFieldSettlePoll"));
    }

    // The one named condition worth waiting on after a bake: nothing in flight and nothing pending, so
    // the field the volume publishes is the one every query answers from. A fixed number of hops would
    // bake a guess about the probe budget into the gym.
    UFUNCTION()
    private void OnFieldSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Step = _Field.Do_PollSettle();

        if (Step == ECkGroundNavGym_Settle::Settled)
        {
            DoApply_DrawState();
            return;
        }

        if (Step == ECkGroundNavGym_Settle::GaveUp)
        {
            _Field.Set_Stage("the surface never settled - nothing here answers yet");
            ck::groundnav::Log("GroundNav repair gym: the field never settled - the obstacle, the paint and the walkers have nothing to stand on");
        }
    }

    UFUNCTION()
    private void OnFieldBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Field.Notify_BuildCompleted(InResult);
    }

    // Applied only once the field publishes: before that there is nothing under the plates to draw,
    // and a mode pushed at startup would be describing an empty picture.
    private void DoApply_DrawState()
    {
        System::ExecuteConsoleCommand("ck.GroundNav.Debug.DrawMarkup 1");

        DoRefresh_Draw();
    }

    // The bake that makes the plates exist, plus the route over them when one is asked for. A draw mode
    // selects what a bake draws and nothing redraws on its own, so this is the only thing that puts a
    // picture on screen: at startup, and again a publish after everything on this panel that makes the
    // field stale.
    //
    // A re-bake replaces the FIELD group and leaves the QUERY group standing, so the route has to be
    // re-asked here rather than surviving on its own - the line drawn by the previous PathAt describes
    // the field as it was before this bake.
    //
    // It is a DEBUG bake and belongs to no volume: the rows above read the volume's own published
    // field, and the two agree because Request_BakeDebugFieldAt pushes the volume's own tunables.
    private void DoRefresh_Draw()
    {
        CkGroundNavGym::Request_BakeDebugFieldAt(_Field, Get_ScenePoint(k_SlabBakeCentre),
            k_DebugBakeExtentUu, k_DebugBakeHeightUu, k_DebugBakeMaxCells, k_PlateDrawMode);

        if (_PathDrawEnabled == false)
        { return; }

        CkGroundNavGym::Request_DrawPathAt(
            Get_ScenePoint(k_WalkerWestPoint), Get_ScenePoint(k_WalkerEastPoint));
    }

    // Armed by every control here that makes the published field stale - the paint, the nudge and the
    // repair - so the plate picture follows the field instead of standing still until the next
    // keypress. The wait itself is FCkGroundNavGym_OverlayRefresh's: epoch moved, surface quiet.
    private void DoArm_DrawRefresh()
    {
        _DrawRefresh.Request_Arm(_PcEntity, _Field, k_DrawRefreshPollCeiling,
            FCk_Delegate_Timer(this, n"OnDrawRefreshPoll"));
    }

    UFUNCTION()
    private void OnDrawRefreshPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_DrawRefresh.Do_Poll(_Field) == false)
        { return; }

        DoRefresh_Draw();
    }

    // ---- The route draw ------------------------------------------------------------------------------
    //
    // The corridor the walkers are on, end to end, so the paint on key 2 can be seen carving the very
    // route the bodies take. ck.GroundNav.PathAt reads the DEBUG field and not the volume's published
    // one, which is why the bake comes first and has to cover the ground the route crosses.

    private void DoToggle_PathDraw()
    {
        if (_PathDrawEnabled)
        {
            _PathDrawEnabled = false;

            // A bake replaces the plates and leaves the QUERY group exactly where it was, so the route
            // would go on standing over the new picture. Dropping a query drawing is the one thing
            // only ck.GroundNav.Clear does - and it drops the plates with it, which is why the bake
            // follows immediately.
            CkGroundNavGym::Request_ClearDebugDraw();
            DoRefresh_Draw();
            return;
        }

        _PathDrawEnabled = true;

        DoRefresh_Draw();
    }

    // ---- The provider row ---------------------------------------------------------------------------

    private void DoCycle_Provider()
    {
        CkGroundNavGym::Request_CycleProvider();

        ck::groundnav::Log("GroundNav repair gym: provider switched - the volume stays baked either way, and the SURFACE row says which backend is answering now");
    }

    // ---- The paint row ------------------------------------------------------------------------------
    //
    // The PROVIDER-NEUTRAL request, which is the one the crowd goes through: it names a shape and a
    // place and nothing about which backend answers it, so one keypress carves Recast and GroundNav
    // alike. Releasing it is destroying the markup entity - the handle IS the paint's lifetime.

    private void DoToggle_Paint()
    {
        if (ck::IsValid(_Markup))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup));
            _Markup = FCk_Handle_NavSurfaceMarkup();

            DoArm_DrawRefresh();

            ck::groundnav::Log("GroundNav repair gym: the paint is released - the corridor reopens once the surface settles again");
            return;
        }

        // Read BEFORE the request, so the number the verdict compares against is the epoch the field
        // was published at when the paint went on rather than one the derive had already moved.
        _EpochAtPaint = utils_ground_nav_volume::Get_BuildEpoch(_Field.Get_Volume());

        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(k_MarkupHalfExtents)),
            FGameplayTag());
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_ScenePoint(k_MarkupCentre), FVector::OneVector));

        _Markup = utils_nav_surface::Request_ImpassableBox(Request);

        if (ck::Is_NOT_Valid(_Markup))
        {
            ck::groundnav::Warning("GroundNav repair gym: the paint request handed back no markup handle - nothing was carved");
            return;
        }

        DoArm_DrawRefresh();

        ck::groundnav::Log("GroundNav repair gym: the corridor is painted impassable - the walkers on it replan around the hole");
    }

    // ---- The obstacle and its repair -----------------------------------------------------------------

    // Which of the two positions the body is at is read off the ACTOR rather than remembered: the actor
    // is where it is, and a bool that disagreed with it would send the next nudge to the place it is
    // already standing.
    private bool Get_ObstacleIsMoved()
    {
        if (ck::Is_NOT_Valid(_ObstacleActor))
        { return false; }

        const auto Here = _ObstacleActor.GetActorLocation();

        const auto ToHome = (Here - Get_ScenePoint(k_ObstacleHomeCentre)).Size();
        const auto ToMoved = (Here - Get_ScenePoint(k_ObstacleMovedCentre)).Size();

        return ToMoved < ToHome;
    }

    private void DoNudge_Obstacle()
    {
        if (ck::Is_NOT_Valid(_ObstacleActor))
        { return; }

        // How many repairs had completed when this nudge went in, so "a repair has run SINCE the nudge"
        // is a comparison rather than a flag a second nudge would leave lying. The epoch is NOT read
        // here - the locality claim is about the repair, and it is snapshotted at that keypress.
        _RepairsAtNudge = _RepairsRun;

        // OUT of the static world before the move and back in after it. The static world holds its own
        // copy of the shape at the position it was baked at, so a body moved without that round trip
        // is still standing where it was as far as every bake is concerned.
        utils_jolt_static_world::Request_RemoveActor(_ObstacleActor);

        FVector Destination = Get_ScenePoint(k_ObstacleMovedCentre);

        if (Get_ObstacleIsMoved())
        { Destination = Get_ScenePoint(k_ObstacleHomeCentre); }

        _ObstacleActor.SetActorLocation(Destination);

        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(_ObstacleActor);

        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav repair gym: the moved obstacle re-baked 0 Jolt bodies - the ground under it can no longer change");
            return;
        }

        _NudgesRun += 1;

        // The nudge deliberately does NOT republish the volume's field, so this refresh runs out its
        // ceiling and redraws anyway - and the redraw is the point. A debug bake reads the Jolt static
        // world FRESH, so the picture comes back showing the body where it now stands while the rows
        // beside it still report the ground it left as blocked. That disagreement IS the staleness
        // this station is about, and it is what the repair on key 4 closes.
        DoArm_DrawRefresh();

        ck::groundnav::Log("GroundNav repair gym: the obstacle moved one tile - the published field still carries the ground it left, until a repair opens over BOTH footprints");
    }

    private void DoRepair_ObstacleGround()
    {
        // A declared local rather than the call inline: Request_Repair takes the volume BY VALUE, and
        // a const value cannot be handed to a by-value parameter.
        FCk_Handle_GroundNavVolume Volume = _Field.Get_Volume();

        if (ck::Is_NOT_Valid(Volume))
        { return; }

        // The UNION of both footprints, never just the one the body arrived on: the half it LEFT is
        // ground nothing else will ever revisit, so a repair aimed only at the new position leaves the
        // old footprint blocked for the rest of the field's life.
        const auto DirtyBounds = FBox(Get_ScenePoint(k_ObstacleDirtyMin), Get_ScenePoint(k_ObstacleDirtyMax));

        // Read IMMEDIATELY before the request, so the number the verdict compares against is the epoch
        // the field was standing at when this repair was asked for. A MEASUREMENT taken at the instant
        // of the action, not a copy of something the volume goes on holding.
        _EpochAtRepair = utils_ground_nav_volume::Get_BuildEpoch(Volume);

        utils_ground_nav_volume::Request_Repair(Volume,
            FCk_Request_GroundNavVolume_Repair(DirtyBounds),
            FCk_Delegate_Request_OnCompleted(this, n"OnRepairCompleted"));
    }

    // The counters here are this gym's arithmetic about its own requests and nothing else: a refused
    // request leaves the ground exactly as stale as it was, and the rows must go on saying so.
    UFUNCTION()
    private void OnRepairCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RepairsRun += 1;
        _LastRepairResult = InResult;

        // A completed repair is the one thing on this panel that reopens ground, and reopened ground
        // is a plate that was not there before - which is invisible without a redraw over it.
        DoArm_DrawRefresh();
    }

    // Whether this scene owes a repair. Asked of the VOLUME first: Get_IsBuildCurrent compares the
    // backend's world revision AND the authored fingerprint against the ones the standing field went
    // out with, which is exactly the two ways this panel can make a field stale - the nudge moves the
    // world, the paint moves the records. False while nothing is published, so the built check comes
    // first: a volume with no field has no bake to be current with.
    //
    // The second clause is NOT a mirror of that answer - it counts the requests THIS panel made, and it
    // is the floor under the row's enabled flag rather than a second opinion about the field. Without
    // it, a nudge whose world-revision bump the backend did not register would leave the repair row
    // permanently disabled and the station with nothing to press.
    //
    // Deliberately not in the verdict, which reads the epoch instead.
    private bool Get_RepairIsOwed()
    {
        if (_Field.Get_IsBuilt() == false)
        { return false; }

        if (utils_ground_nav_volume::Get_IsBuildCurrent(_Field.Get_Volume()) == false)
        { return true; }

        if (_NudgesRun == 0)
        { return false; }

        return _RepairsRun == _RepairsAtNudge
            || _LastRepairResult != ECk_Request_OperationResult::Succeeded;
    }

    // ---- The crowd walkers ----------------------------------------------------------------------------

    private TArray<int32> Get_WalkerCounts()
    {
        auto Counts = TArray<int32>();
        Counts.Add(0);
        Counts.Add(k_WalkerCountLow);
        Counts.Add(k_WalkerCountHigh);
        return Counts;
    }

    private void DoCycle_Walkers()
    {
        _WalkerCountIndex = (_WalkerCountIndex + 1) % Get_WalkerCounts().Num();

        DoDespawn_Walkers();

        const auto Wanted = Get_WalkerCounts()[_WalkerCountIndex];

        for (int32 Index = 0; Index < Wanted; Index++)
        { DoSpawn_Walker(Index, Wanted); }
    }

    private void DoSpawn_Walker(int32 InIndex, int32 InTotal)
    {
        const auto Offset = (float(InIndex) - (float(InTotal - 1) * 0.5f)) * k_WalkerSpacingUu;

        const auto Spawn = Get_ScenePoint(k_WalkerWestPoint + FVector(0.0, Offset, 0.0));
        const auto Goal = Get_ScenePoint(k_WalkerEastPoint + FVector(0.0, Offset, 0.0));

        auto WalkerEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        WalkerEntity.Set_DebugName(n"GroundNavGym_RepairWalker");

        const auto Facing = (Goal - Spawn).Rotation();

        auto WalkerTransform = utils_transform::Add(WalkerEntity,
            FTransform(Facing, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        auto Walker = utils_crowd_agent::Add(WalkerTransform,
            FCk_Fragment_CrowdAgent_ParamsData(k_WalkerRadiusUu, k_WalkerHeightUu));

        if (ck::Is_NOT_Valid(Walker))
        {
            ck::groundnav::Warning("GroundNav repair gym: a corridor walker got no crowd agent handle");
            utils_entity_lifetime::Request_DestroyEntity(WalkerEntity);
            return;
        }

        utils_velocity::Add(WalkerEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(WalkerEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(WalkerEntity);

        // Composed here with the radius the crowd's own GroundNav dispatch would have used. The
        // dispatch adds the feature only when it is missing, so what runs is identical either way.
        utils_ground_nav_path::Add(WalkerEntity,
            FCk_Fragment_GroundNavPath_ParamsData(k_WalkerRadiusUu));

        utils_crowd_agent::BindTo_OnGoalReached(Walker,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(Walker, FCk_Request_CrowdAgent_MoveTo(Goal));

        _WalkerEntities.Add(WalkerEntity);
        _Walkers.Add(Walker);
        _WalkerHasWalked.Add(false);
    }

    // The walkers ping-pong rather than parking at the far end: a corridor whose bodies all stopped
    // after one crossing shows nothing about a paint dropped onto it a minute later.
    UFUNCTION()
    private void OnWalkerGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        auto WalkerEntity = FCk_Handle(InAgent);

        if (ck::Is_NOT_Valid(WalkerEntity))
        { return; }

        const auto Here = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(WalkerEntity));

        const auto WestEnd = Get_ScenePoint(k_WalkerWestPoint);
        const auto EastEnd = Get_ScenePoint(k_WalkerEastPoint);

        FVector Destination = EastEnd;

        // Which end it is nearer, not a world sign test: the corridor is placed off the station anchor,
        // so its midpoint is wherever the grid put it.
        if ((Here - EastEnd).Size() < (Here - WestEnd).Size())
        { Destination = WestEnd; }

        // Its own lane, not the lane the row spawned it in: the walker keeps the Y it is standing on,
        // so eight bodies turning round at once do not all aim at one point.
        utils_crowd_agent::Request_MoveTo(InAgent,
            FCk_Request_CrowdAgent_MoveTo(FVector(Destination.X, Here.Y, Destination.Z)));
    }

    private void DoDespawn_Walkers()
    {
        for (int32 Index = 0; Index < _WalkerEntities.Num(); Index++)
        {
            auto WalkerEntity = _WalkerEntities[Index];

            if (ck::Is_NOT_Valid(WalkerEntity))
            { continue; }

            utils_entity_lifetime::Request_DestroyEntity(WalkerEntity);
        }

        _WalkerEntities.Empty();
        _Walkers.Empty();
        _WalkerHasWalked.Empty();
    }

    // A walker that is on its way somewhere. There is no Arrived state in
    // ECk_CrowdAgent_MovementState - the four are None, Idle, PathPending and Walking - and this
    // corridor's bodies re-issue a MoveTo the instant they reach an end, so the state at a turnaround
    // is PathPending and not a resting one. Idle and None are the two that mean a body has stopped
    // having anywhere to go, which is what the verdict is looking for.
    private bool Get_WalkerStateIsMoving(ECk_CrowdAgent_MovementState InState)
    {
        return InState == ECk_CrowdAgent_MovementState::Walking
            || InState == ECk_CrowdAgent_MovementState::PathPending;
    }

    // Records that this walker has been seen Walking, and answers whether it ever has. The record is
    // made by the same pass that reads the state, so nothing reads the agent twice to keep it.
    //
    // A walker that has NEVER walked is pending, not failed: a body spawned this frame reads Idle until
    // the crowd has planned it a corridor, and colouring that red would fail the gym on its own spawn.
    // Only a body that walked and then stopped is a walker with nowhere to go.
    private bool Get_WalkerHasWalked(int32 InIndex, ECk_CrowdAgent_MovementState InState)
    {
        if (_WalkerHasWalked.IsValidIndex(InIndex) == false)
        { return false; }

        if (InState == ECk_CrowdAgent_MovementState::Walking)
        { _WalkerHasWalked[InIndex] = true; }

        return _WalkerHasWalked[InIndex];
    }

    // How many of the live walkers have been seen Walking at least once. Read through the same pass as
    // above, so asking this also keeps the record up to date.
    private int32 Get_WalkersSeenWalking()
    {
        int32 Seen = 0;

        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            const auto State = utils_crowd_agent::Get_MovementState(_Walkers[Index]);

            if (Get_WalkerHasWalked(Index, State))
            { Seen += 1; }
        }

        return Seen;
    }

    // ---- The verdict -------------------------------------------------------------------------------
    //
    // Every criterion is a LIVE readback: the provider off the facade, the epoch off the volume, the
    // paint off the markup handle, each walker's state off its own agent. The two Epoch members the
    // criteria compare against are SNAPSHOTS taken at the moment of an action - what the volume was
    // publishing when the repair was asked for, and when the paint went on - which is a measurement of
    // the field, not a copy of it kept in step. So is the per-walker "has been seen Walking" flag: it
    // records that a live readback once said so, which the enum itself cannot say afterwards.
    //
    // TILE LOCALITY has no readback. A "tiles rebuilt by the last repair" count is not among the
    // volume's reflected numbers - Get_TileCount and Get_BuiltTileCount describe the whole published
    // field, not the last repair's share of it - so the row SAYS it has no readback rather than
    // estimating one from the difference between two whole-field counts, which would be a guess dressed
    // as a measurement.
    //
    // WHAT THE PROJECTION CANNOT ANSWER. FCk_NavSurface_ProjectionResult carries a status, a location,
    // a surface normal and an area TAG container, and no cost. The paint this gym drops is an
    // impassable box authored with an empty tag, so there is nothing for a projection inside it to
    // report that the epoch does not already say. The paint criterion is therefore the epoch plus the
    // markup's own live flag, and no point probe.

    private TArray<FString> Get_VerdictFailures()
    {
        auto Failures = TArray<FString>();

        // FIRST, and before anything about the volume: on Recast the volume is still baked and still
        // answers its own counts, but nothing in this world routes through it, so every other criterion
        // below would be describing a field nobody is asking.
        if (utils_nav_surface::Get_Provider() != ECk_NavSurface_Provider::GroundNav)
        {
            Failures.Add("provider is Recast - the volume answers nothing");
            return Failures;
        }

        if (_Field.Get_IsBuilt() == false)
        { return Failures; }

        auto Volume = _Field.Get_Volume();
        const auto EpochNow = utils_ground_nav_volume::Get_BuildEpoch(Volume);

        if (_NudgesRun > 0)
        {
            if (_RepairsRun == _RepairsAtNudge)
            {
                Failures.Add("the obstacle moved and the ground it left is still stale - press 4");
            }
            else if (_LastRepairResult != ECk_Request_OperationResult::Succeeded)
            {
                Failures.Add(f"the last repair answered {_LastRepairResult}");
            }
            else if (EpochNow != _EpochAtRepair + 1)
            {
                Failures.Add(f"the epoch went {_EpochAtRepair} to {EpochNow} across the repair - a local repair is one publish, so something else republished the field");
            }
        }

        if (ck::IsValid(_Markup))
        {
            const auto MarkupIsLive = utils_nav_surface::Get_IsMarkupLive(_Markup);

            if (EpochNow <= _EpochAtPaint)
            {
                Failures.Add(f"the paint is held but the field has not moved since it went on (markup live: {MarkupIsLive})");
            }
            else if (MarkupIsLive == false)
            {
                Failures.Add("the field moved but the markup is not live - the paint is not in effect");
            }
        }

        const auto Asked = Get_WalkerCounts()[_WalkerCountIndex];
        const auto Live = _Walkers.Num();

        if (Live != Asked)
        {
            Failures.Add(f"{Asked} walkers asked for and {Live} on the corridor");
        }
        else
        {
            for (int32 Index = 0; Index < _Walkers.Num(); Index++)
            {
                const auto State = utils_crowd_agent::Get_MovementState(_Walkers[Index]);

                // Pending: this body has not been seen Walking yet, so there is nothing to judge.
                if (Get_WalkerHasWalked(Index, State) == false)
                { continue; }

                if (Get_WalkerStateIsMoving(State))
                { continue; }

                Failures.Add(f"walker {Index} was walking and now reads {State}");
                break;
            }
        }

        return Failures;
    }

    // One line. Get_VerdictText is handed the FIRST failure only - the panel's value column is one row
    // deep and the first thing that is wrong is the thing to go and look at, so a list of three would
    // push the one that matters off the end.
    private FString Get_VerdictLine(const TArray<FString>&in InFailures)
    {
        if (InFailures.Num() > 0)
        {
            auto First = TArray<FString>();
            First.Add(InFailures[0]);

            return CkGroundNavGym::Get_VerdictText("", First);
        }

        // No guard for the provider here: it is the first thing Get_VerdictFailures adds, so an empty
        // failure list already says the world is on GroundNav.
        if (_Field.Get_IsBuilt() == false)
        { return "field not built"; }

        FString Text = "OK";

        if (_NudgesRun > 0)
        { Text += " - repair was local (epoch +1), tile locality: no readback"; }

        if (ck::IsValid(_Markup))
        { Text += " - paint advanced the epoch"; }

        const auto Live = _Walkers.Num();

        if (Live > 0)
        {
            // Pending text while any body has yet to report Walking - the corridor is not wrong, it is
            // not started. Once every one of them has, the line says so and stops counting.
            const auto Seen = Get_WalkersSeenWalking();

            if (Seen < Live)
            { Text += f" - walkers: {Seen} of {Live} walking"; }
            else
            { Text += f" - {Live} walkers moving"; }
        }

        if (_NudgesRun == 0 && ck::Is_NOT_Valid(_Markup) && Live == 0)
        { Text += " - field published, nothing asked of it yet"; }

        return Text;
    }

    // ---- Scene construction ----------------------------------------------------------------------

    private bool DoBuildScene()
    {
        // Guarded, not idempotent by luck: see _SceneSpawned. A restart keeps the scene it already
        // spawned, which is also the scene the volume was baked over.
        if (_SceneSpawned)
        { return true; }

        _SceneSpawned = true;

        // The slab and the obstacle standing on it. Both go into the Jolt static world through the same
        // call - the volume bakes from that world and from nothing else.
        if (CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_SlabCentre), k_SlabScale) == false)
        { return false; }

        if (DoSpawn_Obstacle() == false)
        { return false; }

        return true;
    }

    // The obstacle is the one scene box kept as an actor: the nudge row moves this body and re-bakes
    // it, which is the only way ground in this scene goes stale in the first place.
    //
    // Its own guard is kept even though DoBuildScene now has one. The two say different things: the
    // scene flag says the slab is already in the static world, and this says THIS actor is already
    // held - so a restart keeps the body at whichever of the two positions the reader left it, rather
    // than spawning a second one on top of it.
    private bool DoSpawn_Obstacle()
    {
        if (ck::IsValid(_ObstacleActor))
        { return true; }

        auto Obstacle = CkGroundNavGym::Spawn_BoxActor(this,
            Get_ScenePoint(k_ObstacleHomeCentre), FRotator::ZeroRotator, k_ObstacleScale);

        if (Obstacle == nullptr)
        { return false; }

        _ObstacleActor = Obstacle;

        return true;
    }

    private void DoBringPlayerToViewpoint()
    {
        CkGroundNavGym::Request_FlyToStation(this, "GroundNavRepair",
            k_SceneOffset + k_ViewOffset, k_ViewRotation);
    }

    // Mirrors the gym base private WaitOneFrame - a one-shot timer on the PC own entity.
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

    // ---- Control panel ---------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GROUNDNAV: REPAIR AND MARKUP";
    }

    // Readback: every value column below is asked for as the row is built. The only numbers that are
    // NOT read off the volume or the facade are this gym's own counters - how many repairs it asked for
    // and what the last one answered - and they say so where they stand.
    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        const auto VerdictFailures = Get_VerdictFailures();

        Rows.Add(CkGym_Control::Header("SCENE"));
        Rows.Add(CkGym_Control::Status("Verdict", Get_VerdictLine(VerdictFailures), VerdictFailures.Num() > 0));
        Rows.Add(CkGym_Control::Status("Geometry",
            CkGroundNavGym::Get_GeometryStatusText(_GeometryIsBuilt,
                "one slab, with a 400uu obstacle standing on its north band and 2800uu of corridor across its south one"),
            _GeometryIsBuilt == false));

        Rows.Add(CkGym_Control::Header("REPAIR - one volume, and the three ways this panel makes its ground stale"));
        Rows.Add(CkGym_Control::Status("Field", _Field.Get_FieldStatusText(), _Field.Get_IsBuilt() == false));
        Rows.Add(CkGym_Control::Status("Surface", CkGroundNavGym::Get_SurfaceStatusText()));
        Rows.Add(CkGym_Control::Cycle(EKeys::One, "1",
            "Provider (a per-WORLD choice - the volume here only answers on GroundNav)",
            CkGroundNavGym::Get_ProviderLabel()));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::Two, "2",
            "Markup paint (straddling the walkers' corridor - the plates redraw once the field republishes)",
            ck::IsValid(_Markup), "painted", "clear"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3",
            "Nudge the obstacle one tile - moves the body, leaves the ground behind it stale (the plates redraw off the moved world, the rows keep reading the old field)"));
        Rows.Add(CkGym_Control::Status("Obstacle", Get_ObstacleStatus(), Get_RepairIsOwed()));
        Rows.Add(CkGym_Control::Action(EKeys::Four, "4",
            "Repair over BOTH obstacle footprints - the plates redraw when it completes, so the reopened ground is visible",
            Get_RepairIsOwed()));
        Rows.Add(CkGym_Control::Cycle(EKeys::Five, "5", "Crowd walkers on the corridor",
            Get_WalkerCountLabel()));
        Rows.Add(CkGym_Control::Status("Walkers", Get_WalkerStatus()));
        Rows.Add(CkGym_Control::Toggle(EKeys::Six, "6",
            "Draw the walkers' corridor end to end (bakes a DEBUG field over the slab first - ck.GroundNav.PathAt reads that field and not the volume's published one)",
            _PathDrawEnabled));
        Rows.Add(CkGym_Control::Status("Draw", Get_DrawStatus()));

        return Rows;
    }

    // What is on screen and what put it there. The retained draw is command-driven, so this row states
    // what the gym RAN rather than what a reader could type - the bake the old row asked for is the
    // one this gym now runs itself.
    private FString Get_DrawStatus()
    {
        const auto BakeText = CkGroundNavGym::Get_BakeFieldAtCommandText(Get_ScenePoint(k_SlabBakeCentre));

        if (_PathDrawEnabled)
        { return f"{BakeText} then ck.GroundNav.PathAt across the walkers' corridor are what is on screen - press 6 again to put the plate view back"; }

        return f"{BakeText} at draw mode {k_PlateDrawMode} (plates), with ck.GroundNav.Debug.DrawMarkup 1, is run for you once the field publishes and again a publish after every paint, nudge and repair - it is a DEBUG bake and it is not the field the rows above read";
    }

    // Where the body is standing is read off the actor; whether the ground is stale is read off the
    // volume. The only remembered numbers are the two counters, and they are about the requests this
    // panel made rather than about the field.
    private FString Get_ObstacleStatus()
    {
        if (ck::Is_NOT_Valid(_ObstacleActor))
        { return "the obstacle never spawned"; }

        const auto Where = _ObstacleActor.GetActorLocation();

        FString RepairText = f"{_RepairsRun} repairs run (last {_LastRepairResult})";

        if (Get_RepairIsOwed())
        { RepairText = "the ground under this scene has moved and no publish has caught up - press 4"; }

        return f"standing at x {Where.X} - {RepairText}";
    }

    private FString Get_WalkerCountLabel()
    {
        const auto Wanted = Get_WalkerCounts()[_WalkerCountIndex];
        const auto Live = _Walkers.Num();

        return f"{Wanted} asked for - {Live} on the corridor";
    }

    private FString Get_WalkerStatus()
    {
        if (_Walkers.Num() == 0)
        { return "none spawned"; }

        int32 Moving = 0;

        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            if (Get_WalkerStateIsMoving(utils_crowd_agent::Get_MovementState(_Walkers[Index])))
            { Moving += 1; }
        }

        const auto Total = _Walkers.Num();

        return f"{Moving} of {Total} on their way between the two ends of the corridor";
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (HasAuthority() == false)
        { return; }

        if (InRowIndex == k_Row_Provider)
        {
            DoCycle_Provider();
            return;
        }

        if (InRowIndex == k_Row_PaintMarkup)
        {
            DoToggle_Paint();
            return;
        }

        if (InRowIndex == k_Row_NudgeObstacle)
        {
            DoNudge_Obstacle();
            return;
        }

        if (InRowIndex == k_Row_Repair)
        {
            DoRepair_ObstacleGround();
            return;
        }

        if (InRowIndex == k_Row_Walkers)
        {
            DoCycle_Walkers();
            return;
        }

        if (InRowIndex == k_Row_PathDraw)
        {
            DoToggle_PathDraw();
            return;
        }
    }
}
