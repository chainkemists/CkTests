class ACk_GroundNavGym_Walk_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- Where the scene stands ------------------------------------------------------------------
    //
    // Every dimension below is LOCAL to the scene, and the scene is placed off the station's own
    // footprint anchor rather than at a world constant: the station is placed by
    // Request_ApplyDefaultGridLayout, so a hardcoded world position is wrong the moment the grid
    // changes. Stations face world -X, so the scene is pushed into -X in front of the board.

    private const FVector k_SceneOffset = FVector(-2600.0, 0.0, 0.0);

    // ---- The slab ---------------------------------------------------------------------------------
    //
    // 3600 x 2400 with its top face at the scene's Z 0 - X +/-1800, Y +/-1200. Z scale must stay
    // >= 0.5; thinner slabs bake to zero walkable tiles.
    private const FVector k_SlabCentre = FVector(0.0, 0.0, -100.0);
    private const FVector k_SlabScale  = FVector(36.0, 24.0, 2.0);

    // ---- The pillars ------------------------------------------------------------------------------
    //
    // Four 150 x 150 x 300 boxes on the slab, each straddling the west-east lane at Y 0 by a different
    // amount, so the crossing route steps round all four instead of running straight. Nothing else
    // stands near them, so there is always a way past - the weave is the picture, not a maze.
    private const FVector k_PillarScale = FVector(1.5, 1.5, 3.0);
    private const FVector k_Pillar0     = FVector(-900.0, -60.0, 150.0);
    private const FVector k_Pillar1     = FVector(-300.0, 120.0, 150.0);
    private const FVector k_Pillar2     = FVector(300.0, -100.0, 150.0);
    private const FVector k_Pillar3     = FVector(900.0, 80.0, 150.0);

    // ---- The ramp and its landing -------------------------------------------------------------------
    //
    // A 400uu landing 200uu above the slab, and two planks climbing to it SIDE BY SIDE rather than in
    // series - 40 degrees and 50, either side of the default profile's 45-degree slope limit. The
    // landing is 200uu clear of the slab on every side and nothing seams up to it, so the shallow
    // plank is the only ground that reaches it and the steep one is ground the filters throw away.
    //
    // Each centre is the plank's TOP-FACE midpoint pushed 20uu (half its thickness) back along its own
    // normal, which for FRotator(pitch, 0, 0) is (-sin(pitch), 0, cos(pitch)) - so each top face runs
    // from the slab at Z 0 to the landing edge at (-1200, 200) with no lip at either end:
    //   40 deg: run 200/tan40 = 238.4, mid (-1319.2, 100) - 20 * (-0.643, 0.766) -> (-1306.3, 84.7)
    //   50 deg: run 200/tan50 = 167.8, mid (-1283.9, 100) - 20 * (-0.766, 0.643) -> (-1268.6, 87.1)
    // The lengths (320, 270) each run a little past the slope they span, so neither end leaves a gap.
    private const FVector k_LandingCentre = FVector(-1000.0, 700.0, 100.0);
    private const FVector k_LandingScale  = FVector(4.0, 4.0, 2.0);

    private const float k_RampLowerPitchDegrees = 40.0f;
    private const float k_RampUpperPitchDegrees = 50.0f;

    private const FVector k_RampLowerCentre = FVector(-1306.3, 600.0, 84.7);
    private const FVector k_RampLowerScale  = FVector(3.2, 2.0, 0.4);
    private const FVector k_RampUpperCentre = FVector(-1268.6, 800.0, 87.1);
    private const FVector k_RampUpperScale  = FVector(2.7, 2.0, 0.4);

    // ---- The island -------------------------------------------------------------------------------
    //
    // 600uu square with 300uu of nothing between it and the slab's south edge: no seam can span a gap
    // with no ground in it, and nothing authors a link across it, so it is baked ground that no route
    // can reach.
    private const FVector k_IslandCentre = FVector(0.0, -1800.0, -100.0);
    private const FVector k_IslandScale  = FVector(6.0, 6.0, 2.0);

    // ---- The posts --------------------------------------------------------------------------------
    //
    // All at ground + 100uu, which is where a 180uu body's centre stands.
    private const FVector k_WestPost     = FVector(-1650.0, 0.0, 100.0);
    private const FVector k_EastPost     = FVector(1650.0, 0.0, 100.0);
    private const FVector k_RampFootPost = FVector(-1600.0, 600.0, 100.0);
    private const FVector k_LandingPost  = FVector(-1000.0, 700.0, 300.0);
    private const FVector k_ShorePost    = FVector(0.0, -1100.0, 100.0);
    private const FVector k_IslandPost   = FVector(0.0, -1800.0, 100.0);

    // The five extra crossings key 1 adds at count 8: the same west-east run on lanes 200uu apart,
    // south of the first one so none of them meets the ramp.
    private const float k_LaneFirstY  = -200.0f;
    private const float k_LaneSpacing = 200.0f;
    private const int32 k_ExtraLanes  = 5;

    // Where the caption stands, high enough over the slab to be read from the viewpoint.
    private const FVector k_CaptionPoint = FVector(0.0, 0.0, 900.0);

    // ---- The bake ---------------------------------------------------------------------------------
    //
    // The 25uu lattice every GroundNav fixture in the corpus bakes on, 800uu tiles under a scene this
    // wide, and the default 34uu / 180uu body.
    private const float k_CellSizeUu        = 25.0f;
    private const float k_CellHeightUu      = 10.0f;
    private const float k_TileSizeUu        = 800.0f;
    private const float k_AgentRadiusUu     = 34.0f;
    private const float k_AgentHalfHeightUu = 90.0f;
    private const float k_WalkerHeightUu    = 180.0f;

    // 0.05s a poll, so thirty seconds on a NAMED condition before the gym says it gave up rather than
    // hanging silently. There is no FCkGroundNavGym_OverlayRefresh beside it on purpose: the deferred
    // redraw exists for a request that CHANGES the field, and this gym issues none - key 1 rebuilds
    // walkers and T re-bakes the DEBUG picture, which is a command and publishes nothing.
    private const int32 k_SettlePollCeiling = 600;

    // The slab, the ramp, the landing and the island - and nothing else, because nothing else is here.
    private const FVector k_VolumeMin = FVector(-1900.0, -2300.0, -400.0);
    private const FVector k_VolumeMax = FVector(1900.0, 1400.0, 600.0);

    // Only the REGION is stated here; every filter is pushed off the volume by Request_BakeDebugFieldAt,
    // so the picture and the walkers cannot describe different fields. The centre is pulled south so
    // one bake covers the slab AND the island beyond its edge; 3800uu of span on a 25uu lattice is
    // about 23000 columns, inside the ceiling below.
    private const FVector k_BakeCentre        = FVector(0.0, -450.0, 100.0);
    private const float   k_DebugBakeExtentUu = 1900.0f;
    private const float   k_DebugBakeHeightUu = 400.0f;
    private const int32   k_DebugBakeMaxCells = 40000;

    // Frames the ramp at the north-west, the pillar corridor across the middle and the island beyond
    // the south edge, from high above the scene's south-east.
    private const FVector  k_ViewOffset   = FVector(2600.0, -2400.0, 2000.0);
    private const FRotator k_ViewRotation = FRotator(-30.5, 143.8, 0.0);

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Layout: the demo header (This shows / Verdict / Walkers = rows 0-2), this gym's one keyed row,
    // then the shared T row LAST. Status rows never reach Request_ControlActivated but they DO occupy
    // an index, and the panel dispatches on the index. 3 is CkGroundNavDemo::k_DemoHeaderRowCount,
    // written as a literal because a class default initialiser reading a namespace constant would
    // depend on module init order and nothing else in the corpus does it.
    private const int32 k_Row_WalkerCount = 3;
    private const int32 k_Row_DrawMode    = 4;

    // How many counts key 1 steps through: 3, 1, 8.
    private const int32 k_WalkerCountModes = 3;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FVector _Origin = FVector::ZeroVector;
    private bool _GeometryIsBuilt = false;

    // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and the slab, the pillars, the
    // planks, the landing and the island are spawned actors that nothing here holds a handle to - so a
    // second pass would stack a whole second scene into the Jolt static world, invisible to every row.
    private bool _SceneSpawned = false;

    private FCkGroundNavGym_Field _Field;

    private FCkGroundNavDemo_WalkerSet _Walkers;

    // Which of the three counts key 1 is on: 0 -> 3, 1 -> 1, 2 -> 8.
    private int32 _WalkerCountIndex = 0;

    // Plates, because this station is about which ground is walkable at all. T cycles it.
    private int32 _DrawModeIndex = 0;

    // The posts the walkers patrol between, in WORLD space, rebuilt whenever the walkers are. Three
    // parallel arrays rather than one of a local struct: Tick wants a point, a label and the colour of
    // the walker the post belongs to, and nothing else ever reads them.
    private TArray<FVector> _PostPoints;
    private TArray<FString> _PostLabels;
    private TArray<FLinearColor> _PostColors;

    // ---- Station ---------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // No Transform: the base grid places it, and the scene is built off the anchor it lands on.
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavWalk");
        Station.AutoSize = true;
        Station.Title = FText::FromString("GroundNav - Walk");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Walkers patrol a baked field: one weaves the four pillars west to east, one climbs the ramp to the landing over the 40-degree plank because the 50-degree one is not ground, and one asks for the island across the gap and is refused."));
        Description.Add(FText::FromString("Key 1 cycles how many walkers are on the scene - three, one, or eight. T cycles what the picture under them shows."));
        Description.Add(FText::FromString("The Verdict turns green once the pillar and the ramp walkers have walked and the island walker is holding with no route, which is the contract and not a fault."));
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
            ck::groundnav::Warning("GroundNav walk gym: PC entity invalid; cannot start");
            return;
        }

        _Origin = Get_StationAnchorLocation("GroundNavWalk", ECk_GymStation_Anchor::FootprintCenter);

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav walk gym: the scene failed to bake into the Jolt static world - the field has nothing to bake over", n"GroundNavGym.Scene", 10.0);
        }

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        DoArm_Field();

        ck::groundnav::Log("GroundNav walk gym: scene built - the walkers step onto it once the field settles");
    }

    // Scene-local to world. Everything the gym spawns, bakes and walks between goes through here, so
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

        // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and a field is minted ONCE -
        // so the mint below is turned away the second time and the settle poll never fires again. The
        // retained draw is command-driven and nothing redraws on its own, so the picture is owed here.
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

        // The slab, the landing and the island all END inside the volume, so at the default sensitivity
        // the ledge filter would demote their perimeters - and the 400uu landing would lose its top
        // outright, for a reason with nothing to do with the ramp. The SLOPE limit is left at the
        // profile default of 45 degrees: that is the number the two planks are pitched either side of.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(Get_ScenePoint(k_VolumeMin), Get_ScenePoint(k_VolumeMax));

        _Field.Request_Mint(_PcEntity, n"GroundNavGym_WalkField", Bounds, Config, Profile,
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
    // the field the walkers route through is the one the picture draws.
    UFUNCTION()
    private void OnFieldSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Step = _Field.Do_PollSettle();

        if (Step == ECkGroundNavGym_Settle::Settled)
        {
            DoRefresh_Picture();

            // The walkers are put on the scene ONCE, at the first settle. A later settle - a re-mint, a
            // rebuild - is not a reason to throw away bodies that are mid-leg and the legs they have
            // already walked, which are what the Verdict reads.
            if (_Walkers.Get_Count() == 0)
            { DoSpawn_Walkers(); }

            return;
        }

        if (Step == ECkGroundNavGym_Settle::GaveUp)
        {
            _Field.Set_Stage("the surface never settled - no walkers were spawned");
            ck::groundnav::Log("GroundNav walk gym: the field never settled - nothing was put on the scene");
        }
    }

    // ---- The picture ---------------------------------------------------------------------------------
    //
    // The retained draw is COMMAND-driven: the mode selects what a bake draws and no sink redraws on
    // its own, so the plates exist only because ck.GroundNav.BakeFieldAt ran. There are no authored
    // links on this scene, so there is nothing for ck.GroundNav.LinksAt to report.

    private void DoRefresh_Picture()
    {
        CkGroundNavGym::Request_BakeDebugFieldAt(_Field, Get_ScenePoint(k_BakeCentre),
            k_DebugBakeExtentUu, k_DebugBakeHeightUu, k_DebugBakeMaxCells, _DrawModeIndex);
    }

    // ---- The walkers ---------------------------------------------------------------------------------

    // 3 is the station: the pillars, the ramp and the island. 1 strips it back to the one crossing.
    // 8 adds five more of that crossing on their own lanes, so the weave is a crowd rather than a line.
    private int32 Get_WalkerCount()
    {
        if (_WalkerCountIndex == 1)
        { return 1; }

        if (_WalkerCountIndex == 2)
        { return 8; }

        return 3;
    }

    private FString Get_WalkerCountLabel()
    {
        if (_WalkerCountIndex == 1)
        { return "1 - the pillar crossing on its own"; }

        if (_WalkerCountIndex == 2)
        { return "8 - the three, plus five more crossings on lanes 200uu apart"; }

        return "3 - the pillars, the ramp, the island";
    }

    private void DoCycle_WalkerCount()
    {
        _WalkerCountIndex = (_WalkerCountIndex + 1) % k_WalkerCountModes;

        // Rebuilt rather than trimmed: the count IS the set, and a walker kept across the change would
        // carry its old legs and its old failure into a scene the reader has just asked to be different.
        DoSpawn_Walkers();
    }

    private void DoSpawn_Walkers()
    {
        _Walkers.Request_DestroyAll();

        _PostPoints.Empty();
        _PostLabels.Empty();
        _PostColors.Empty();

        const auto Count = Get_WalkerCount();

        // W0 - west to east through the pillars. The one crossing every count has.
        DoAdd_Walker(0, Get_ScenePoint(k_WestPost), Get_ScenePoint(k_EastPost), "A", "B");

        if (Count >= 3)
        {
            // W1 - the ramp's foot to the landing. Its route must climb the 40-degree plank; the
            // 50-degree one is past the profile's slope limit and is never ground to step on.
            DoAdd_Walker(1, Get_ScenePoint(k_RampFootPost), Get_ScenePoint(k_LandingPost),
                "ramp foot", "landing");

            // W2 - the slab's south shore to the island. There is no route, by construction: it asks,
            // is refused, and holds where it stopped. That refusal is the third of the three answers.
            DoAdd_Walker(2, Get_ScenePoint(k_ShorePost), Get_ScenePoint(k_IslandPost),
                "shore", "island");
        }

        if (Count >= 8)
        {
            for (int32 Lane = 0; Lane < k_ExtraLanes; Lane++)
            {
                const auto Index = 3 + Lane;
                const auto LaneY = k_LaneFirstY - float(Lane) * k_LaneSpacing;

                // Declared locals of the concrete type, not `auto`: the posts are class CONSTANTS and
                // `auto` preserves const, so an assignment to .Y would be refused. This is the copy
                // that launders it.
                FVector West = k_WestPost;
                West.Y = LaneY;

                FVector East = k_EastPost;
                East.Y = LaneY;

                DoAdd_Walker(Index, Get_ScenePoint(West), Get_ScenePoint(East),
                    f"W{Index}", f"W{Index}");
            }
        }

        const auto Spawned = _Walkers.Get_Count();
        ck::groundnav::Log(f"GroundNav walk gym: {Spawned} walkers on the scene");
    }

    // One walker and the two posts it patrols between, in the walker's own colour so the panel, the
    // route and the posts can all be told apart at eight bodies.
    private void DoAdd_Walker(int32 InIndex, FVector InPostA, FVector InPostB, FString InLabelA, FString InLabelB)
    {
        // Declared non-const: Request_Add and Draw_GoalPost take the colour BY VALUE, and `auto`
        // preserves const.
        FLinearColor Color = CkGroundNavDemo::Get_WalkerColor(InIndex);

        if (_Walkers.Request_Add(_PcEntity, FName(f"GroundNavGym_WalkWalker{InIndex}"),
                InPostA, InPostB, k_AgentRadiusUu, k_WalkerHeightUu, Color,
                FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerGoalReached"),
                FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerGoalFailed")) == false)
        { return; }

        _PostPoints.Add(InPostA);
        _PostLabels.Add(InLabelA);
        _PostColors.Add(Color);

        _PostPoints.Add(InPostB);
        _PostLabels.Add(InLabelB);
        _PostColors.Add(Color);
    }

    // A struct cannot carry a UFUNCTION, so the crowd's signals are bound HERE and forwarded to the
    // set, which finds the walker they name by its entity handle.
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

    // One walker out of the set, laundered into a typed local so its plain (non-const) readers can be
    // called on it. Copied rather than referenced because everything asked of it here is read-only.
    private ECkGroundNavDemo_WalkerState Get_WalkerState(int32 InIndex)
    {
        if (InIndex < 0 || InIndex >= _Walkers.Get_Count())
        { return ECkGroundNavDemo_WalkerState::None; }

        return _Walkers.Get_State(InIndex);
    }

    private bool Get_WalkerHasWalked(int32 InIndex)
    {
        if (InIndex < 0 || InIndex >= _Walkers.Get_Count())
        { return false; }

        return _Walkers.Get_HasWalked(InIndex);
    }

    // ---- Tick ---------------------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        // Observes every walker, then draws its route and its body - all at zero lifetime, so a replan
        // never leaves the route it abandoned lying under the new one.
        _Walkers.Do_Tick();

        for (int32 Index = 0; Index < _PostPoints.Num(); Index++)
        {
            FLinearColor Color = _PostColors[Index];

            CkGroundNavDemo::Draw_GoalPost(_PostPoints[Index], _PostLabels[Index], Color);
        }

        CkGroundNavDemo::Draw_WorldCaption(Get_ScenePoint(k_CaptionPoint), Get_Caption());
    }

    // ---- The verdict ----------------------------------------------------------------------------------
    //
    // Three claims, one per walker, and the third INVERTS the sense of the other two: the pillar and
    // the ramp walker have to walk, the island walker has to be refused. Every one is a live readback
    // off the set. A walker that has not walked YET is not a failure - it is the second before its
    // first plan lands - so that case falls through to the pending text instead of colouring the row
    // red on the gym's own first frame.

    private TArray<FString> Get_VerdictFailures()
    {
        auto Failures = TArray<FString>();

        if (Get_WalkerState(0) == ECkGroundNavDemo_WalkerState::Failed)
        { Failures.Add("W0 has no route through the pillars"); }

        if (Get_WalkerState(1) == ECkGroundNavDemo_WalkerState::Failed)
        { Failures.Add("W1 has no route to the landing - the 40-degree plank should carry it"); }

        // The positive test, not "is it Failed yet": if the island walker has EVER been seen walking,
        // something joined the island to the slab, and that is the fault this scene is built to catch.
        if (_Walkers.Get_Count() > 2 && Get_WalkerHasWalked(2))
        { Failures.Add("W2 got a route to the island - the 300uu gap should refuse it"); }

        for (int32 Index = 3; Index < _Walkers.Get_Count(); Index++)
        {
            if (Get_WalkerState(Index) == ECkGroundNavDemo_WalkerState::Failed)
            { Failures.Add(f"W{Index} has no route west to east"); }
        }

        return Failures;
    }

    // Still on its way to an answer rather than standing on one: a walker that owes its first leg, or an
    // island walker whose refusal has not come back yet.
    private bool Get_VerdictIsPending()
    {
        if (_Walkers.Get_Count() == 0)
        { return true; }

        if (Get_WalkerHasWalked(0) == false)
        { return true; }

        if (_Walkers.Get_Count() > 1 && Get_WalkerHasWalked(1) == false)
        { return true; }

        if (_Walkers.Get_Count() > 2 && Get_WalkerState(2) != ECkGroundNavDemo_WalkerState::Failed)
        { return true; }

        return false;
    }

    private FString Get_VerdictLine(const TArray<FString>&in InFailures)
    {
        if (InFailures.Num() > 0)
        { return CkGroundNavGym::Get_VerdictText("", InFailures); }

        if (Get_VerdictIsPending())
        { return CkGroundNavDemo::Get_VerdictPendingText(_Field); }

        // Built from the clauses that apply, so the one-walker count claims only what it has on the
        // scene rather than naming a ramp and an island that are not standing.
        const auto Legs = _Walkers.Get_LegsCompleted();

        FString Text = f"OK - {Legs} legs walked";

        if (_Walkers.Get_Count() > 1)
        { Text += "; the ramp taken over the 40-degree plank"; }

        if (_Walkers.Get_Count() > 2)
        { Text += "; the island walker holds with no route, as it should"; }

        return Text;
    }

    // The one line a reader sees without looking at the panel, and the panel's own "This shows" row.
    private FString Get_Caption()
    {
        return "Walkers crossing a baked field - pillars routed around, the 40-degree plank taken, the 50-degree plank and the island refused";
    }

    // ---- Scene construction ----------------------------------------------------------------------

    private bool DoBuildScene()
    {
        // Guarded, not idempotent by luck: see _SceneSpawned. A restart keeps the scene it already
        // spawned, which is also the scene the volume was baked over.
        if (_SceneSpawned)
        { return true; }

        _SceneSpawned = true;

        // All of it goes into the Jolt static world through these calls - the volume bakes from that
        // world and from nothing else, so an actor that is visible but not baked is free space.
        //
        // Every box is attempted and the results are folded at the END rather than returned on the
        // first miss: Spawn_Box warns with the reason, so a run that lost two of them names both
        // instead of stopping at the first and leaving the rest unexplained. `Ok` is written LAST in
        // each fold so the spawn always runs.
        bool Ok = CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_SlabCentre), k_SlabScale);

        Ok = CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_Pillar0), k_PillarScale) && Ok;
        Ok = CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_Pillar1), k_PillarScale) && Ok;
        Ok = CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_Pillar2), k_PillarScale) && Ok;
        Ok = CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_Pillar3), k_PillarScale) && Ok;

        Ok = CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_LandingCentre), k_LandingScale) && Ok;

        Ok = CkGroundNavGym::Spawn_BoxRotated(this, Get_ScenePoint(k_RampLowerCentre),
            FRotator(k_RampLowerPitchDegrees, 0.0, 0.0), k_RampLowerScale) && Ok;
        Ok = CkGroundNavGym::Spawn_BoxRotated(this, Get_ScenePoint(k_RampUpperCentre),
            FRotator(k_RampUpperPitchDegrees, 0.0, 0.0), k_RampUpperScale) && Ok;

        Ok = CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_IslandCentre), k_IslandScale) && Ok;

        return Ok;
    }

    private void DoBringPlayerToViewpoint()
    {
        CkGroundNavGym::Request_FlyToStation(this, "GroundNavWalk",
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

    // ---- Control panel ---------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GROUNDNAV: WALK";
    }

    // Five lines and no readback block: the caption, the Verdict, the walkers, this gym's one key and
    // the shared picture key. What a Field or a Surface row would have said is in the Verdict when it
    // matters and in the log when it does not.
    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        const auto Failures = Get_VerdictFailures();

        auto Header = CkGroundNavDemo::Get_HeaderRows(Get_Caption(), Get_VerdictLine(Failures),
            Failures.Num() > 0, _Walkers.Get_StatusText());

        for (int32 Index = 0; Index < Header.Num(); Index++)
        { Rows.Add(Header[Index]); }

        Rows.Add(CkGym_Control::Cycle(EKeys::One, "1", "Walkers on the scene", Get_WalkerCountLabel()));
        Rows.Add(CkGroundNavDemo::Get_DrawModeRow(_DrawModeIndex));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (HasAuthority() == false)
        { return; }

        if (InRowIndex == k_Row_WalkerCount)
        {
            DoCycle_WalkerCount();
            return;
        }

        if (InRowIndex == k_Row_DrawMode)
        {
            _DrawModeIndex = (_DrawModeIndex + 1) % CkGroundNavGym::Get_DrawModeCount();

            if (_Field.Get_IsBuilt())
            { DoRefresh_Picture(); }

            return;
        }
    }
}
