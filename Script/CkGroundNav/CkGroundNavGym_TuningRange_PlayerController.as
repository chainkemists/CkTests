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

    // ---- Range stations ---------------------------------------------------------------------------
    //
    // Five stations on ONE slab south of the floor, each in its own 600uu Y band, and all served by a
    // second volume this controller mints for them. They are on a volume for the same reason the links
    // deck is: a repair, a paint and a walked route are all asked OF a volume, and the R/Y bake is a
    // debug picture that no volume holds.
    //
    // The slab is 200uu clear of the floor in Y rather than joined to it. That gap is deliberate: the
    // range is its own ground, so a walker released on it can never wander into the tuning scene, and
    // a bake aimed at one never picks up the other.

    // Top face at Z=0, flush with the floor. X -1600..1600, Y -3800..-1400.
    private const FVector k_RangeSlabCentre = FVector(0.0, -2600.0, -100.0);
    private const FVector k_RangeSlabScale  = FVector(32.0, 24.0, 2.0);

    // The RAMP band. Two planks in series, 200uu along the slope and 400uu wide, pitched either side
    // of the default profile's 45-degree slope limit: the lower one at 40 degrees is walkable and the
    // upper one at 50 is not, so the ramp stops being ground half way up rather than at its foot.
    //
    // Each centre is the plank's foot plus half its length along (cos(pitch), 0, sin(pitch)):
    //   lower foot (-1400, 0)       + 100 * (0.766, 0.643) -> (-1323.4,  64.3), head (-1246.8, 128.6)
    //   upper foot (-1246.8, 128.6) + 100 * (0.643, 0.766) -> (-1182.5, 205.2), head (-1118.2, 281.8)
    //
    // The whole ramp tops out under 300uu on purpose: the panel's own bake region is 400uu tall around
    // Z 120, so a debug bake aimed at this band shows the ramp whole rather than clipping its head and
    // leaving the reader unable to tell a rejected plank from one outside the region.
    private const float k_RampLowerPitchDegrees = 40.0f;
    private const float k_RampUpperPitchDegrees = 50.0f;
    private const FVector k_RampLowerCentre = FVector(-1323.4, -1700.0, 64.3);
    private const FVector k_RampUpperCentre = FVector(-1182.5, -1700.0, 205.2);
    private const FVector k_RampPlankScale  = FVector(2.0, 4.0, 0.4);

    // The MOVED OBSTACLE band. 400uu square, 300uu tall, standing on the slab; the nudge row swaps it
    // between the two positions, which are one 800uu tile apart.
    private const FVector k_ObstacleHomeCentre  = FVector(-400.0, -2300.0, 150.0);
    private const FVector k_ObstacleMovedCentre = FVector(400.0, -2300.0, 150.0);
    private const FVector k_ObstacleScale       = FVector(4.0, 4.0, 3.0);

    // The ground a nudge leaves untrustworthy: the UNION of both footprints, grown by 100uu on every
    // side so the repair opens clear of the body's own edge rather than exactly along it.
    private const FVector k_ObstacleDirtyMin = FVector(-700.0, -2600.0, -100.0);
    private const FVector k_ObstacleDirtyMax = FVector(700.0, -2000.0, 400.0);

    // The PAINTED MARKUP band, which is also the crowd walkers' corridor: the paint lands across the
    // middle of the route the walkers are already on, so what it does to them is visible without
    // having to go and look for it.
    private const FVector k_MarkupCentre      = FVector(0.0, -2900.0, 100.0);
    private const FVector k_MarkupHalfExtents = FVector(250.0, 250.0, 200.0);

    private const FVector k_WalkerWestPoint = FVector(-1400.0, -2900.0, 100.0);
    private const FVector k_WalkerEastPoint = FVector(1400.0, -2900.0, 100.0);
    private const float   k_WalkerRadiusUu  = 34.0f;
    private const float   k_WalkerHeightUu  = 180.0f;

    // Spread across the corridor rather than stacked on one point: eight bodies born inside each other
    // spend their first seconds pushing apart, which is avoidance and says nothing about routing.
    private const float k_WalkerSpacingUu = 90.0f;

    // The MULTI-TILE CROSSING band. 2800uu end to end over 800uu tiles, so four tiles lie under one
    // corridor and a route that disagreed with itself across a seam would show here.
    private const FVector k_CrossingWestPoint  = FVector(-1400.0, -3500.0, 20.0);
    private const FVector k_CrossingEastPoint  = FVector(1400.0, -3500.0, 20.0);
    private const FVector k_CrossingBakeCentre = FVector(0.0, -3500.0, 120.0);

    // The NO-ROUTE POCKET. 600uu square with 300uu of nothing between it and the slab's south edge: no
    // seam can span a gap with no ground in it, and nothing authors a link across it, so the island is
    // baked ground that no route can reach.
    private const FVector k_PocketCentre     = FVector(0.0, -4400.0, -100.0);
    private const FVector k_PocketScale      = FVector(6.0, 6.0, 2.0);
    private const FVector k_PocketProbeStart = FVector(0.0, -3600.0, 100.0);
    private const FVector k_PocketProbeGoal  = FVector(0.0, -4400.0, 100.0);

    // The slab, everything standing on it, and the pocket beside it - and nothing from the tuning
    // scene, whose nearest ground stops at Y -1200.
    private const FVector k_RangeVolumeMin = FVector(-1800.0, -4900.0, -300.0);
    private const FVector k_RangeVolumeMax = FVector(1800.0, -1300.0, 500.0);

    // The same 25uu lattice the links deck bakes on, so the two volumes are directly comparable, and
    // fine enough that the ramp's shorter plank is still several cells of slope rather than one. The
    // 800uu tiles are what put four tiles under the crossing station's route. The agent is the default
    // 34uu body at 180uu standing height.
    private const float k_RangeCellSizeUu        = 25.0f;
    private const float k_RangeCellHeightUu      = 10.0f;
    private const float k_RangeTileSizeUu        = 800.0f;
    private const float k_RangeAgentRadiusUu     = 34.0f;
    private const float k_RangeAgentHalfHeightUu = 90.0f;

    // 0.05s a poll, and the range carries several times the tiles the links deck does, so it is given
    // a minute on the same NAMED condition before it reports that it gave up.
    private const int32 k_RangeSettlePollCeiling = 1200;

    // What the crowd row offers. Zero is a state worth having: it is how the corridor reads with
    // nothing standing on it.
    private const int32 k_WalkerCountLow  = 1;
    private const int32 k_WalkerCountHigh = 8;

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

    // The RANGE section sits between the links toggle and the link RESOLUTION rows, and that is not a
    // preference either: the resolution rows vary in number with what the volume holds, so any keyed
    // row placed after them would move between frames.
    private const int32 k_Row_Provider      = 32;
    private const int32 k_Row_PaintMarkup   = 34;
    private const int32 k_Row_NudgeObstacle = 35;
    private const int32 k_Row_Repair        = 37;
    private const int32 k_Row_Walkers       = 38;
    private const int32 k_Row_PathDraw      = 40;
    private const int32 k_Row_PocketProbe   = 41;

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

    // The batch's own completion. ONE delegate for both links, which is the only thing the batch
    // adds over two single requests - the drain takes the whole queue in a pass and the derive tag
    // is idempotent, so two singles landing in one tick already cost exactly one derive.
    private int32 _LinksBatchCompletions = 0;
    private ECk_Request_OperationResult _LastLinksBatchResult = ECk_Request_OperationResult::Failed;

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

    // Where the last bake was aimed. R keeps it on the scene; the crossing row aims a field bake at
    // its own band instead, and the region row would otherwise go on naming a box that had moved.
    private FVector _LastBakeCentre = FVector(200.0, 0.0, 120.0);

    private int32 _ModeIndex = 0;
    private int32 _PlaneFitIndex = 1;
    private int32 _NormalConeIndex = 2;
    private int32 _LedgeIndex = 0;
    private int32 _StepHeightIndex = 2;
    private int32 _AgentHeightIndex = 1;
    private int32 _AgentRadiusIndex = 1;
    private int32 _CellSizeIndex = 1;

    // ---- Range station state ----------------------------------------------------------------------

    private FCk_Handle _RangeVolumeEntity;
    private FCk_Handle_GroundNavVolume _RangeVolume;
    private FCk_Handle_Timer _RangeSettleTimer;

    private bool _RangeArmed = false;
    private int32 _RangeSettlePolls = 0;

    // The one thing about the range with no readback: what it is waiting on. Everything else the
    // section reports - epoch, tiles, walkable cells, seams, health, revision - is asked for as the
    // row is built.
    private FString _RangeStage = "not started";

    // The actor IS the obstacle's position, so the row reads it off the actor rather than mirroring
    // it. What is NOT readable is whether a nudge is still owed a repair: the volume's own
    // pending-dirty answer is C++ only, so the owing is remembered here and cleared by the repair's
    // own completion rather than by a guess.
    private AStaticMeshActor _ObstacleActor = nullptr;
    private bool _ObstacleIsMoved = false;
    private bool _ObstacleRepairOwed = false;

    private int32 _RepairsRun = 0;
    private ECk_Request_OperationResult _LastRepairResult = ECk_Request_OperationResult::Failed;

    private FCk_Handle_NavSurfaceMarkup _RangeMarkup;

    private TArray<FCk_Handle> _WalkerEntities;
    private TArray<FCk_Handle_CrowdAgent> _Walkers;
    private int32 _WalkerCountIndex = 0;

    // Nothing outside this gym holds this. ck.GroundNav.PathAt is a COMMAND, not a cvar, so there is
    // no console state saying whether a crossing route is on screen - only the fact that every other
    // bake clears the drawing, which is what puts this back to false.
    private bool _PathDrawEnabled = false;

    private FCk_Handle _PocketProbeEntity;
    private int32 _PocketProbesRun = 0;

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
        LinksDescription.Add(FText::FromString("Under the toggle there is one RESOLUTION row per link, straight from Get_LinkResolution: what each end projected onto, the flat plate it landed in, and whether the record resolved and is live. Every index in it is valid only against the field currently published, which is why the row is rebuilt each frame rather than remembered."));
        LinksDescription.Add(FText::FromString("The per-agent VETO - a body that may not take a link by id, or may not take ladders by the link's user-type tag - has no toggle here: this station owns no crowd agent to carry the params, and a veto with nobody to apply it to would show nothing. It is exercised by the autotest CkAutoTest_GroundNav_Link_VetoRoutesAroundForThatAgentOnly instead."));
        LinksDescription.Add(FText::FromString("The ladder is priced at twice its own straight-line span and narrowed to 40uu of clearance; the drop is priced at its span and admits any agent. A link never costs less than its own length - that is what keeps the search's Euclidean heuristic admissible."));
        LinksStation.Description = LinksDescription;

        Stations.Add(LinksStation);

        // The range stations. Each board stands at X 2000, east of the range slab and clear of the
        // volume, on the Y of the band it names and turned to face back across it - so reading a
        // board and looking at what it describes is one move rather than two.

        auto RampStation = FCkGym_Station_SpawnParams_Payload();
        RampStation.Tags.Add(n"GroundNavRamp");
        RampStation.AutoSize = true;
        RampStation.Transform = FTransform(FRotator(0.0, 180.0, 0.0), FVector(2000.0, -1700.0, 0.0), FVector::OneVector);
        RampStation.Title = FText::FromString("GroundNav - Ramp");

        auto RampDescription = TArray<FText>();
        RampDescription.Add(FText::FromString("Two planks in series climbing west to east: the lower at 40 degrees, the upper at 50. The range volume's agent profile keeps the default 45-degree slope limit, so the join between them is where the ramp stops being ground."));
        RampDescription.Add(FText::FromString("Type ck.GroundNav.Debug.Mode 3 and then ck.GroundNav.BakeFieldAt -1250 -1700 120 to see it as the filters do: the lower plank survives, the upper one is red. The debug bake's own slope limit defaults to the same 45 degrees the volume's profile carries, so the two agree until you move one."));
        RampDescription.Add(FText::FromString("The panel's F/G/N/J/M/L/K keys move the DEBUG bake's tunables and not this volume's profile. The volume was authored once, at startup, and only a repair or a rebuild changes what it published."));
        RampStation.Description = RampDescription;

        Stations.Add(RampStation);

        auto ObstacleStation = FCkGym_Station_SpawnParams_Payload();
        ObstacleStation.Tags.Add(n"GroundNavMovedObstacle");
        ObstacleStation.AutoSize = true;
        ObstacleStation.Transform = FTransform(FRotator(0.0, 180.0, 0.0), FVector(2000.0, -2300.0, 0.0), FVector::OneVector);
        ObstacleStation.Title = FText::FromString("GroundNav - Moved Obstacle");

        auto ObstacleDescription = TArray<FText>();
        ObstacleDescription.Add(FText::FromString("A 400uu box standing on the range slab. Press 3 and it jumps one 800uu tile east, out of the Jolt static world and back into it at the new place - which is the only way the published field goes stale."));
        ObstacleDescription.Add(FText::FromString("Nothing repairs it for you. The OBSTACLE row turns amber and says the ground the body LEFT is still blocked; press 4 and the repair opens over the UNION of both footprints, which is the only box that reopens the old half and closes the new one in one pass."));
        ObstacleDescription.Add(FText::FromString("A repair aimed only at where the body arrived would leave its old footprint blocked for the rest of the field's life, because nothing else will ever revisit that ground."));
        ObstacleStation.Description = ObstacleDescription;

        Stations.Add(ObstacleStation);

        auto MarkupStation = FCkGym_Station_SpawnParams_Payload();
        MarkupStation.Tags.Add(n"GroundNavPaintedMarkup");
        MarkupStation.AutoSize = true;
        MarkupStation.Transform = FTransform(FRotator(0.0, 180.0, 0.0), FVector(2000.0, -2900.0, 0.0), FVector::OneVector);
        MarkupStation.Title = FText::FromString("GroundNav - Painted Markup");

        auto MarkupDescription = TArray<FText>();
        MarkupDescription.Add(FText::FromString("A 500uu impassable box dropped across the middle of this band. Press 2 to paint it and again to release it; the row reads the markup handle back, so it reports the paint the surface holds rather than the one this panel last asked for."));
        MarkupDescription.Add(FText::FromString("The request is the provider-NEUTRAL one, the same call the crowd goes through: it names a shape and a place and nothing about which backend answers it, so the same keypress carves Recast and GroundNav alike."));
        MarkupDescription.Add(FText::FromString("Press 5 first to put crowd walkers on this corridor. They cross it end to end and turn round, so a paint dropped in front of them is answered by a replan you can watch rather than by a number."));
        MarkupDescription.Add(FText::FromString("ck.GroundNav.Debug.DrawMarkup 1 draws the paint over a bake: impassable in red, a cost area in amber with its multiplier."));
        MarkupStation.Description = MarkupDescription;

        Stations.Add(MarkupStation);

        auto CrossingStation = FCkGym_Station_SpawnParams_Payload();
        CrossingStation.Tags.Add(n"GroundNavMultiTileCrossing");
        CrossingStation.AutoSize = true;
        CrossingStation.Transform = FTransform(FRotator(0.0, 180.0, 0.0), FVector(2000.0, -3500.0, 0.0), FVector::OneVector);
        CrossingStation.Title = FText::FromString("GroundNav - Multi-Tile Crossing");

        auto CrossingDescription = TArray<FText>();
        CrossingDescription.Add(FText::FromString("A 2800uu route over 800uu tiles, so four tiles lie under one corridor. Press 6 to draw it: the corridor the search walked, and over it the string-pulled route the agent would actually take."));
        CrossingDescription.Add(FText::FromString("The row bakes a FIELD over this band before it asks, and that is not incidental. ck.GroundNav.PathAt reads the DEBUG field, not a volume's published one, and a region bake produces no field to path through at all."));
        CrossingDescription.Add(FText::FromString("Draw mode 5 over the same bake shows the tiles and the seams between them, which is what makes it worth seeing a route that crosses three of them: a tiled bake that disagreed with itself would show as a kink at a seam and nowhere else."));
        CrossingStation.Description = CrossingDescription;

        Stations.Add(CrossingStation);

        auto PocketStation = FCkGym_Station_SpawnParams_Payload();
        PocketStation.Tags.Add(n"GroundNavNoRoutePocket");
        PocketStation.AutoSize = true;
        PocketStation.Transform = FTransform(FRotator(0.0, 180.0, 0.0), FVector(2000.0, -4400.0, 0.0), FVector::OneVector);
        PocketStation.Title = FText::FromString("GroundNav - No-Route Pocket");

        auto PocketDescription = TArray<FText>();
        PocketDescription.Add(FText::FromString("A 600uu island with 300uu of nothing between it and the slab's south edge. It is inside the range volume and it bakes to real walkable ground - no seam can span a gap with no ground in it, and nothing authors a link across it, so there is no way to reach it."));
        PocketDescription.Add(FText::FromString("Press 7 to ask for a path onto it. The request is made with partial paths OFF, and that is the whole station: with them on, a route that cannot reach the island answers with the closest point it COULD reach and reads as a success."));
        PocketDescription.Add(FText::FromString("The POCKET row reports the status the probe was last given. Failed is the right answer here; Ready or Partial would mean something joined the island to the slab."));
        PocketStation.Description = PocketDescription;

        Stations.Add(PocketStation);

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
        DoArm_RangeStation();

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
    //
    // ONE BATCH, not two requests. A batch is ATOMIC: every entry is judged before any is applied, so
    // a drop the volume refused could never leave the ladder authored on its own and this station's
    // rows half-populated. It also completes ONCE, which is the only thing the station can act on -
    // "the deck is joined to the floor" is the state it wants, and two completions cannot say it.
    private void DoRequest_Links(ECk_EnableDisable InEnable)
    {
        if (ck::Is_NOT_Valid(_LinksVolume))
        { return; }

        // The id is -1 because the VOLUME assigns it; the record's identity carries no setter.
        auto DropRecord = FCk_GroundNav_LinkRecord(-1, k_LinksDropStart, k_LinksDropEnd);

        DropRecord.Set_Direction(ECk_GroundNav_LinkDirection::Forward)
                  .Set_Enable(InEnable);

        auto LadderRecord = FCk_GroundNav_LinkRecord(-1, k_LinksLadderStart, k_LinksLadderEnd);

        LadderRecord.Set_Direction(ECk_GroundNav_LinkDirection::Forward)
                    .Set_CostMultiplierForward(k_LinksLadderMultiplier)
                    .Set_ClearanceUu(k_LinksLadderClearanceUu)
                    .Set_Enable(InEnable);

        // Built imperatively: AngelScript takes no brace initialiser for a TArray. The drop goes in
        // first, and ids are handed out monotonically, so the resolution rows below can name the
        // first record the drop and the second the ladder.
        auto Entries = TArray<FCk_Request_GroundNavVolume_Link>();
        Entries.Add(FCk_Request_GroundNavVolume_Link(_LinksDropEntity, DropRecord));
        Entries.Add(FCk_Request_GroundNavVolume_Link(_LinksLadderEntity, LadderRecord));

        utils_ground_nav_volume::Request_LinkBatch(_LinksVolume,
            FCk_Request_GroundNavVolume_LinkBatch(Entries),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinksBatchCompleted"));
    }

    UFUNCTION()
    private void OnLinksBatchCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LinksBatchCompletions += 1;
        _LastLinksBatchResult = InResult;

        if (InResult != ECk_Request_OperationResult::Succeeded)
        {
            ck::groundnav::Log("GroundNav gym: the link batch was REFUSED - a batch is atomic, so neither the drop nor the ladder was applied");
        }
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

    // ---- Range station -----------------------------------------------------------------------------
    //
    // Mints ONE volume over the range slab and the pocket beside it, bakes it, and probes the pocket
    // once the surface has gone quiet. Guarded so Ck_Gym_Restart re-running the gym does not stack a
    // second volume over the same ground.
    //
    // The provider is not set here. The links station ahead of it already put this world on GroundNav,
    // and the provider is a per-WORLD selection - asking for it twice would say something this station
    // does not decide.

    private void DoArm_RangeStation()
    {
        if (_RangeArmed)
        { return; }

        if (_GeometryIsBuilt == false)
        {
            _RangeStage = "the scene is not in the Jolt static world - nothing to bake over";
            return;
        }

        _RangeArmed = true;

        _RangeVolumeEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        _RangeVolumeEntity.Request_OverrideToSelf();
        _RangeVolumeEntity.Set_DebugName(n"GroundNavGym_RangeField");

        auto Config = FCk_GroundNav_BakeConfig(k_RangeCellSizeUu, k_RangeCellHeightUu);
        Config.Set_TileSizeUu(k_RangeTileSizeUu);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(k_RangeAgentHalfHeightUu, k_RangeAgentRadiusUu)));

        // The slab and the pocket both END inside the volume, so at the default sensitivity the ledge
        // filter would demote their whole perimeter - and the pocket, 600uu square, would lose its top
        // outright and fail its probe for a reason that has nothing to do with reachability.
        //
        // The slope limit is deliberately left at the profile default of 45 degrees: that number is
        // what the ramp station is built around, and moving it would make the ramp say nothing.
        Profile.Set_LedgeSensitivity(0.0f);

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(
            FBox(k_RangeVolumeMin, k_RangeVolumeMax), Config, Profile);

        // The bake waited on must be the one asked for, not one that happened to run at setup.
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _RangeVolume = utils_ground_nav_volume::Add(_RangeVolumeEntity, VolumeParams);

        if (ck::Is_NOT_Valid(_RangeVolume))
        {
            _RangeStage = "Add() returned an invalid volume handle";
            return;
        }

        utils_ground_nav_volume::Request_Build(_RangeVolume, FCk_Request_GroundNavVolume_Build());

        _RangeStage = "baking, then waiting for the surface to settle";
        _RangeSettlePolls = 0;

        auto PollParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        PollParams.Set_StartingState(ECk_Timer_State::Running)
                  .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);

        auto PollTimer = utils_timer::Add(_PcEntity, PollParams);
        PollTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnRangeSettlePoll"));

        _RangeSettleTimer = PollTimer;
    }

    // Same named condition the links station waits on, and for the same reason: the pocket probe is
    // only worth firing once the field every query answers from is the published one.
    UFUNCTION()
    private void OnRangeSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _RangeSettlePolls += 1;

        if (utils_nav_surface::Get_IsSurfaceSettled())
        {
            DoStop_RangeSettlePoll();
            _RangeStage = f"settled after {_RangeSettlePolls} polls";
            DoProbe_Pocket();
            return;
        }

        if (_RangeSettlePolls >= k_RangeSettlePollCeiling)
        {
            DoStop_RangeSettlePoll();
            _RangeStage = "the surface never settled - the pocket was never probed";
            ck::groundnav::Log("GroundNav gym: the range field never settled - the no-route pocket was not probed");
        }
    }

    private void DoStop_RangeSettlePoll()
    {
        if (ck::Is_NOT_Valid(_RangeSettleTimer))
        { return; }

        utils_timer::Request_Stop(_RangeSettleTimer);
        _RangeSettleTimer = FCk_Handle_Timer();
    }

    // ---- Range station: the provider row ------------------------------------------------------------

    private void DoCycle_Provider()
    {
        ECk_NavSurface_Provider Next = ECk_NavSurface_Provider::GroundNav;

        if (utils_nav_surface::Get_Provider() == ECk_NavSurface_Provider::GroundNav)
        { Next = ECk_NavSurface_Provider::Recast; }

        utils_nav_surface::Request_SetProvider(Next);

        ck::groundnav::Log("GroundNav gym: provider switched - the volumes stay baked either way, and the SURFACE row says which backend is answering now");
    }

    // ---- Range station: the paint row ---------------------------------------------------------------
    //
    // The PROVIDER-NEUTRAL request, which is the one the crowd goes through: it names a shape and a
    // place and nothing about which backend answers it, so one keypress carves Recast and GroundNav
    // alike. Releasing it is destroying the markup entity - the handle IS the paint's lifetime.

    private void DoToggle_Paint()
    {
        if (ck::IsValid(_RangeMarkup))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_RangeMarkup));
            _RangeMarkup = FCk_Handle_NavSurfaceMarkup();

            ck::groundnav::Log("GroundNav gym: the paint is released - the corridor reopens once the surface settles again");
            return;
        }

        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(k_MarkupHalfExtents)),
            FGameplayTag());
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, k_MarkupCentre, FVector::OneVector));

        _RangeMarkup = utils_nav_surface::Request_ImpassableBox(Request);

        if (ck::Is_NOT_Valid(_RangeMarkup))
        {
            ck::groundnav::Warning("GroundNav gym: the paint request handed back no markup handle - nothing was carved");
            return;
        }

        ck::groundnav::Log("GroundNav gym: the corridor is painted impassable - the walkers on it replan around the hole");
    }

    // ---- Range station: the obstacle and its repair ---------------------------------------------------

    private void DoNudge_Obstacle()
    {
        if (ck::Is_NOT_Valid(_ObstacleActor))
        { return; }

        // OUT of the static world before the move and back in after it. The static world holds its own
        // copy of the shape at the position it was baked at, so a body moved without that round trip
        // is still standing where it was as far as every bake is concerned.
        utils_jolt_static_world::Request_RemoveActor(_ObstacleActor);

        _ObstacleIsMoved = !_ObstacleIsMoved;

        FVector Destination = k_ObstacleHomeCentre;

        if (_ObstacleIsMoved)
        { Destination = k_ObstacleMovedCentre; }

        _ObstacleActor.SetActorLocation(Destination);

        const auto NumBaked = utils_jolt_static_world::Request_BakeActor(_ObstacleActor);

        if (NumBaked == 0)
        {
            ck::groundnav::Warning("GroundNav gym: the moved obstacle re-baked 0 Jolt bodies - the ground under it can no longer change");
            return;
        }

        _ObstacleRepairOwed = true;

        ck::groundnav::Log("GroundNav gym: the obstacle moved one tile - the published field still carries the ground it left, until a repair opens over BOTH footprints");
    }

    private void DoRepair_ObstacleGround()
    {
        if (ck::Is_NOT_Valid(_RangeVolume))
        { return; }

        // The UNION of both footprints, never just the one the body arrived on: the half it LEFT is
        // ground nothing else will ever revisit, so a repair aimed only at the new position leaves the
        // old footprint blocked for the rest of the field's life.
        const auto DirtyBounds = FBox(k_ObstacleDirtyMin, k_ObstacleDirtyMax);

        utils_ground_nav_volume::Request_Repair(_RangeVolume,
            FCk_Request_GroundNavVolume_Repair(DirtyBounds),
            FCk_Delegate_Request_OnCompleted(this, n"OnRangeRepairCompleted"));
    }

    UFUNCTION()
    private void OnRangeRepairCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RepairsRun += 1;
        _LastRepairResult = InResult;

        // Cleared by the repair the volume actually ran, and by nothing else: a refused request leaves
        // the ground exactly as stale as it was, and the row must go on saying so.
        if (InResult == ECk_Request_OperationResult::Succeeded)
        { _ObstacleRepairOwed = false; }
    }

    // ---- Range station: the crowd walkers -------------------------------------------------------------

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

        const auto Spawn = k_WalkerWestPoint + FVector(0.0, Offset, 0.0);
        const auto Goal = k_WalkerEastPoint + FVector(0.0, Offset, 0.0);

        auto WalkerEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        WalkerEntity.Set_DebugName(n"GroundNavGym_RangeWalker");

        const auto Facing = (Goal - Spawn).Rotation();

        auto WalkerTransform = utils_transform::Add(WalkerEntity,
            FTransform(Facing, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        auto Walker = utils_crowd_agent::Add(WalkerTransform,
            FCk_Fragment_CrowdAgent_ParamsData(k_WalkerRadiusUu, k_WalkerHeightUu));

        if (ck::Is_NOT_Valid(Walker))
        {
            ck::groundnav::Warning("GroundNav gym: a range walker got no crowd agent handle");
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

        FVector Destination = k_WalkerEastPoint;

        if (Here.X > 0.0)
        { Destination = k_WalkerWestPoint; }

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
    }

    // ---- Range station: the crossing route and the pocket ---------------------------------------------

    // ck.GroundNav.PathAt reads the DEBUG field and not a volume's published one, so the row bakes a
    // field over the crossing band before it asks: a region bake produces no field to path through,
    // and a field baked at the tuning scene has no ground at all under this route.
    private void DoDraw_CrossingPath()
    {
        DoBakeFieldAt(k_CrossingBakeCentre);

        const auto Start = k_CrossingWestPoint;
        const auto Goal = k_CrossingEastPoint;

        System::ExecuteConsoleCommand(
            f"ck.GroundNav.PathAt {Start.X} {Start.Y} {Start.Z} {Goal.X} {Goal.Y} {Goal.Z}");

        _PathDrawEnabled = true;
    }

    private void DoToggle_CrossingPath()
    {
        if (_PathDrawEnabled)
        {
            System::ExecuteConsoleCommand("ck.GroundNav.Clear");
            _PathDrawEnabled = false;
            return;
        }

        DoDraw_CrossingPath();
    }

    // One probe entity, re-asked rather than re-minted: a fresh entity per press would leave one
    // behind for every press, and the status row reads the LAST answer this one was given.
    private void DoProbe_Pocket()
    {
        if (ck::Is_NOT_Valid(_PocketProbeEntity))
        {
            _PocketProbeEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
            _PocketProbeEntity.Set_DebugName(n"GroundNavGym_PocketProbe");

            utils_transform::Add(_PocketProbeEntity,
                FTransform(FRotator::ZeroRotator, k_PocketProbeStart, FVector::OneVector),
                ECk_Replication::DoesNotReplicate);

            utils_ground_nav_path::Add(_PocketProbeEntity,
                FCk_Fragment_GroundNavPath_ParamsData(k_RangeAgentRadiusUu));
        }

        // Partial paths OFF, and that is the whole station: with them on, a route that cannot reach the
        // island answers with the closest point it COULD reach and reads as a success. The question
        // being asked is whether the island is reachable at all.
        auto Request = FCk_Request_Nav_FindPath(k_PocketProbeGoal);
        Request.Set_AllowPartialPath(false);

        utils_nav::Request_FindPath(_PocketProbeEntity, Request);

        _PocketProbesRun += 1;
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

        // The range slab and the four stations standing on it, then the pocket island beyond its
        // south edge. All of it goes into the Jolt static world through the same call the rest of the
        // scene does - the range volume bakes from that world and from nothing else.
        if (DoSpawnBox(k_RangeSlabCentre, k_RangeSlabScale) == false)
        { return false; }

        if (DoSpawnBoxRotated(k_RampLowerCentre,
                FRotator(k_RampLowerPitchDegrees, 0.0, 0.0), k_RampPlankScale) == false)
        { return false; }

        if (DoSpawnBoxRotated(k_RampUpperCentre,
                FRotator(k_RampUpperPitchDegrees, 0.0, 0.0), k_RampPlankScale) == false)
        { return false; }

        if (DoSpawnBox(k_PocketCentre, k_PocketScale) == false)
        { return false; }

        if (DoSpawnObstacle() == false)
        { return false; }

        return true;
    }

    // The obstacle is the one scene box kept as an actor: the nudge row moves this body and re-bakes
    // it, which is the only way ground in this scene goes stale in the first place. Held across a
    // restart rather than re-spawned, so Ck_Gym_Restart cannot leave the old one standing in the
    // static world with nothing holding it.
    private bool DoSpawnObstacle()
    {
        if (ck::IsValid(_ObstacleActor))
        { return true; }

        auto Obstacle = DoSpawnBoxActor(k_ObstacleHomeCentre, FRotator::ZeroRotator, k_ObstacleScale);

        if (Obstacle == nullptr)
        { return false; }

        _ObstacleActor = Obstacle;
        _ObstacleIsMoved = false;

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
        return DoSpawnBoxRotated(InCentre, FRotator::ZeroRotator, InScale);
    }

    private bool DoSpawnBoxRotated(FVector InCentre, FRotator InRotation, FVector InScale)
    {
        return DoSpawnBoxActor(InCentre, InRotation, InScale) != nullptr;
    }

    // Hands the actor back rather than a verdict, for the one box the panel has to keep hold of. Every
    // other caller only wants to know whether the scene is still whole.
    private AStaticMeshActor DoSpawnBoxActor(FVector InCentre, FRotator InRotation, FVector InScale)
    {
        auto BoxActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, InCentre, InRotation));
        if (ck::Is_NOT_Valid(BoxActor))
        {
            ck::groundnav::Warning("GroundNav gym: failed to spawn a scene box");
            return nullptr;
        }

        // A runtime-spawned AStaticMeshActor must be Movable BEFORE it will accept a mesh.
        BoxActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);

        auto CubeMesh = Cast<UStaticMesh>(LoadObject(this, "/Engine/BasicShapes/Cube.Cube"));
        if (CubeMesh == nullptr)
        {
            ck::groundnav::Warning("GroundNav gym: failed to load /Engine/BasicShapes/Cube.Cube");
            return nullptr;
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
            return nullptr;
        }

        return BoxActor;
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
        // Sized to the tuning scene rather than to the viewer: it spans X -1200..1400 and Y +/-1200,
        // and everything walkable in it sits between Z=0 and Z=240. The range bands south of it are
        // reached by aiming a bake AT one, not by widening this - an extent that swallowed the whole
        // world would truncate the drawing long before it got there.
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
        DoBakeAt(k_BakeCentre);
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

        // Clear wiped the drawing, so whatever route was on screen no longer is.
        _PathDrawEnabled = false;
    }

    // The same scene baked as several tiles instead of one region. Everything else is identical, so
    // the two runs are directly comparable - which is the point: a tiled bake that disagreed with the
    // whole one would show up here as a seam, and nowhere else.
    private void DoBakeField()
    {
        DoBakeFieldAt(k_BakeCentre);
    }

    private void DoBakeFieldAt(FVector InCentre)
    {
        DoPushAllTunables();

        // The same tile size the range volume bakes on, deliberately: the crossing station's claim
        // that four tiles lie under one corridor is only true of a bake that tiles the same way.
        DoSetTunable("TileSizeUu", k_RangeTileSizeUu);
        System::ExecuteConsoleCommand("ck.GroundNav.Clear");
        System::ExecuteConsoleCommand(
            f"ck.GroundNav.BakeFieldAt {InCentre.X} {InCentre.Y} {InCentre.Z}");
        _BakeCount += 1;
        _LastBakeWasField = true;
        _LastBakeCentre = InCentre;
        _PathDrawEnabled = false;
    }

    // Re-runs the KIND of bake that last ran and re-aims it WHERE that one was aimed. Both halves
    // matter: a region bake would replace the field mode 5 draws from, and a re-bake that snapped back
    // to the scene would erase the range station a tunable key was being turned against.
    private void DoRebake()
    {
        if (_LastBakeWasField)
        {
            DoBakeFieldAt(_LastBakeCentre);
            return;
        }

        DoBakeAt(_LastBakeCentre);
    }

    // ---- Control panel ---------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GROUNDNAV: TUNING RANGE";
    }

    // Readback: every value column below is asked for as the row is built, except where there is
    // nothing to ask. Four columns are remembered rather than read, and each says so where it stands:
    // the tunable cycles (no AngelScript console-variable reader exists - see the value tables above),
    // how many bakes have run and where the last one was aimed (the gym is the only thing that
    // counts them), whether the crossing route is on screen (PathAt is a command, not a cvar), and
    // whether a nudge is still owed a repair (the volume's pending-dirty answer is C++ only).
    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("SCENE"));
        Rows.Add(CkGym_Control::Status("Geometry", Get_GeometryStatus(), _GeometryIsBuilt == false));
        Rows.Add(CkGym_Control::Status("Bake region",
        f"white box around ({_LastBakeCentre.X}, {_LastBakeCentre.Y}, {_LastBakeCentre.Z}), +/-1500uu wide, 400uu tall - it is pinned where the bake was aimed and does not follow you"));
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

        // Every value in this section is read where it is shown: the field's own counts off the volume,
        // the provider and its health off the facade, the obstacle off the actor, the walkers off
        // their agents, the pocket off the probe's last answer.
        Rows.Add(CkGym_Control::Header("RANGE - five stations south of the floor, on a volume of their own"));
        Rows.Add(CkGym_Control::Status("Field", Get_RangeFieldStatus(),
            utils_ground_nav_volume::Get_IsBuilt(_RangeVolume) == false));
        Rows.Add(CkGym_Control::Status("Surface", Get_RangeSurfaceStatus()));
        Rows.Add(CkGym_Control::Cycle(EKeys::One, "1",
            "Provider (a per-WORLD choice - the volumes here only answer on GroundNav)",
            Get_ProviderLabel()));
        Rows.Add(CkGym_Control::Status("Ramp (Y -1700)",
            "two planks in series at 40 then 50 degrees - the lower clears the profile's 45-degree slope limit and the upper does not, so the ramp stops being ground half way up"));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::Two, "2",
            "Markup paint (Y -2900, straddling the walkers' corridor)",
            ck::IsValid(_RangeMarkup), "painted", "clear"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3",
            "Nudge the obstacle one tile (Y -2300) - moves the body, leaves the ground behind it stale"));
        Rows.Add(CkGym_Control::Status("Obstacle", Get_ObstacleStatus(), _ObstacleRepairOwed));
        Rows.Add(CkGym_Control::Action(EKeys::Four, "4",
            "Repair over BOTH obstacle footprints", _ObstacleRepairOwed));
        Rows.Add(CkGym_Control::Cycle(EKeys::Five, "5", "Crowd walkers on the corridor",
            Get_WalkerCountLabel()));
        Rows.Add(CkGym_Control::Status("Walkers", Get_WalkerStatus()));
        Rows.Add(CkGym_Control::Toggle(EKeys::Six, "6",
            "Draw the crossing route (Y -3500; bakes a FIELD over that band first - R, Y and every tunable key replace the drawing)",
            _PathDrawEnabled));
        Rows.Add(CkGym_Control::Action(EKeys::Seven, "7",
            "Probe the no-route pocket (Y -4400) with partial paths OFF"));
        Rows.Add(CkGym_Control::Status("Pocket", Get_PocketStatus()));

        // LAST, and that is not a preference. How many resolution rows there are depends on how many
        // records the links volume holds, so a section of them placed ABOVE a keyed row would move
        // that row's index between frames, and the panel dispatches on the index.
        Rows.Add(CkGym_Control::Header("LINK RESOLUTION - one row per record the links volume holds"));

        auto ResolutionRows = Get_LinkResolutionRows();

        for (int32 Index = 0; Index < ResolutionRows.Num(); Index++)
        { Rows.Add(ResolutionRows[Index]); }

        return Rows;
    }

    // One row per authored link, straight off the published field. Every index in a resolution - the
    // plates above all - is valid only against the publish that answered it, so this is read where it
    // is displayed and never held: the panel rebuilds its rows each frame, which is a stricter
    // refresh than the settle poll that authored the links in the first place.
    private TArray<FCkGym_ControlRow> Get_LinkResolutionRows()
    {
        auto OutRows = TArray<FCkGym_ControlRow>();

        auto Records = utils_ground_nav_volume::Get_LinkRecords(_LinksVolume);

        for (int32 Index = 0; Index < Records.Num(); Index++)
        {
            auto Record = Records[Index];

            const auto LinkId = Record.Get_Id();
            const auto Resolution = utils_ground_nav_volume::Get_LinkResolution(_LinksVolume, LinkId);

            // Authoring order, which is the batch's order and the order the ids were handed out in.
            auto RowName = f"Link {LinkId}";

            if (Index == 0)
            { RowName = f"Link {LinkId} (drop)"; }
            else if (Index == 1)
            { RowName = f"Link {LinkId} (ladder)"; }

            const auto StartStatus = Resolution.Get_StartStatus();
            const auto EndStatus = Resolution.Get_EndStatus();
            const auto StartPlate = Resolution.Get_StartFlatPlate();
            const auto EndPlate = Resolution.Get_EndFlatPlate();
            const auto Resolved = Resolution.Get_Resolved();
            const auto Live = Resolution.Get_Live();

            OutRows.Add(CkGym_Control::Status(RowName,
                f"start {StartStatus} (plate {StartPlate}) - end {EndStatus} (plate {EndPlate}) - resolved: {Resolved} - live: {Live}",
                Resolved == false));
        }

        return OutRows;
    }

    // The static-body count is read off the world as the row is built rather than remembered: the
    // open-collision toggle and the obstacle nudge both add and remove bodies, and a number captured
    // at startup would go on reporting the scene as it was first spawned.
    private FString Get_GeometryStatus()
    {
        const auto Bodies = utils_jolt_static_world::Get_NumStaticBodies();

        if (_GeometryIsBuilt == false)
        { return f"NOT BAKED INTO JOLT ({Bodies} static bodies) - every bake will find nothing"; }

        return f"{Bodies} static bodies - floor + 12 steps (20uu risers) + platform + 75uu catwalk + 160uu pinch, plus the range slab south of it";
    }

    private FString Get_RangeFieldStatus()
    {
        if (utils_ground_nav_volume::Get_IsBuilt(_RangeVolume) == false)
        { return _RangeStage; }

        const auto Epoch = utils_ground_nav_volume::Get_BuildEpoch(_RangeVolume);
        const auto TilesBuilt = utils_ground_nav_volume::Get_BuiltTileCount(_RangeVolume);
        const auto TilesTotal = utils_ground_nav_volume::Get_TileCount(_RangeVolume);
        const auto Cells = utils_ground_nav_volume::Get_WalkableCellCount(_RangeVolume);
        const auto Seams = utils_ground_nav_volume::Get_SeamPortalCount(_RangeVolume);

        // PLATES are deliberately absent. They are not among the volume's reflected counts - the only
        // place a plate total is printed is ck.GroundNav.Print, over the DEBUG field, which is a
        // different field from this one. Walkable cells and seam portals are what the volume itself
        // will answer, so they are what this row says.
        return f"epoch {Epoch} - {TilesBuilt} of {TilesTotal} tiles built - {Cells} walkable cells - {Seams} seam portals";
    }

    private FString Get_RangeSurfaceStatus()
    {
        const auto Provider = utils_nav_surface::Get_Provider();
        const auto Health = utils_nav_surface::Get_ProviderHealth();
        const auto Revision = utils_nav_surface::Get_SurfaceRevision();
        const auto Settled = utils_nav_surface::Get_IsSurfaceSettled();

        return f"{Provider} - health {Health} - revision {Revision} - settled: {Settled}";
    }

    private FString Get_ProviderLabel()
    {
        const auto Provider = utils_nav_surface::Get_Provider();

        if (Provider == ECk_NavSurface_Provider::GroundNav)
        { return "GroundNav (this gym's volumes answer)"; }

        return "Recast (the volumes stay baked, but nothing routes through them)";
    }

    private FString Get_ObstacleStatus()
    {
        if (ck::Is_NOT_Valid(_ObstacleActor))
        { return "the obstacle never spawned"; }

        const auto Where = _ObstacleActor.GetActorLocation();

        FString RepairText = f"{_RepairsRun} repairs run (last {_LastRepairResult})";

        if (_ObstacleRepairOwed)
        { RepairText = "the ground it LEFT is still blocked - press 4"; }

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

        int32 Walking = 0;

        for (int32 Index = 0; Index < _Walkers.Num(); Index++)
        {
            if (utils_crowd_agent::Get_MovementState(_Walkers[Index]) == ECk_CrowdAgent_MovementState::Walking)
            { Walking += 1; }
        }

        const auto Total = _Walkers.Num();

        return f"{Walking} of {Total} walking between the two ends of the corridor";
    }

    private FString Get_PocketStatus()
    {
        if (_PocketProbesRun == 0)
        { return "not probed yet"; }

        const auto Status = utils_nav::Get_PathStatus(_PocketProbeEntity);

        return f"{_PocketProbesRun} probes - last status {Status} (Failed is what an island with no seam and no link is supposed to answer)";
    }

    private FString Get_LinksFieldStatus()
    {
        if (utils_ground_nav_volume::Get_IsBuilt(_LinksVolume) == false)
        { return _LinksStage; }

        const auto Tiles = utils_ground_nav_volume::Get_BuiltTileCount(_LinksVolume);
        const auto Batches = _LinksBatchCompletions;
        const auto LastResult = _LastLinksBatchResult;

        return f"published - {Tiles} tiles - {_LinksStage} - batches: {Batches} (last {LastResult})";
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
            DoToggle_CrossingPath();
            return;
        }

        if (InRowIndex == k_Row_PocketProbe)
        {
            DoProbe_Pocket();
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
