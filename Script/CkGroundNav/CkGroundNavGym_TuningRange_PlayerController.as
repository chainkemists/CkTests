class ACk_GroundNavGym_TuningRange_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- Where the scene stands ------------------------------------------------------------------
    //
    // Every dimension below is LOCAL to the scene, and the scene is placed off the station's own
    // footprint anchor rather than at a world constant: the station is placed by
    // Request_ApplyDefaultGridLayout, so a hardcoded world position is wrong the moment the grid
    // changes. Stations face world -X, so the scene is pushed into -X in front of the board.

    // Far enough into -X that the volume's own +X bound (scene-local 1400, below) still lands 300uu
    // short of the station's footprint, so the field is never baked over the board itself.
    private const FVector k_SceneOffset = FVector(-1700.0, 0.0, 0.0);

    // ---- Scene constants -------------------------------------------------------------------------
    //
    // Every dimension here is chosen so that ONE tunable decides what the bake does with it. The
    // riser is the clearest case: at 20uu it sits between the default plane-fit tolerance (10) and
    // the next value the panel offers (25), so a single keypress flips the staircase between twelve
    // plates and six.

    private const FVector k_FloorLocation = FVector(0.0, 0.0, 0.0);

    // Z scale must stay >= 0.5 - thinner slabs bake to zero walkable tiles. The walkable surface is
    // at the actor origin, so the slab hangs below the scene's Z 0.
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

    // 75uu wide, spanning scene-local Y 412.5..487.5 - four columns of the default 25uu lattice, two of
    // them half covered. Narrow enough that the ledge filter reaches its EDGE columns, which is the
    // only way to see what that filter costs.
    //
    // It does not erase the strip. DoFilter_Ledges counts a column's dropping sides among its four
    // neighbours in ONE pass and applies the demotions afterwards, with no erosion - so an edge column
    // has exactly one dropping side (the void outwards; the strip supports it inwards and along), and
    // the two inner columns have none at any sensitivity. At sensitivity 1.0 the strip narrows to its
    // middle 50uu; nothing below that touches it at all.
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

    // Frames the staircase, the platform and the catwalk in one shot from the scene's south-west.
    private const FVector  k_ViewOffset   = FVector(300.0, -900.0, 550.0);
    private const FRotator k_ViewRotation = FRotator(-22.0, 75.0, 0.0);

    // ---- The tuning volume the Verdict reads -----------------------------------------------------
    //
    // The R and Y bakes are a DEBUG picture: they are owned by the draw layer, no volume holds them,
    // and NOTHING about them is reflected - FCk_GroundNav_DebugSnapshot is a plain C++ struct that no
    // Utils class exposes. A verdict computed from live readbacks therefore cannot be computed from
    // them at all, so this gym mints one volume over the same scene and asks IT.
    //
    // THE VOLUME IS MINTED FROM THE SAME VALUES THE DEBUG BAKE READS. Every F/G/N/J/M/L/K keypress
    // pushes its value to the ck.GroundNav.Debug.* cvars AND re-mints this volume from that same
    // value, using the same arithmetic Make_BakeParams uses on the cvar side
    // (CkGroundNav_DebugDraw.cpp) - so the picture and the verdict are two readings of one bake
    // rather than two bakes wearing one panel. A verdict that stood still while the reader turned a
    // dial would be a row whose value does not move, which is the one thing a gym must never ship.
    //
    // Re-minting rather than editing: a volume's params are read once, at Add, and no request
    // re-authors them. FCkGroundNavGym_Field::Request_Remint destroys the volume entity and mints a
    // fresh one, which is why every tunable key spends a whole field build.

    // The +X bound stops at the platform's own far face (scene-local 1400) rather than reaching past
    // it: with the scene offset above, anything further would put the volume under the station's
    // footprint, and a bake that swallowed the board would be reporting on furniture.
    //
    // The MIN corner is also the LATTICE ORIGIN - the rasterizer indexes cells from the region's Min -
    // so its Y of -1400 is what puts cell boundaries on multiples of 25 in scene-local Y, which is what
    // the catwalk-edge probe below is placed against. Moving it moves the probe.
    private const FVector k_FieldBoundsMin = FVector(-1400.0, -1400.0, -150.0);
    private const FVector k_FieldBoundsMax = FVector(1400.0, 1400.0, 450.0);

    // Cell size, agent height, agent radius, step height, ledge sensitivity and both merge tunables
    // are NOT constants - they come off the panel's own value tables. What is left here is what no
    // key moves.
    private const float k_FieldCellHeightUu = 10.0f;
    private const float k_FieldTileSizeUu   = 500.0f;

    // Above this lattice the catwalk half of the verdict is reported and not judged: a 75uu strip is
    // 1.5 cells at 50uu and narrower than one cell at 100uu, so it has no distinguishable edge column
    // to probe, and what the ledge filter does to a strip that barely rasterizes is not a claim this
    // gym is in a position to make. BELOW it the same is true for the opposite reason - at 12.5uu the
    // strip is eight columns and the probe below would land in an interior one - so the catwalk half
    // is judged at this cell size and at no other.
    private const float k_CatwalkAssertableCellSizeUu = 25.0f;

    // 0.05s a poll, so this is thirty seconds of waiting on a NAMED condition before the field gives
    // up and says so in its own status row rather than hanging silently.
    private const int32 k_FieldSettlePollCeiling = 600;

    // The two ledge probes, five units above the surface each names.
    //
    // The catwalk probe stands on an EDGE COLUMN of the strip, and it has to: the ledge filter counts
    // dropping sides per column with no erosion, so the strip's two interior columns are supported on
    // all four sides at every sensitivity and a probe in the middle of the strip would read ground no
    // matter what N says - a row whose value never moves. The outer column at scene-local Y 400..425 is
    // the one the filter can reach; its centre is 412.5 and the X of 487.5 is likewise a cell centre,
    // so the probe sits 12.5uu clear of every neighbouring cell.
    //
    // The staircase's top tread is 600uu wide, so its CENTRE has no dropping side at all: the drops are
    // 300uu away at the Y edges and the platform meets it at the same height on +X. One filter, two
    // answers, and only one of them moves with N - which is what makes the pair a check rather than a
    // reading.
    private const FVector k_CatwalkProbe = FVector(487.5, 412.5, 245.0);
    private const FVector k_TopStepProbe = FVector(650.0, 0.0, 245.0);

    // Tight in Z on purpose. A generous vertical search reaches PAST the catwalk and answers with the
    // floor 240uu below it, which reads as a success and says nothing about the ledge filter.
    private const FVector k_ProbeHalfExtents = FVector(20.0, 20.0, 60.0);

    // The catwalk's own, tighter in the HORIZONTAL: the projection's search radius is the X component
    // alone (CkGroundNav_NavSurfaceAdapter::Get_HorizontalExtentUu) and it is measured to the nearest
    // point of each candidate cell, so anything from 12.5 up would reach the surviving interior column
    // next door and report the demoted edge column as ground. 10 reaches the probe's own cell and
    // nothing else.
    private const FVector k_CatwalkProbeHalfExtents = FVector(10.0, 10.0, 60.0);

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Header and Status rows never reach Request_ControlActivated but they DO occupy an index. These
    // constants sit next to each other so a row inserted in one place and not renumbered here is a
    // visible edit rather than a silent off-by-one.

    private const int32 k_Row_Bake        = 6;
    private const int32 k_Row_Mode        = 7;
    private const int32 k_Row_Clear       = 9;
    private const int32 k_Row_PlaneFit    = 11;
    private const int32 k_Row_NormalCone  = 12;
    private const int32 k_Row_Ledge       = 14;
    private const int32 k_Row_StepHeight  = 15;
    private const int32 k_Row_AgentHeight = 16;
    private const int32 k_Row_AgentRadius = 17;
    private const int32 k_Row_CellSize    = 19;
    private const int32 k_Row_Print       = 21;
    private const int32 k_Row_Reset       = 22;
    private const int32 k_Row_Viewpoint   = 23;
    private const int32 k_Row_BakeField   = 24;
    private const int32 k_Row_OpenBody    = 25;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FVector _Origin = FVector::ZeroVector;
    private bool _GeometryIsBuilt = false;
    private int32 _BakeCount = 0;

    // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and the scene boxes are spawned
    // actors that nothing here holds a handle to - so a second pass would stack a whole second scene
    // in the Jolt static world, on top of the first and invisible to every row. Spawned once per
    // controller, and the flag is the only thing that can say so.
    private bool _SceneSpawned = false;

    private FCkGroundNavGym_Field _Field;

    // The row reads this back rather than mirroring a bool: the actor IS the state, and a bool that
    // disagreed with it would report an open body the static world no longer holds.
    private AStaticMeshActor _OpenBodyActor = nullptr;

    // T and every tunable key re-run the bake so the drawing tracks the change. They re-run the KIND
    // of bake that last ran - region after R, tiled field after Y - because a region bake would
    // replace the field and mode 5 would then have no tiles to draw.
    private bool _LastBakeWasField = false;

    // Where the last bake was aimed. Remembered because the region row would otherwise go on naming
    // a box that had moved.
    private FVector _LastBakeCentre = FVector::ZeroVector;

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
    // The gym owns these values and pushes them to the cvars; it never reads them back, because there
    // is nothing to read them back with: AngelScript is bound no console-variable READER at all - the
    // CVar utility exposes Make_CVarRef and IsRegistered and no getter of any type. Typing a value
    // straight into the console still works and still takes effect; the panel just will not know
    // about it until the next keypress pushes the gym value over the top.

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
        Labels.Add("1.0 - one dropping side (the catwalk loses its edge columns)");
        Labels.Add("0.5 - two dropping sides (the catwalk is whole again)");
        Labels.Add("0.34 - three dropping sides");
        Labels.Add("off - nothing is demoted");
        return Labels;
    }

    // How many of a span's four sides must drop away before the ledge filter demotes it, one entry
    // per sensitivity above. Mirrors Get_RequiredDroppingSides in CkGroundNav_Walkability.cpp:
    // ceil(1 / sensitivity) clamped to 1..4, with zero disabling the filter by demanding more sides
    // than a span has. Written as a table rather than computed because AngelScript binds no
    // FMath::CeilToInt, and because four numbers beside four labels are checkable by eye.
    //
    // This is what the verdict's catwalk expectation is derived from, and the count it is compared
    // against is ONE, not two. The filter is per COLUMN, not per strip: the probed edge column of the
    // catwalk is supported inwards by the strip and along the strip in both X directions, and drops
    // only outwards - so it is demoted while this table says 1 and stands at everything above it.
    private TArray<int32> Get_LedgeRequiredSides()
    {
        auto Sides = TArray<int32>();
        Sides.Add(1);
        Sides.Add(2);
        Sides.Add(3);
        Sides.Add(5);
        return Sides;
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

        // No Transform: the base grid places it, and the scene is built off the anchor it lands on.
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavTuningRange");
        Station.AutoSize = true;
        Station.Title = FText::FromString("GroundNav - Tuning Range");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("A scene built so that each part of it is decided by exactly one bake tunable. Press R to bake it and read the summary that prints to the log; every other key changes a value and re-bakes."));
        Description.Add(FText::FromString("The VERDICT row at the top of the panel is not read off the R bake - the debug bake is a picture nothing can be asked about. It is read off a volume this gym mints over the same scene, from the same values every key below pushes to the debug bake. Each keypress re-mints it, so the verdict names the profile it actually evaluated - and it reads 'verdict pending' rather than a colour while that re-mint is still publishing."));
        Description.Add(FText::FromString("The staircase has 20uu risers. At the default plane-fit tolerance of 10uu you get one plate per tread; press F once to raise it past 20 and the treads merge into ramps. Watch the worst height spread in the summary - when it reaches 20 the steps have stopped existing."));
        Description.Add(FText::FromString("The platform leaves 220uu of headroom over the floor, so the region reports two layers. Raise the agent height past 220 with M and the floor beneath it is culled, dropping the count to one."));
        Description.Add(FText::FromString("The catwalk is 75uu wide and drops 240uu on both sides, which is four columns of the 25uu lattice. The ledge filter counts dropping sides per COLUMN and demotes nothing else, so it reaches the strip's two EDGE columns - each of which drops on exactly one side - and never its middle. Draw mode 3 shows what it removed: at sensitivity 1.0 the strip's outer columns go red and it narrows rather than vanishing. Press N once to 0.5 and they come back, because two dropping sides are then demanded and an edge column only has one."));
        Description.Add(FText::FromString("Draw mode 4 shows the crossings between plates. The two pillars stand 160uu apart, so the crossing through the gap between them offers about 80uu - that number, not the open floor either side of it, is what decides whether a body can get through."));
        Description.Add(FText::FromString("Fail signatures: status BackendUnavailable = no Jolt static world in this PIE mode; NoGeometryInRegion = the scene did not bake into Jolt, or the pawn drifted outside the region."));
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
            ck::groundnav::Warning("GroundNav tuning gym: PC entity invalid; cannot start");
            return;
        }

        _Origin = Get_StationAnchorLocation("GroundNavTuningRange", ECk_GymStation_Anchor::FootprintCenter);
        _LastBakeCentre = Get_ScenePoint(k_BakeCentre);

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav tuning gym: the scene failed to bake into the Jolt static world - every bake will report NoGeometryInRegion", n"GroundNavGym.Scene", 10.0);
        }

        DoPushAllTunables();

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        DoArm_Field();

        ck::groundnav::Log("GroundNav tuning gym: scene built - press R to bake");
    }

    // Scene-local to world. Everything the gym spawns, bakes and probes goes through here, so the
    // scene is one translation away from the station the grid layout happened to place.
    private FVector Get_ScenePoint(FVector InLocal)
    {
        return _Origin + k_SceneOffset + InLocal;
    }

    // ---- The tuning volume -------------------------------------------------------------------------

    // The lattice the volume bakes on, assembled from the panel's CURRENT cell size (K). Cell height
    // and tile size are not on any key, so they stay authored.
    private FCk_GroundNav_BakeConfig Get_FieldConfig()
    {
        auto Config = FCk_GroundNav_BakeConfig(Get_CellSizeValues()[_CellSizeIndex], k_FieldCellHeightUu);
        Config.Set_TileSizeUu(k_FieldTileSizeUu);
        return Config;
    }

    // The walker the volume bakes for, assembled from M (agent height), L (agent radius), J (step
    // height) and N (ledge sensitivity) - the same four the debug bake reads off its cvars.
    //
    // The capsule arithmetic is Make_BakeParams's, not a second opinion: half-height is
    // (agent height / 2) - radius, so a 180uu agent with a 34uu radius stands 180uu tall. The panel
    // offers combinations where that comes out negative (120uu tall on a 90uu radius); the debug bake
    // hands the identical capsule to the identical admission check, so the two of them are refused
    // together rather than disagreeing about the same keypress.
    private FCk_GroundNav_AgentProfile Get_FieldProfile()
    {
        const auto AgentHeightUu = Get_AgentHeightValues()[_AgentHeightIndex];
        const auto AgentRadiusUu = Get_AgentRadiusValues()[_AgentRadiusIndex];

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions((AgentHeightUu * 0.5f) - AgentRadiusUu, AgentRadiusUu)));

        Profile.Set_StepHeightUu(Get_StepHeightValues()[_StepHeightIndex]);
        Profile.Set_LedgeSensitivity(Get_LedgeValues()[_LedgeIndex]);

        return Profile;
    }

    // F and G, the two the volume takes as params rather than as profile fields.
    private FCk_GroundNav_MergeTunables Get_FieldMergeTunables()
    {
        return FCk_GroundNav_MergeTunables(
            Get_PlaneFitValues()[_PlaneFitIndex],
            Get_NormalConeValues()[_NormalConeIndex]);
    }

    private void DoArm_Field()
    {
        if (_GeometryIsBuilt == false)
        {
            _Field.Set_Stage("the scene is not in the Jolt static world - nothing to bake over");
            return;
        }

        const auto Bounds = FBox(Get_ScenePoint(k_FieldBoundsMin), Get_ScenePoint(k_FieldBoundsMax));

        _Field.Set_MergeTunables(Get_FieldMergeTunables());

        _Field.Request_Mint(_PcEntity, n"GroundNavGym_TuningField", Bounds,
            Get_FieldConfig(), Get_FieldProfile(),
            NAME_None, k_FieldSettlePollCeiling,
            FCk_Delegate_Request_OnCompleted(this, n"OnFieldBuildCompleted"),
            FCk_Delegate_Timer(this, n"OnFieldSettlePoll"));
    }

    // Destroys the volume and mints a fresh one from whatever the tunables now say. Called from
    // EVERY path that re-bakes the picture - R, Y, and each of the F/G/N/J/M/L/K keys - because the
    // gym's contract is that the tunables re-bake the field, and a volume the keys could not reach
    // would leave the verdict describing a profile nobody selected.
    private void DoRemintField()
    {
        if (_GeometryIsBuilt == false)
        { return; }

        const auto Bounds = FBox(Get_ScenePoint(k_FieldBoundsMin), Get_ScenePoint(k_FieldBoundsMax));

        _Field.Set_MergeTunables(Get_FieldMergeTunables());

        _Field.Request_Remint(_PcEntity, n"GroundNavGym_TuningField", Bounds,
            Get_FieldConfig(), Get_FieldProfile(),
            NAME_None, k_FieldSettlePollCeiling,
            FCk_Delegate_Request_OnCompleted(this, n"OnFieldBuildCompleted"),
            FCk_Delegate_Timer(this, n"OnFieldSettlePoll"));
    }

    UFUNCTION()
    private void OnFieldSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Step = _Field.Do_PollSettle();

        if (Step == ECkGroundNavGym_Settle::GaveUp)
        { ck::groundnav::Log("GroundNav tuning gym: the tuning field never settled - the verdict has nothing to read"); }
    }

    UFUNCTION()
    private void OnFieldBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Field.Notify_BuildCompleted(InResult);
    }

    // ---- The verdict -------------------------------------------------------------------------------
    //
    // Every criterion is a LIVE readback, and there is no mirrored member behind any of them: the
    // build result is the volume's own answer to the request this gym made, the counts are asked of
    // the volume as the row is built, and both ledge answers come from the provider-neutral facade.
    //
    // PLATES are deliberately absent from the OK text. A plate total is not among the volume's
    // reflected counts - the only place one is printed is ck.GroundNav.Print, over the debug field,
    // which is a different field from this one. Seam portals are what the volume itself will answer.

    // The two facade probes are run ONCE, by the panel, and handed to both halves below - so the row
    // colours itself from the same evaluation it prints rather than asking the surface twice a frame
    // and hoping the two answers agree.
    private ECk_NavSurface_QueryStatus Get_CatwalkStatus()
    {
        return CkGroundNavGym::Get_ProjectedStatus(Get_ScenePoint(k_CatwalkProbe), k_CatwalkProbeHalfExtents);
    }

    private ECk_NavSurface_QueryStatus Get_TopStepStatus()
    {
        return CkGroundNavGym::Get_ProjectedStatus(Get_ScenePoint(k_TopStepProbe), k_ProbeHalfExtents);
    }

    private TArray<FString> Get_VerdictFailures(
        ECk_NavSurface_QueryStatus InCatwalkStatus,
        ECk_NavSurface_QueryStatus InTopStepStatus)
    {
        auto Failures = TArray<FString>();

        // BUILT IS NOT ENOUGH. A re-mint destroys the old volume and asks for a new bake, and between
        // the new field publishing and the surface going quiet every probe below is answered by the
        // field that WAS. Judging in that window would fail the gym on its own re-mint, once per
        // keypress, so the verdict is withheld until both are true.
        if (Get_VerdictIsPending())
        { return Failures; }

        const auto BuildResult = _Field.Get_LastBuildResult();

        if (BuildResult != ECk_Request_OperationResult::Succeeded)
        { Failures.Add(f"the last build reported {BuildResult}"); }

        if (_Field.Get_WalkableCellCount() <= 0)
        { Failures.Add("the field published 0 walkable cells"); }

        // Asserted at every setting the panel offers. The top tread's centre has no dropping side, so
        // no sensitivity can demote it: if it stopped being ground, the ledge filter reached ground
        // it has no business touching.
        if (InTopStepStatus != ECk_NavSurface_QueryStatus::Success)
        { Failures.Add(f"the staircase top step is not ground ({InTopStepStatus}) - the ledge filter took the stairs with the catwalk"); }

        // The catwalk half MOVES WITH N, which is exactly why the volume is re-minted on every
        // keypress. ONE dropping side, because the probed column is an EDGE of the strip and the filter
        // is per column: demoted while the filter asks for one, standing once it asks for two or more.
        // A fixed "the catwalk must not be ground" would have gone red the moment a reader pressed N,
        // and reported a working filter as broken.
        //
        // Only at the lattice the probe was placed against: at any other cell size the column under it
        // is a different fraction of the strip, and it may not be an edge column at all.
        if (Get_CellSizeValues()[_CellSizeIndex] != k_CatwalkAssertableCellSizeUu)
        { return Failures; }

        const auto CatwalkIsGround = InCatwalkStatus == ECk_NavSurface_QueryStatus::Success;
        const auto RequiredSides = Get_LedgeRequiredSides()[_LedgeIndex];
        const auto LedgeValue = Get_LedgeValues()[_LedgeIndex];

        if (RequiredSides <= 1 && CatwalkIsGround)
        { Failures.Add(f"the catwalk's edge column is still ground at ledge {LedgeValue} - the filter demotes at {RequiredSides} dropping side and that column drops on one"); }

        if (RequiredSides > 1 && CatwalkIsGround == false)
        { Failures.Add(f"the catwalk's edge column is not ground ({InCatwalkStatus}) at ledge {LedgeValue} - the filter needs {RequiredSides} dropping sides and that column drops on only one"); }

        return Failures;
    }

    // Built AND quiet. The two are separate facts and the verdict needs both: the volume's built flag
    // says a field is published, and the surface's settle says nothing is still in flight on top of it.
    // Neither is mirrored - both are asked as the row is built.
    private bool Get_VerdictIsPending()
    {
        return _Field.Get_IsBuilt() == false || _Field.Get_IsSettled() == false;
    }

    private FString Get_VerdictLine(
        ECk_NavSurface_QueryStatus InCatwalkStatus,
        ECk_NavSurface_QueryStatus InTopStepStatus,
        const TArray<FString>&in InFailures)
    {
        if (_Field.Get_IsBuilt() == false)
        { return "not baked yet"; }

        // NOT a FAIL. Every keypress here re-mints the volume, so this is the state the row is in for
        // the second or two after each one - painting it red would report the gym's own re-bake as a
        // broken filter.
        if (_Field.Get_IsSettled() == false)
        { return "field building - verdict pending"; }

        const auto Cells = _Field.Get_WalkableCellCount();
        const auto Seams = _Field.Get_SeamPortalCount();
        const auto LedgeValue = Get_LedgeValues()[_LedgeIndex];

        // The ledge value is NAMED in the OK line so the verdict says which profile it evaluated. A
        // reader pressing N sees the number here change with the label above it; a verdict that
        // printed the same sentence at every setting would be indistinguishable from one that never
        // re-baked at all.
        FString CatwalkWord = "not ground";
        if (InCatwalkStatus == ECk_NavSurface_QueryStatus::Success)
        { CatwalkWord = "ground"; }

        FString TopStepWord = "not ground";
        if (InTopStepStatus == ECk_NavSurface_QueryStatus::Success)
        { TopStepWord = "ground"; }

        return CkGroundNavGym::Get_VerdictText(
            f"OK - ledge {LedgeValue}: catwalk {CatwalkWord}, top step {TopStepWord} - {Cells} walkable cells, {Seams} seam portals",
            InFailures);
    }

    // ---- Scene construction ----------------------------------------------------------------------

    private bool DoBuildScene()
    {
        // Guarded, not idempotent by luck: see _SceneSpawned. A restart keeps the scene it already
        // spawned, which is also the scene the volume below was baked over.
        if (_SceneSpawned)
        { return true; }

        _SceneSpawned = true;

        if (CkGroundNavGym::Spawn_Floor(Get_ScenePoint(k_FloorLocation), k_FloorScale) == nullptr)
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

        return true;
    }

    private bool DoSpawnBox(FVector InLocalCentre, FVector InScale)
    {
        return CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(InLocalCentre), InScale);
    }

    // Scaled from the asset's own bounds rather than a hardcoded number: the mesh is an engine sheet
    // whose authored size is not ours to assume, and a sheet baked at the wrong size is either
    // invisible or covers the scene.
    private bool DoSpawnOpenBody()
    {
        auto SheetActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, Get_ScenePoint(k_OpenBodyCentre)));
        if (ck::Is_NOT_Valid(SheetActor))
        {
            ck::groundnav::Warning("GroundNav tuning gym: failed to spawn the open-collision body");
            return false;
        }

        SheetActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);

        auto SheetMesh = Cast<UStaticMesh>(LoadObject(this, k_OpenBodyMeshPath));
        if (SheetMesh == nullptr)
        {
            ck::groundnav::Warning("GroundNav tuning gym: failed to load the open-collision sheet mesh");
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
            ck::groundnav::Warning("GroundNav tuning gym: the open-collision sheet mesh has no width to scale from");
            SheetActor.DestroyActor();
            return false;
        }

        const auto SheetScale = k_OpenBodyWidthUu / LocalWidthUu;
        SheetActor.SetActorScale3D(FVector(SheetScale, SheetScale, 1.0));
        SheetActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(SheetActor);
        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav tuning gym: the open-collision body baked 0 Jolt bodies - the bake would never see it");
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
            ck::groundnav::Log("GroundNav tuning gym: open-collision body removed - press R or Y to bake again");
            return;
        }

        if (DoSpawnOpenBody() == false)
        { return; }

        ck::groundnav::Log("GroundNav tuning gym: open-collision body added - press R or Y to bake again and read the OPEN COLLISION block");
    }

    private void DoBringPlayerToViewpoint()
    {
        CkGroundNavGym::Request_FlyToStation(this, "GroundNavTuningRange",
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

    // ---- Tunable plumbing ------------------------------------------------------------------------

    // Pushes the whole set rather than just the one that changed, so the cvars and the panel always
    // agree from the first keypress even if something else wrote them earlier in the session.
    private void DoPushAllTunables()
    {
        // Sized to the scene rather than to the viewer: it spans X -1200..1400 and Y +/-1200, and
        // everything walkable in it sits between Z=0 and Z=240. An extent that swallowed the whole
        // world would truncate the drawing long before it bought anything.
        CkGroundNavGym::Set_DebugTunable("ExtentUu", 1500.0f);
        CkGroundNavGym::Set_DebugTunable("HeightUu", 400.0f);
        CkGroundNavGym::Set_DebugTunable("MaxCells", 40000.0f);

        CkGroundNavGym::Set_DebugTunable("Mode", float(_ModeIndex));
        CkGroundNavGym::Set_DebugTunable("PlaneFitToleranceUu", Get_PlaneFitValues()[_PlaneFitIndex]);
        CkGroundNavGym::Set_DebugTunable("NormalConeDegrees", Get_NormalConeValues()[_NormalConeIndex]);
        CkGroundNavGym::Set_DebugTunable("LedgeSensitivity", Get_LedgeValues()[_LedgeIndex]);
        CkGroundNavGym::Set_DebugTunable("StepHeightUu", Get_StepHeightValues()[_StepHeightIndex]);
        CkGroundNavGym::Set_DebugTunable("AgentHeightUu", Get_AgentHeightValues()[_AgentHeightIndex]);
        CkGroundNavGym::Set_DebugTunable("AgentRadiusUu", Get_AgentRadiusValues()[_AgentRadiusIndex]);
        CkGroundNavGym::Set_DebugTunable("CellSizeUu", Get_CellSizeValues()[_CellSizeIndex]);
    }

    private void DoBake()
    {
        DoBakeAt(Get_ScenePoint(k_BakeCentre));

        // R is "read the world again", so it re-mints the volume too - otherwise the open-collision
        // toggle would change the picture and leave the verdict describing the scene as it was.
        DoRemintField();
    }

    private void DoBakeAt(FVector InCentre)
    {
        DoPushAllTunables();
        System::ExecuteConsoleCommand("ck.GroundNav.Clear");
        System::ExecuteConsoleCommand(
            f"ck.GroundNav.BakeAt {InCentre.X} {InCentre.Y} {InCentre.Z}");
        _BakeCount += 1;
        _LastBakeWasField = false;
        _LastBakeCentre = InCentre;
    }

    // The same scene baked as several tiles instead of one region. Everything else is identical, so
    // the two runs are directly comparable - which is the point: a tiled bake that disagreed with the
    // whole one would show up here as a seam, and nowhere else.
    private void DoBakeField()
    {
        DoBakeFieldAt(Get_ScenePoint(k_BakeCentre));
        DoRemintField();
    }

    private void DoBakeFieldAt(FVector InCentre)
    {
        DoPushAllTunables();
        CkGroundNavGym::Set_DebugTunable("TileSizeUu", k_FieldTileSizeUu);
        System::ExecuteConsoleCommand("ck.GroundNav.Clear");
        System::ExecuteConsoleCommand(
            f"ck.GroundNav.BakeFieldAt {InCentre.X} {InCentre.Y} {InCentre.Z}");
        _BakeCount += 1;
        _LastBakeWasField = true;
        _LastBakeCentre = InCentre;
    }

    // Re-runs the KIND of bake that last ran and re-aims it WHERE that one was aimed. A region bake
    // would replace the field mode 5 draws from, which is why the kind is remembered.
    //
    // The volume IS re-minted with it. A tunable cannot be pushed into a standing volume - params are
    // read once, at Add - so the only way the verdict tracks the panel is a fresh mint per keypress,
    // and that cost is the price of the two halves agreeing. T is in here too and re-mints for
    // nothing (a draw mode changes no bake input), which is the honest cost of one path rather than
    // two subtly different ones.
    private void DoRebake()
    {
        if (_LastBakeWasField)
        {
            DoBakeFieldAt(_LastBakeCentre);
            DoRemintField();
            return;
        }

        DoBakeAt(_LastBakeCentre);
        DoRemintField();
    }

    // ---- Control panel ---------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GROUNDNAV: TUNING RANGE";
    }

    // Readback: every value column below is asked for as the row is built, except where there is
    // nothing to ask. Three columns are remembered rather than read, and each says so where it
    // stands: the tunable cycles (no AngelScript console-variable reader exists - see the value
    // tables above), and how many bakes have run and where the last one was aimed (the gym is the
    // only thing that counts them). None of the three feeds the Verdict.
    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        // Probed once here, then handed to both halves of the verdict.
        const auto CatwalkStatus = Get_CatwalkStatus();
        const auto TopStepStatus = Get_TopStepStatus();

        const auto VerdictFailures = Get_VerdictFailures(CatwalkStatus, TopStepStatus);

        Rows.Add(CkGym_Control::Header("SCENE"));
        Rows.Add(CkGym_Control::Status("Verdict",
            Get_VerdictLine(CatwalkStatus, TopStepStatus, VerdictFailures), VerdictFailures.Num() > 0));
        Rows.Add(CkGym_Control::Status("Geometry",
            CkGroundNavGym::Get_GeometryStatusText(_GeometryIsBuilt,
                "floor + 12 steps (20uu risers) + platform + 75uu catwalk + 160uu pinch"),
            _GeometryIsBuilt == false));
        Rows.Add(CkGym_Control::Status("Bake region",
        f"white box around ({_LastBakeCentre.X}, {_LastBakeCentre.Y}, {_LastBakeCentre.Z}), +/-1500uu wide, 400uu tall - it is pinned where the bake was aimed and does not follow you"));
        Rows.Add(CkGym_Control::Status("Bakes run", f"{_BakeCount}"));

        Rows.Add(CkGym_Control::Header("BAKE"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Bake the scene (summary prints to the log; also re-mints the tuning volume)"));
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

        // The volume the Verdict is read off, shown so the verdict is auditable rather than oracular.
        // It is minted from the same values the keys above push to the debug bake, and re-minted on
        // every one of them - so this row going back to "baking" after a keypress IS the evidence
        // that the verdict tracked the change rather than describing the previous profile.
        Rows.Add(CkGym_Control::Header("FIELD - the volume the Verdict reads (re-minted by every key above)"));
        Rows.Add(CkGym_Control::Status("Field", _Field.Get_FieldStatusText(), _Field.Get_IsBuilt() == false));
        Rows.Add(CkGym_Control::Status("Surface", CkGroundNavGym::Get_SurfaceStatusText()));

        return Rows;
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
        ck::groundnav::Log("GroundNav tuning gym: tunables reset to the gym preset");
    }
}
