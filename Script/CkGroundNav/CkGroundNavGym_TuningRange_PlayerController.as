class ACk_GroundNavGym_TuningRange_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- Scene constants -------------------------------------------------------------------------
    //
    // Every dimension here is chosen so that ONE tunable decides what the bake does with it. The
    // riser is the clearest case: at 20uu it sits between the default plane-fit tolerance (10) and
    // the next value the panel offers (25), so a single keypress flips the staircase between twelve
    // plates and six.

    private const FVector k_FloorLocation = FVector(0.0, 0.0, 0.0);

    // Z scale must stay >= 0.5 - thinner slabs bake to zero walkable tiles. The walkable surface is
    // at the actor origin, so the slab hangs below Z=0.
    private const FVector k_FloorScale = FVector(24.0, 24.0, 0.5);

    private const int32 k_StepCount   = 12;
    private const float k_StepRunUu   = 100.0f;
    private const float k_StepRiseUu  = 20.0f;
    private const float k_StairStartX = -500.0f;
    private const float k_StairWidthY = 600.0f;

    // Sits on top of the last step and reaches out over the floor. The floor underneath keeps 220uu
    // of headroom, which clears the default 180uu agent, so the region genuinely has two layers
    // rather than one layer with a hole in it.
    private const FVector k_PlatformCentre = FVector(1050.0, 0.0, 230.0);
    private const FVector k_PlatformScale  = FVector(7.0, 10.0, 0.2);

    // 75uu wide - three cells at the default 25uu lattice. Narrow enough that the ledge filter can
    // erase it outright, which is the only way to see what that filter costs.
    private const FVector k_CatwalkCentre = FVector(475.0, 450.0, 230.0);
    private const FVector k_CatwalkScale  = FVector(4.5, 0.75, 0.2);

    // Inner faces at Y = +/-80, so the gap is 160uu. Wide enough for the default 34uu-radius agent
    // and tight enough to be the only pinch in the clearance field.
    private const FVector k_PillarNorthCentre = FVector(-900.0, 180.0, 150.0);
    private const FVector k_PillarSouthCentre = FVector(-900.0, -180.0, 150.0);
    private const FVector k_PillarScale       = FVector(2.0, 2.0, 3.0);

    // A sheet with nothing on its underside - the one thing in the scene that is NOT closed. The
    // bake reads an asset's SIMPLE collision first, so a box or a capsule arrives closed no matter
    // what its triangles look like; /Engine/BasicShapes/Plane carries a collision box and would too.
    // This mesh has no simple collision at all, which is the one case where the bake falls through
    // to the cooked triangle mesh and the sheet's four boundary edges reach the closure check.
    private const FString k_OpenBodyMeshPath = "/Engine/ArtTools/RenderToTexture/Meshes/S_1_Unit_Plane.S_1_Unit_Plane";

    // Clear of the stairs (Y +/-300), the catwalk (Y +450) and both pillars, and on the viewpoint's
    // side of the scene so the red edges read without flying anywhere. The 2uu lift stops it fighting
    // the floor plane and stays inside every plane-fit tolerance the panel offers, so the floor
    // underneath still merges straight through it and stays walkable.
    private const FVector k_OpenBodyCentre = FVector(200.0, -700.0, 2.0);
    private const float   k_OpenBodyWidthUu = 200.0f;

    // The bake is aimed at the scene, NOT at the pawn. ck.GroundNav.Bake centres its region on the
    // viewer, which is unusable here: this pawn flies, and a viewer that climbs above the region
    // height leaves the ground behind and below it, so the bake reports NoGeometryInRegion while the
    // scene sits in plain view. ck.GroundNav.BakeAt pins the region instead, so flying around changes
    // what you can SEE and never what was baked.
    private const FVector k_BakeCentre = FVector(200.0, 0.0, 120.0);

    private const FVector  k_PlayerViewLocation = FVector(300.0, -900.0, 550.0);
    private const FRotator k_PlayerViewRotation = FRotator(-22.0, 75.0, 0.0);

    // ---- Links station ---------------------------------------------------------------------------
    //
    // The other stations bake a DEBUG-owned field through ck.GroundNav.BakeAt: a picture, owned by the
    // draw layer, that no volume holds and no request can be aimed at. A link is authored ON a volume,
    // and both the mode-7 draw and ck.GroundNav.LinksAt read the volumes' PUBLISHED fields - so this
    // station mints a volume of its own over its own corner of the floor and bakes it for real. The
    // debug bake the rest of the panel drives is untouched by it, and vice versa.
    //
    // The corner is the north-west quadrant, which is the one part of the scene nothing else occupies:
    // the stairs and the platform sit inside Y +/-500, the catwalk at Y +412..487, the pillars at
    // Y +/-280, and the open-collision sheet at Y -700.

    // 400 x 400 x 200, standing on the floor - X -700..-300, Y 700..1100, top face at Z 200. The Z
    // scale is 2.0, well past the 0.5 below which a slab bakes to zero walkable tiles.
    private const FVector k_LinksDeckCentre = FVector(-500.0, 900.0, 100.0);
    private const FVector k_LinksDeckScale  = FVector(4.0, 4.0, 2.0);

    // Deck plus the floor around it, and nothing else in the scene.
    private const FVector k_LinksVolumeMin = FVector(-1000.0, 500.0, -100.0);
    private const FVector k_LinksVolumeMax = FVector(100.0, 1300.0, 400.0);

    // The DROP: off the deck's +X edge and down onto the floor beyond it. One-way, because walking off
    // a ledge is not the same act as climbing back up it - that is what the ladder is for.
    private const FVector k_LinksDropStart = FVector(-360.0, 900.0, 200.0);
    private const FVector k_LinksDropEnd   = FVector(-180.0, 900.0, 0.0);

    // The LADDER: off the floor south of the deck and up onto its top face. Priced at twice its own
    // span, so a route that has any way round prefers the way round; narrowed to 40uu of clearance,
    // which still admits the 34uu default agent and refuses anything wider.
    private const FVector k_LinksLadderStart = FVector(-500.0, 640.0, 0.0);
    private const FVector k_LinksLadderEnd   = FVector(-500.0, 760.0, 200.0);

    private const float k_LinksLadderMultiplier = 2.0f;
    private const float k_LinksLadderClearanceUu = 40.0f;

    // The station's own bake, deliberately the same shape every GroundNav fixture in the corpus uses.
    // LedgeSensitivity is pinned off: the deck is a 400uu square that drops 200uu on all four sides,
    // and the ledge filter at its default would demote its whole top - leaving the two links with
    // nothing to land on for a reason that has nothing to do with links.
    private const float k_LinksCellSizeUu = 25.0f;
    private const float k_LinksCellHeightUu = 10.0f;
    private const float k_LinksTileSizeUu = 500.0f;
    private const float k_LinksAgentRadiusUu = 34.0f;
    private const float k_LinksAgentHalfHeightUu = 90.0f;

    // 0.05s a poll, so this is 30 seconds of waiting on a NAMED condition before the station gives up
    // and says so in its own status row rather than hanging silently.
    private const int32 k_LinksSettlePollCeiling = 600;

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Header and Status rows never reach Request_ControlActivated but they DO occupy an index. These
    // constants sit next to each other so a row inserted in one place and not renumbered here is a
    // visible edit rather than a silent off-by-one.

    private const int32 k_Row_Bake        = 5;
    private const int32 k_Row_Mode        = 6;
    private const int32 k_Row_Clear       = 8;
    private const int32 k_Row_PlaneFit    = 10;
    private const int32 k_Row_NormalCone  = 11;
    private const int32 k_Row_Ledge       = 13;
    private const int32 k_Row_StepHeight  = 14;
    private const int32 k_Row_AgentHeight = 15;
    private const int32 k_Row_AgentRadius = 16;
    private const int32 k_Row_CellSize    = 18;
    private const int32 k_Row_Print       = 20;
    private const int32 k_Row_Reset       = 21;
    private const int32 k_Row_Viewpoint   = 22;
    private const int32 k_Row_BakeField   = 23;
    private const int32 k_Row_OpenBody    = 24;

    // Appended after every existing row on purpose: a section inserted higher up would renumber
    // every constant above it, and the panel dispatches on the index.
    private const int32 k_Row_LinksToggle = 28;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private bool _GeometryIsBuilt = false;
    private int32 _BakeCount = 0;

    // ---- Links station state ---------------------------------------------------------------------

    private FCk_Handle _LinksVolumeEntity;
    private FCk_Handle_GroundNavVolume _LinksVolume;
    private FCk_Handle _LinksDropEntity;
    private FCk_Handle _LinksLadderEntity;

    // ONE repeating timer, not a chain of one-shots: utils_timer::Add mints a child entity per timer,
    // so re-arming a one-shot every poll would leave one behind for every frame it waited.
    private FCk_Handle_Timer _LinksSettleTimer;

    private bool _LinksArmed = false;
    private int32 _LinksSettlePolls = 0;

    // The one thing about the links station with no readback: what it is waiting on. Everything else
    // the panel reports - whether the field is built, whether each link is live, how many did not
    // resolve, whether they are enabled - is read off the volume every frame.
    private FString _LinksStage = "not started";

    // The row reads this back rather than mirroring a bool: the actor IS the state, and a bool that
    // disagreed with it would report an open body the static world no longer holds.
    private AStaticMeshActor _OpenBodyActor = nullptr;

    // T and every tunable key re-run the bake so the drawing tracks the change. They re-run the KIND
    // of bake that last ran - region after R, tiled field after Y - because a region bake would
    // replace the field and mode 5 would then have no tiles to draw.
    private bool _LastBakeWasField = false;

    private int32 _ModeIndex = 0;
    private int32 _PlaneFitIndex = 1;
    private int32 _NormalConeIndex = 2;
    private int32 _LedgeIndex = 0;
    private int32 _StepHeightIndex = 2;
    private int32 _AgentHeightIndex = 1;
    private int32 _AgentRadiusIndex = 1;
    private int32 _CellSizeIndex = 1;

    // ---- Tunable value tables --------------------------------------------------------------------
    //
    // The gym owns these values and pushes them to the cvars; it never reads them back. Typing a
    // value straight into the console still works and still takes effect - the panel just will not
    // know about it until the next keypress pushes the gym value over the top.

    private TArray<float> Get_PlaneFitValues()
    {
        auto Values = TArray<float>();
        Values.Add(2.5f);
        Values.Add(10.0f);
        Values.Add(25.0f);
        Values.Add(50.0f);
        return Values;
    }

    private TArray<FString> Get_PlaneFitLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("2.5 uu (near the quantization floor)");
        Labels.Add("10 uu (default - steps survive)");
        Labels.Add("25 uu (past the 20uu riser - steps merge)");
        Labels.Add("50 uu (the whole staircase flattens)");
        return Labels;
    }

    private TArray<float> Get_NormalConeValues()
    {
        auto Values = TArray<float>();
        Values.Add(1.0f);
        Values.Add(3.0f);
        Values.Add(10.0f);
        Values.Add(30.0f);
        return Values;
    }

    private TArray<FString> Get_NormalConeLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("1 deg (fragments flat ground)");
        Labels.Add("3 deg (the narrow end where it still binds)");
        Labels.Add("10 deg (default)");
        Labels.Add("30 deg (no measurable effect)");
        return Labels;
    }

    private TArray<float> Get_LedgeValues()
    {
        auto Values = TArray<float>();
        Values.Add(1.0f);
        Values.Add(0.5f);
        Values.Add(0.34f);
        Values.Add(0.0f);
        return Values;
    }

    private TArray<FString> Get_LedgeLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("1.0 - one dropping side (erases the catwalk)");
        Labels.Add("0.5 - two dropping sides");
        Labels.Add("0.34 - three dropping sides");
        Labels.Add("off - nothing is demoted");
        return Labels;
    }

    private TArray<float> Get_StepHeightValues()
    {
        auto Values = TArray<float>();
        Values.Add(10.0f);
        Values.Add(25.0f);
        Values.Add(40.0f);
        Values.Add(60.0f);
        return Values;
    }

    private TArray<FString> Get_StepHeightLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("10 uu (below the 20uu riser - the stairs disconnect)");
        Labels.Add("25 uu (just clears the riser)");
        Labels.Add("40 uu (default)");
        Labels.Add("60 uu");
        return Labels;
    }

    private TArray<float> Get_AgentHeightValues()
    {
        auto Values = TArray<float>();
        Values.Add(120.0f);
        Values.Add(180.0f);
        Values.Add(220.0f);
        Values.Add(260.0f);
        return Values;
    }

    private TArray<FString> Get_AgentHeightLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("120 uu");
        Labels.Add("180 uu (default)");
        Labels.Add("220 uu (exactly the platform headroom)");
        Labels.Add("260 uu (the floor under the platform is culled - one layer)");
        return Labels;
    }

    private TArray<float> Get_AgentRadiusValues()
    {
        auto Values = TArray<float>();
        Values.Add(17.0f);
        Values.Add(34.0f);
        Values.Add(60.0f);
        Values.Add(90.0f);
        return Values;
    }

    private TArray<FString> Get_AgentRadiusLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("17 uu");
        Labels.Add("34 uu (default - fits the 160uu gap)");
        Labels.Add("60 uu");
        Labels.Add("90 uu (wider than the gap - the pinch closes)");
        return Labels;
    }

    private TArray<float> Get_CellSizeValues()
    {
        auto Values = TArray<float>();
        Values.Add(12.5f);
        Values.Add(25.0f);
        Values.Add(50.0f);
        Values.Add(100.0f);
        return Values;
    }

    private TArray<FString> Get_CellSizeLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("12.5 uu (4x the cells - expect draw truncation)");
        Labels.Add("25 uu (default)");
        Labels.Add("50 uu (the 75uu catwalk is now 1.5 cells)");
        Labels.Add("100 uu (a whole tread is one cell)");
        return Labels;
    }

    // What the current mode paints, in the mode's own colours. Without this the drawing is a
    // picture nobody can read: green-vs-blue means layer in two modes and nothing in the other two,
    // and the clearance ramp runs the opposite way to the usual red-is-bad reflex.
    private TArray<FString> Get_ModeLegends()
    {
        auto Legends = TArray<FString>();
        Legends.Add("one wireframe box per plate - green = layer 0, blue = layer 1");
        Legends.Add("one point per cell - BLUE = least room, RED = most (scaled to this bake)");
        Legends.Add("one point per cell - green = layer 0 (ground), blue = layer 1 (deck above it)");
        Legends.Add("RED = cut by the filters, dim grey = what survived");
        Legends.Add("one line per crossing - BLUE = tightest, RED = widest; a mast marks one that changes floor");
        Legends.Add("BLUE box per tile, RED = a tile that did not build; thick lines = the seams between tiles");
        return Legends;
    }

    private TArray<FString> Get_ModeLabels()
    {
        auto Labels = TArray<FString>();
        Labels.Add("0 Plates");
        Labels.Add("1 Clearance");
        Labels.Add("2 Layers");
        Labels.Add("3 Rejected (what the filters threw away)");
        Labels.Add("4 Portals (the crossings between plates)");
        Labels.Add("5 Tiles (needs a field bake - press Y; T then keeps re-baking the field)");
        return Labels;
    }

    // ---- Station ---------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavTuningRange");
        Station.AutoSize = true;
        Station.Transform = FTransform(FRotator(0.0, 270.0, 0.0), FVector(300.0, 2600.0, 0.0), FVector::OneVector);
        Station.Title = FText::FromString("GroundNav - Tuning Range");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("A scene built so that each part of it is decided by exactly one bake tunable. Press R to bake around your pawn and read the summary that prints to the log; every other key changes a value and re-bakes."));
        Description.Add(FText::FromString("The staircase has 20uu risers. At the default plane-fit tolerance of 10uu you get one plate per tread; press F once to raise it past 20 and the treads merge into ramps. Watch the worst height spread in the summary - when it reaches 20 the steps have stopped existing."));
        Description.Add(FText::FromString("The platform leaves 220uu of headroom over the floor, so the region reports two layers. Raise the agent height past 220 with M and the floor beneath it is culled, dropping the count to one."));
        Description.Add(FText::FromString("The catwalk is 75uu wide and drops 240uu on both sides. Draw mode 3 shows what the ledge filter removed - at sensitivity 1.0 the whole catwalk goes red."));
        Description.Add(FText::FromString("Draw mode 4 shows the crossings between plates. The two pillars stand 160uu apart, so the crossing through the gap between them offers about 80uu - that number, not the open floor either side of it, is what decides whether a body can get through."));
        Description.Add(FText::FromString("Fail signatures: status BackendUnavailable = no Jolt static world in this PIE mode; NoGeometryInRegion = the scene did not bake into Jolt, or the pawn drifted outside the region."));
        Station.Description = Description;

        Stations.Add(Station);

        auto LinksStation = FCkGym_Station_SpawnParams_Payload();
        LinksStation.Tags.Add(n"GroundNavLinks");
        LinksStation.AutoSize = true;
        LinksStation.Transform = FTransform(FRotator(0.0, 270.0, 0.0), FVector(-500.0, 2600.0, 0.0), FVector::OneVector);
        LinksStation.Title = FText::FromString("GroundNav - Nav Links");

        auto LinksDescription = TArray<FText>();
        LinksDescription.Add(FText::FromString("A deck standing on the floor to the north-west, joined to the ground beside it by two authored navigation links: a one-way DROP off the deck's east edge, and a one-way LADDER back up its south face. Both are authored on a volume this station bakes for itself - the R and Y bakes the rest of the panel drives are a debug picture that no volume holds, and a link has to be authored ON one."));
        LinksDescription.Add(FText::FromString("Type ck.GroundNav.LinksAt 0 0 0 to draw both links and print what each end resolved to. It reads the PUBLISHED field, so it needs no bake at all: green means traversable, grey disabled, orange an end over ground nobody has baked, red an end with no ground under it."));
        LinksDescription.Add(FText::FromString("Type ck.GroundNav.Debug.Mode 7 and then press R or Y to see the same links over the dimmed plates they join. Note that R, Y and every tunable key push this gym's own draw mode back over the top, so set the mode again after a bake - or stay on ck.GroundNav.LinksAt, which does not care."));
        LinksDescription.Add(FText::FromString("Press U to disable both links and again to re-enable them. A disabled link is invisible to search and to reachability, and the LINKS panel rows below report each one's live state, read off the volume rather than remembered."));
        LinksDescription.Add(FText::FromString("The ladder is priced at twice its own straight-line span and narrowed to 40uu of clearance; the drop is priced at its span and admits any agent. A link never costs less than its own length - that is what keeps the search's Euclidean heuristic admissible."));
        LinksStation.Description = LinksDescription;

        Stations.Add(LinksStation);

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
            ck::groundnav::Warning("GroundNav gym: PC entity invalid; cannot start");
            return;
        }

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav gym: the scene failed to bake into the Jolt static world - every bake will report NoGeometryInRegion", n"GroundNavGym.Scene", 10.0);
        }

        DoPushAllTunables();

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        DoArm_LinksStation();

        ck::groundnav::Log("GroundNav gym: scene built - press R to bake");
    }

    // ---- Links station ---------------------------------------------------------------------------
    //
    // Mints a volume over the deck and the floor around it, bakes it, and authors the drop and the
    // ladder once the surface has gone quiet. Guarded so Ck_Gym_Restart re-running the gym does not
    // stack a second volume over the same ground.

    private void DoArm_LinksStation()
    {
        if (_LinksArmed)
        { return; }

        if (_GeometryIsBuilt == false)
        {
            _LinksStage = "the scene is not in the Jolt static world - nothing to bake over";
            return;
        }

        _LinksArmed = true;

        // The settle below is answered by whichever provider the world is on, and it folds over every
        // GroundNav volume the world holds - this station's, and nothing else in this scene. The
        // provider is a per-WORLD selection and the cycler travels to reach another gym, so this one
        // is not handed back: the world it was set on ends with the gym.
        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);

        _LinksVolumeEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        _LinksVolumeEntity.Request_OverrideToSelf();
        _LinksVolumeEntity.Set_DebugName(n"GroundNavGym_LinksField");

        auto Config = FCk_GroundNav_BakeConfig(k_LinksCellSizeUu, k_LinksCellHeightUu);
        Config.Set_TileSizeUu(k_LinksTileSizeUu);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(k_LinksAgentHalfHeightUu, k_LinksAgentRadiusUu)));
        Profile.Set_LedgeSensitivity(0.0f);

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(
            FBox(k_LinksVolumeMin, k_LinksVolumeMax), Config, Profile);

        // The bake waited on must be the one asked for, not one that happened to run at setup.
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _LinksVolume = utils_ground_nav_volume::Add(_LinksVolumeEntity, VolumeParams);

        if (ck::Is_NOT_Valid(_LinksVolume))
        {
            _LinksStage = "Add() returned an invalid volume handle";
            return;
        }

        utils_ground_nav_volume::Request_Build(_LinksVolume, FCk_Request_GroundNavVolume_Build());

        _LinksStage = "baking, then waiting for the surface to settle";
        _LinksSettlePolls = 0;

        auto PollParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        PollParams.Set_StartingState(ECk_Timer_State::Running)
                  .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);

        auto PollTimer = utils_timer::Add(_PcEntity, PollParams);
        PollTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnLinksSettlePoll"));

        _LinksSettleTimer = PollTimer;
    }

    // The one named condition worth waiting on after a bake: nothing in flight and nothing pending, so
    // the field the volume publishes is the one every query - and every link resolution - answers
    // from. A fixed number of hops would bake a guess about the probe budget into the gym.
    UFUNCTION()
    private void OnLinksSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _LinksSettlePolls += 1;

        if (utils_nav_surface::Get_IsSurfaceSettled())
        {
            DoStop_LinksSettlePoll();
            DoAuthor_Links();
            return;
        }

        if (_LinksSettlePolls >= k_LinksSettlePollCeiling)
        {
            DoStop_LinksSettlePoll();
            _LinksStage = "the surface never settled - no links were authored";
            ck::groundnav::Log("GroundNav gym: the links field never settled - the drop and the ladder were not authored");
        }
    }

    private void DoStop_LinksSettlePoll()
    {
        if (ck::Is_NOT_Valid(_LinksSettleTimer))
        { return; }

        utils_timer::Request_Stop(_LinksSettleTimer);
        _LinksSettleTimer = FCk_Handle_Timer();
    }

    private void DoAuthor_Links()
    {
        _LinksDropEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        _LinksDropEntity.Request_OverrideToSelf();
        _LinksDropEntity.Set_DebugName(n"GroundNavGym_DropLink");

        _LinksLadderEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        _LinksLadderEntity.Request_OverrideToSelf();
        _LinksLadderEntity.Set_DebugName(n"GroundNavGym_LadderLink");

        DoRequest_Links(ECk_EnableDisable::Enable);

        _LinksStage = f"authored after {_LinksSettlePolls} settle polls";
        ck::groundnav::Log("GroundNav gym: the drop and the ladder are authored - ck.GroundNav.LinksAt 0 0 0 lists them");
    }

    // Both links, every time, from one place: the toggle re-requests them with the enable flag flipped
    // and nothing else changed, so the two forms cannot drift apart. Naming the SAME entities is what
    // keeps each record's id - an update keeps the id the entity was first admitted under.
    private void DoRequest_Links(ECk_EnableDisable InEnable)
    {
        if (ck::Is_NOT_Valid(_LinksVolume))
        { return; }

        // The id is -1 because the VOLUME assigns it; the record's identity carries no setter.
        auto DropRecord = FCk_GroundNav_LinkRecord(-1, k_LinksDropStart, k_LinksDropEnd);

        DropRecord.Set_Direction(ECk_GroundNav_LinkDirection::Forward)
                  .Set_Enable(InEnable);

        utils_ground_nav_volume::Request_Link(_LinksVolume,
            FCk_Request_GroundNavVolume_Link(_LinksDropEntity, DropRecord));

        auto LadderRecord = FCk_GroundNav_LinkRecord(-1, k_LinksLadderStart, k_LinksLadderEnd);

        LadderRecord.Set_Direction(ECk_GroundNav_LinkDirection::Forward)
                    .Set_CostMultiplierForward(k_LinksLadderMultiplier)
                    .Set_ClearanceUu(k_LinksLadderClearanceUu)
                    .Set_Enable(InEnable);

        utils_ground_nav_volume::Request_Link(_LinksVolume,
            FCk_Request_GroundNavVolume_Link(_LinksLadderEntity, LadderRecord));
    }

    private void DoToggle_Links()
    {
        if (ck::Is_NOT_Valid(_LinksVolume))
        { return; }

        auto Enable = ECk_EnableDisable::Enable;

        if (Get_LinksAreEnabled())
        { Enable = ECk_EnableDisable::Disable; }

        DoRequest_Links(Enable);

        ck::groundnav::Log("GroundNav gym: link enable flipped - the derive republishes, then ck.GroundNav.LinksAt shows the new state");
    }

    // Read off the record the volume holds rather than mirrored in a bool: the volume IS the state,
    // and a member that disagreed with it would report links the field no longer carries.
    private bool Get_LinksAreEnabled()
    {
        auto Records = utils_ground_nav_volume::Get_LinkRecords(_LinksVolume);

        if (Records.Num() == 0)
        { return false; }

        return Records[0].Get_Enable() == ECk_EnableDisable::Enable;
    }

    // ---- Scene construction ----------------------------------------------------------------------

    private bool DoBuildScene()
    {
        if (DoSpawnFloor() == false)
        { return false; }

        for (int32 StepIndex = 0; StepIndex < k_StepCount; ++StepIndex)
        {
            // Each step is a solid block from the floor up to its own tread rather than a slab
            // floating at tread height: a floating slab would leave walkable floor underneath it and
            // read as a stack of layers instead of as a staircase.
            const auto TopZ = k_StepRiseUu * float(StepIndex + 1);
            const auto CentreX = k_StairStartX + (k_StepRunUu * (float(StepIndex) + 0.5f));

            const auto Centre = FVector(CentreX, 0.0, TopZ * 0.5);
            const auto Scale = FVector(k_StepRunUu / 100.0, k_StairWidthY / 100.0, TopZ / 100.0);

            if (DoSpawnBox(Centre, Scale) == false)
            { return false; }
        }

        if (DoSpawnBox(k_PlatformCentre, k_PlatformScale) == false)
        { return false; }

        if (DoSpawnBox(k_CatwalkCentre, k_CatwalkScale) == false)
        { return false; }

        if (DoSpawnBox(k_PillarNorthCentre, k_PillarScale) == false)
        { return false; }

        if (DoSpawnBox(k_PillarSouthCentre, k_PillarScale) == false)
        { return false; }

        // The links station's deck. It is scene geometry like everything else here, so it goes into
        // the Jolt static world through the same call - the links volume bakes from that world.
        if (DoSpawnBox(k_LinksDeckCentre, k_LinksDeckScale) == false)
        { return false; }

        return true;
    }

    private bool DoSpawnFloor()
    {
        auto Floor = SpawnActor(ACk_Gym_Floor, k_FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::groundnav::Warning("GroundNav gym: failed to spawn the floor actor");
            return false;
        }

        Floor.SetActorScale3D(k_FloorScale);
        FinishSpawningActor(Floor);

        // The floor has to be baked like everything else. The GroundNav backend reads the Jolt
        // static world, not the level collision - a floor that Recast can see is still nothing to
        // this bake until it has Jolt bodies.
        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(Floor);
        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav gym: the floor baked 0 Jolt bodies");
            return false;
        }

        return true;
    }

    private bool DoSpawnBox(FVector InCentre, FVector InScale)
    {
        auto BoxActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, InCentre));
        if (ck::Is_NOT_Valid(BoxActor))
        {
            ck::groundnav::Warning("GroundNav gym: failed to spawn a scene box");
            return false;
        }

        // A runtime-spawned AStaticMeshActor must be Movable BEFORE it will accept a mesh.
        BoxActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);

        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh == nullptr)
        {
            ck::groundnav::Warning("GroundNav gym: failed to load /Engine/BasicShapes/Cube.Cube");
            return false;
        }
        BoxActor.StaticMeshComponent.SetStaticMesh(CubeMesh);

        auto BoxMaterial = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (BoxMaterial != nullptr)
        { BoxActor.StaticMeshComponent.SetMaterial(0, BoxMaterial); }

        BoxActor.SetActorScale3D(InScale);
        BoxActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(BoxActor);
        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav gym: a scene box baked 0 Jolt bodies - the bake would read it as free space");
            return false;
        }

        return true;
    }

    // Scaled from the asset's own bounds rather than a hardcoded number: the mesh is an engine sheet
    // whose authored size is not ours to assume, and a sheet baked at the wrong size is either
    // invisible or covers the scene.
    private bool DoSpawnOpenBody()
    {
        auto SheetActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, k_OpenBodyCentre));
        if (ck::Is_NOT_Valid(SheetActor))
        {
            ck::groundnav::Warning("GroundNav gym: failed to spawn the open-collision body");
            return false;
        }

        SheetActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);

        auto SheetMesh = Cast<UStaticMesh>(LoadObject(this, k_OpenBodyMeshPath));
        if (SheetMesh == nullptr)
        {
            ck::groundnav::Warning("GroundNav gym: failed to load the open-collision sheet mesh");
            SheetActor.DestroyActor();
            return false;
        }
        SheetActor.StaticMeshComponent.SetStaticMesh(SheetMesh);

        auto SheetMaterial = Cast<UMaterialInterface>(LoadObject(this, "/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
        if (SheetMaterial != nullptr)
        { SheetActor.StaticMeshComponent.SetMaterial(0, SheetMaterial); }

        const auto LocalBounds = SheetMesh.GetBoundingBox();
        const auto LocalSize = LocalBounds.Max - LocalBounds.Min;

        auto LocalWidthUu = LocalSize.X;
        if (LocalSize.Y > LocalWidthUu)
        { LocalWidthUu = LocalSize.Y; }

        if (LocalWidthUu <= 0.0)
        {
            ck::groundnav::Warning("GroundNav gym: the open-collision sheet mesh has no width to scale from");
            SheetActor.DestroyActor();
            return false;
        }

        const auto SheetScale = k_OpenBodyWidthUu / LocalWidthUu;
        SheetActor.SetActorScale3D(FVector(SheetScale, SheetScale, 1.0));
        SheetActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(SheetActor);
        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav gym: the open-collision body baked 0 Jolt bodies - the bake would never see it");
            SheetActor.DestroyActor();
            return false;
        }

        _OpenBodyActor = SheetActor;
        return true;
    }

    private void DoRemoveOpenBody()
    {
        if (ck::Is_NOT_Valid(_OpenBodyActor))
        { return; }

        // The static world keeps its own copy of the shape, so destroying the actor alone would leave
        // the open geometry in the bake for the rest of the session.
        utils_jolt_static_world::Request_RemoveActor(_OpenBodyActor);
        _OpenBodyActor.DestroyActor();
        _OpenBodyActor = nullptr;
    }

    private void DoToggleOpenBody()
    {
        if (ck::IsValid(_OpenBodyActor))
        {
            DoRemoveOpenBody();
            ck::groundnav::Log("GroundNav gym: open-collision body removed - press R or Y to bake again");
            return;
        }

        if (DoSpawnOpenBody() == false)
        { return; }

        ck::groundnav::Log("GroundNav gym: open-collision body added - press R or Y to bake again and read the OPEN COLLISION block");
    }

    private void DoBringPlayerToViewpoint()
    {
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        { return; }

        ViewPawn.SetActorLocation(k_PlayerViewLocation);
        SetControlRotation(k_PlayerViewRotation);
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

    // ---- Tunable plumbing ------------------------------------------------------------------------

    private void DoSetTunable(FString InName, float InValue)
    {
        System::ExecuteConsoleCommand(f"ck.GroundNav.Debug.{InName} {InValue}");
    }

    // Pushes the whole set rather than just the one that changed, so the cvars and the panel always
    // agree from the first keypress even if something else wrote them earlier in the session.
    private void DoPushAllTunables()
    {
        // Sized to the scene rather than to the viewer: the scene spans X -1200..1400 and Y +/-1200,
        // and everything walkable in it sits between Z=0 and Z=240.
        DoSetTunable("ExtentUu", 1500.0f);
        DoSetTunable("HeightUu", 400.0f);
        DoSetTunable("MaxCells", 40000.0f);

        DoSetTunable("Mode", float(_ModeIndex));
        DoSetTunable("PlaneFitToleranceUu", Get_PlaneFitValues()[_PlaneFitIndex]);
        DoSetTunable("NormalConeDegrees", Get_NormalConeValues()[_NormalConeIndex]);
        DoSetTunable("LedgeSensitivity", Get_LedgeValues()[_LedgeIndex]);
        DoSetTunable("StepHeightUu", Get_StepHeightValues()[_StepHeightIndex]);
        DoSetTunable("AgentHeightUu", Get_AgentHeightValues()[_AgentHeightIndex]);
        DoSetTunable("AgentRadiusUu", Get_AgentRadiusValues()[_AgentRadiusIndex]);
        DoSetTunable("CellSizeUu", Get_CellSizeValues()[_CellSizeIndex]);
    }

    private void DoBake()
    {
        DoPushAllTunables();
        System::ExecuteConsoleCommand("ck.GroundNav.Clear");
        System::ExecuteConsoleCommand(
            f"ck.GroundNav.BakeAt {k_BakeCentre.X} {k_BakeCentre.Y} {k_BakeCentre.Z}");
        _BakeCount += 1;
        _LastBakeWasField = false;
    }

    // The same scene baked as several tiles instead of one region. Everything else is identical, so
    // the two runs are directly comparable - which is the point: a tiled bake that disagreed with the
    // whole one would show up here as a seam, and nowhere else.
    private void DoBakeField()
    {
        DoPushAllTunables();
        DoSetTunable("TileSizeUu", 800.0f);
        System::ExecuteConsoleCommand("ck.GroundNav.Clear");
        System::ExecuteConsoleCommand(
            f"ck.GroundNav.BakeFieldAt {k_BakeCentre.X} {k_BakeCentre.Y} {k_BakeCentre.Z}");
        _BakeCount += 1;
        _LastBakeWasField = true;
    }

    private void DoRebake()
    {
        if (_LastBakeWasField)
        {
            DoBakeField();
            return;
        }

        DoBake();
    }

    // ---- Control panel ---------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GROUNDNAV: TUNING RANGE";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("SCENE"));
        Rows.Add(CkGym_Control::Status("Geometry",
            _GeometryIsBuilt ? "floor + 12 steps (20uu risers) + platform + 75uu catwalk + 160uu pinch"
                             : "NOT BAKED INTO JOLT - every bake will find nothing",
            _GeometryIsBuilt == false));
        Rows.Add(CkGym_Control::Status("Bake region",
        f"white box, pinned to ({k_BakeCentre.X}, {k_BakeCentre.Y}, {k_BakeCentre.Z}), +/-1500uu wide, 400uu tall - it does not follow you"));
        Rows.Add(CkGym_Control::Status("Bakes run", f"{_BakeCount}"));

        Rows.Add(CkGym_Control::Header("BAKE"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Bake the scene (summary prints to the log)"));
        Rows.Add(CkGym_Control::Cycle(EKeys::T, "T", "Draw mode", Get_ModeLabels()[_ModeIndex]));
        Rows.Add(CkGym_Control::Status("Colours", Get_ModeLegends()[_ModeIndex]));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Clear the drawing"));

        Rows.Add(CkGym_Control::Header("MERGE - how cells collapse into plates"));
        Rows.Add(CkGym_Control::Cycle(EKeys::F, "F", "Plane fit tolerance", Get_PlaneFitLabels()[_PlaneFitIndex]));
        Rows.Add(CkGym_Control::Cycle(EKeys::G, "G", "Normal cone", Get_NormalConeLabels()[_NormalConeIndex]));

        Rows.Add(CkGym_Control::Header("AGENT - what counts as walkable"));
        Rows.Add(CkGym_Control::Cycle(EKeys::N, "N", "Ledge sensitivity", Get_LedgeLabels()[_LedgeIndex]));
        Rows.Add(CkGym_Control::Cycle(EKeys::J, "J", "Step height", Get_StepHeightLabels()[_StepHeightIndex]));
        Rows.Add(CkGym_Control::Cycle(EKeys::M, "M", "Agent height", Get_AgentHeightLabels()[_AgentHeightIndex]));
        Rows.Add(CkGym_Control::Cycle(EKeys::L, "L", "Agent radius", Get_AgentRadiusLabels()[_AgentRadiusIndex]));

        Rows.Add(CkGym_Control::Header("LATTICE"));
        Rows.Add(CkGym_Control::Cycle(EKeys::K, "K", "Cell size", Get_CellSizeLabels()[_CellSizeIndex]));

        Rows.Add(CkGym_Control::Header("OTHER"));
        Rows.Add(CkGym_Control::Action(EKeys::P, "P", "Print every tunable to the log"));
        Rows.Add(CkGym_Control::Action(EKeys::O, "O", "Reset to the gym preset"));
        Rows.Add(CkGym_Control::Action(EKeys::V, "V", "Fly back to the starting viewpoint"));
        Rows.Add(CkGym_Control::Action(EKeys::Y, "Y",
            "Bake the scene as a TILED field (draw mode 5 shows the tiles and their seams; T and the tunables then re-bake the field until you press R)"));
        Rows.Add(CkGym_Control::Toggle(EKeys::X, "X",
            "Open-collision body (does NOT re-bake - press R or Y afterwards)", ck::IsValid(_OpenBodyActor)));

        // Every value here is read off the volume as the row is built, so the panel reports the links
        // the field actually carries rather than what this controller last asked for.
        Rows.Add(CkGym_Control::Header("LINKS - the deck to the north-west (its own volume, not the R bake)"));
        Rows.Add(CkGym_Control::Status("Field", Get_LinksFieldStatus(),
            utils_ground_nav_volume::Get_IsBuilt(_LinksVolume) == false));
        Rows.Add(CkGym_Control::Status("Drop / ladder", Get_LinksLiveStatus()));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::U, "U",
            "Links (ck.GroundNav.LinksAt 0 0 0 lists them; ck.GroundNav.Debug.Mode 7 draws them over a bake)",
            Get_LinksAreEnabled(), "enabled", "disabled"));

        return Rows;
    }

    private FString Get_LinksFieldStatus()
    {
        if (utils_ground_nav_volume::Get_IsBuilt(_LinksVolume) == false)
        { return _LinksStage; }

        const auto Tiles = utils_ground_nav_volume::Get_BuiltTileCount(_LinksVolume);

        return f"published - {Tiles} tiles - {_LinksStage}";
    }

    private FString Get_LinksLiveStatus()
    {
        const auto Records = utils_ground_nav_volume::Get_LinkRecords(_LinksVolume).Num();

        if (Records == 0)
        { return "nothing authored yet"; }

        const auto DropLive = utils_ground_nav_volume::Get_IsLinkLive(_LinksDropEntity);
        const auto LadderLive = utils_ground_nav_volume::Get_IsLinkLive(_LinksLadderEntity);
        const auto Unresolved = utils_ground_nav_volume::Get_UnresolvedLinkCount(_LinksVolume);

        return f"{Records} records - drop live: {DropLive} - ladder live: {LadderLive} - ends that found no ground: {Unresolved}";
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (HasAuthority() == false)
        { return; }

        if (InRowIndex == k_Row_Bake)
        {
            DoBake();
            return;
        }

        if (InRowIndex == k_Row_BakeField)
        {
            DoBakeField();
            return;
        }

        if (InRowIndex == k_Row_Mode)
        {
            _ModeIndex = (_ModeIndex + 1) % Get_ModeLabels().Num();
            DoRebake();
            return;
        }

        if (InRowIndex == k_Row_Clear)
        {
            System::ExecuteConsoleCommand("ck.GroundNav.Clear");
            return;
        }

        if (InRowIndex == k_Row_PlaneFit)
        {
            _PlaneFitIndex = (_PlaneFitIndex + 1) % Get_PlaneFitValues().Num();
            DoRebake();
            return;
        }

        if (InRowIndex == k_Row_NormalCone)
        {
            _NormalConeIndex = (_NormalConeIndex + 1) % Get_NormalConeValues().Num();
            DoRebake();
            return;
        }

        if (InRowIndex == k_Row_Ledge)
        {
            _LedgeIndex = (_LedgeIndex + 1) % Get_LedgeValues().Num();
            DoRebake();
            return;
        }

        if (InRowIndex == k_Row_StepHeight)
        {
            _StepHeightIndex = (_StepHeightIndex + 1) % Get_StepHeightValues().Num();
            DoRebake();
            return;
        }

        if (InRowIndex == k_Row_AgentHeight)
        {
            _AgentHeightIndex = (_AgentHeightIndex + 1) % Get_AgentHeightValues().Num();
            DoRebake();
            return;
        }

        if (InRowIndex == k_Row_AgentRadius)
        {
            _AgentRadiusIndex = (_AgentRadiusIndex + 1) % Get_AgentRadiusValues().Num();
            DoRebake();
            return;
        }

        if (InRowIndex == k_Row_CellSize)
        {
            _CellSizeIndex = (_CellSizeIndex + 1) % Get_CellSizeValues().Num();
            DoRebake();
            return;
        }

        if (InRowIndex == k_Row_Print)
        {
            System::ExecuteConsoleCommand("ck.GroundNav.Print");
            return;
        }

        if (InRowIndex == k_Row_Reset)
        {
            DoResetTunables();
            return;
        }

        if (InRowIndex == k_Row_Viewpoint)
        {
            DoBringPlayerToViewpoint();
            return;
        }

        if (InRowIndex == k_Row_OpenBody)
        {
            DoToggleOpenBody();
            return;
        }

        if (InRowIndex == k_Row_LinksToggle)
        {
            DoToggle_Links();
            return;
        }
    }

    private void DoResetTunables()
    {
        _ModeIndex = 0;
        _PlaneFitIndex = 1;
        _NormalConeIndex = 2;
        _LedgeIndex = 0;
        _StepHeightIndex = 2;
        _AgentHeightIndex = 1;
        _AgentRadiusIndex = 1;
        _CellSizeIndex = 1;

        DoBake();
        ck::groundnav::Log("GroundNav gym: tunables reset to the gym preset");
    }
}
