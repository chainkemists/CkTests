class ACk_GroundNavGym_Routing_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- Where the scene stands ------------------------------------------------------------------
    //
    // Every dimension below is LOCAL to the scene, and the scene is placed off the station's own
    // footprint anchor rather than at a world constant: the station is placed by
    // Request_ApplyDefaultGridLayout, so a hardcoded world position is wrong the moment the grid
    // changes. Stations face world -X, so the scene is pushed into -X in front of the board.

    private const FVector k_SceneOffset = FVector(-2400.0, 0.0, 0.0);

    // ---- The slab ---------------------------------------------------------------------------------
    //
    // One slab carries all three questions this gym asks. Top face at the scene's Z 0, X +/-1600 and
    // Y +/-1200 - wide enough in X that the crossing route below spans four 800uu tiles, which is the
    // whole reason that route is worth drawing.
    //
    // Z scale must stay >= 0.5 - thinner slabs bake to zero walkable tiles.
    private const FVector k_SlabCentre = FVector(0.0, 0.0, -100.0);
    private const FVector k_SlabScale  = FVector(32.0, 24.0, 2.0);

    // ---- The ramp ---------------------------------------------------------------------------------
    //
    // Two planks in series, 200uu along the slope and 400uu wide, pitched either side of the default
    // profile's 45-degree slope limit: the lower one at 40 degrees is walkable and the upper one at 50
    // is not, so the ramp stops being ground half way up rather than at its foot.
    //
    // Each centre is the plank's foot plus half its length along (cos(pitch), 0, sin(pitch)):
    //   lower foot (-1400, 0)       + 100 * (0.766, 0.643) -> (-1323.4,  64.3), head (-1246.8, 128.6)
    //   upper foot (-1246.8, 128.6) + 100 * (0.643, 0.766) -> (-1182.5, 205.2), head (-1118.2, 281.8)
    //
    // The whole ramp tops out under 300uu on purpose: a debug field bake aimed at this band is 400uu
    // tall, so it shows the ramp whole rather than clipping its head and leaving the reader unable to
    // tell a rejected plank from one outside the region.

    private const float k_RampLowerPitchDegrees = 40.0f;
    private const float k_RampUpperPitchDegrees = 50.0f;
    private const FVector k_RampLowerCentre = FVector(-1323.4, 600.0, 64.3);
    private const FVector k_RampUpperCentre = FVector(-1182.5, 600.0, 205.2);
    private const FVector k_RampPlankScale  = FVector(2.0, 4.0, 0.4);

    // The two ramp probes: each plank's own MID-TOP, five-ish units clear of its upper face.
    //
    // A plank is 40uu thick, so its top face is 20uu out along its own normal - (-sin(pitch), 0,
    // cos(pitch)) - and each probe sits 25uu out, which is that half-thickness plus a little air:
    //   lower: (-1323.4, 64.3) + 25 * (-0.643, 0.766) -> (-1339.5,  83.5)
    //   upper: (-1182.5, 205.2) + 25 * (-0.766, 0.643) -> (-1201.7, 221.3)
    private const FVector k_RampLowerProbe = FVector(-1339.5, 600.0, 83.5);
    private const FVector k_RampUpperProbe = FVector(-1201.7, 600.0, 221.3);

    // Tight in Z on purpose. The slab's top face is 83uu below the LOWER probe and 221uu below the
    // upper one; a generous vertical search reaches past the plank being asked about and answers with
    // the slab, which reads as a success and says nothing about the slope limit. 40uu reaches each
    // plank's own face and nothing else.
    private const FVector k_ProbeHalfExtents = FVector(20.0, 20.0, 40.0);

    // ---- The multi-tile crossing --------------------------------------------------------------------
    //
    // 2800uu end to end over 800uu tiles, so four tiles lie under one corridor and a route that
    // disagreed with itself across a seam would show here and nowhere else.
    private const FVector k_CrossingWestPoint  = FVector(-1400.0, -600.0, 20.0);
    private const FVector k_CrossingEastPoint  = FVector(1400.0, -600.0, 20.0);
    private const FVector k_CrossingBakeCentre = FVector(0.0, -600.0, 120.0);

    // ---- The no-route pocket ------------------------------------------------------------------------
    //
    // 600uu square with 300uu of nothing between it and the slab's south edge: no seam can span a gap
    // with no ground in it, and nothing authors a link across it, so the island is baked ground that
    // no route can reach.
    private const FVector k_PocketCentre     = FVector(0.0, -1800.0, -100.0);
    private const FVector k_PocketScale      = FVector(6.0, 6.0, 2.0);
    private const FVector k_PocketProbeStart = FVector(0.0, -1000.0, 100.0);
    private const FVector k_PocketProbeGoal  = FVector(0.0, -1800.0, 100.0);

    // ---- The volume -----------------------------------------------------------------------------------
    //
    // The slab, the ramp standing on it, and the pocket island beyond its south edge - and nothing
    // else, because nothing else is in this gym's scene.
    private const FVector k_VolumeMin = FVector(-1800.0, -2300.0, -300.0);
    private const FVector k_VolumeMax = FVector(1800.0, 1400.0, 500.0);

    // The same 25uu lattice every GroundNav fixture in the corpus bakes on, fine enough that the
    // ramp's shorter plank is several cells of slope rather than one. The 800uu tiles are what put
    // four tiles under the crossing route. The agent is the default 34uu body at 180uu standing
    // height.
    private const float k_CellSizeUu        = 25.0f;
    private const float k_CellHeightUu      = 10.0f;
    private const float k_TileSizeUu        = 800.0f;
    private const float k_AgentRadiusUu     = 34.0f;
    private const float k_AgentHalfHeightUu = 90.0f;

    // 0.05s a poll, and this volume carries several times the tiles a single-deck one does, so it is
    // given a minute on the same NAMED condition before it reports that it gave up.
    private const int32 k_SettlePollCeiling = 1200;

    // Frames the ramp at the scene's north-west, the crossing corridor across the middle, and the
    // pocket island beyond the south edge, from above and behind the slab's south-east corner.
    private const FVector  k_ViewOffset   = FVector(2200.0, -1600.0, 1600.0);
    private const FRotator k_ViewRotation = FRotator(-32.0, 149.4, 0.0);

    // The draw mode a routing bake is worth looking at in: the tiles and the seams between them, so a
    // route drawn over the top can be seen crossing three of them.
    private const int32 k_TileDrawMode = 5;

    // ---- The debug bake the draw row runs ------------------------------------------------------------
    //
    // Only the REGION is stated here: the extent and height are sized to the crossing band rather than
    // to the viewer, so flying around changes what can be seen and never what was baked. Every filter -
    // the lattice, the 800uu tiles the four-tiles-under-one-corridor claim rests on, the agent capsule,
    // the slope limit the ramp is built around, the ledge sensitivity the slab and the pocket need
    // pinned off - is pushed from the volume by Request_BakeDebugFieldAt.
    private const float k_DebugBakeExtentUu = 1500.0f;
    private const float k_DebugBakeHeightUu = 400.0f;
    private const int32 k_DebugBakeMaxCells = 40000;

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Header and Status rows never reach Request_ControlActivated but they DO occupy an index. These
    // constants sit next to each other so a row inserted in one place and not renumbered here is a
    // visible edit rather than a silent off-by-one.
    //
    // The old single gym gave the crossing 6 and the pocket 7. They are renumbered here because a key
    // set only has to be unique within one gym, and 1-3 is what this one's three rows are worth.

    private const int32 k_Row_Provider = 6;
    private const int32 k_Row_PathDraw = 10;
    private const int32 k_Row_Reprobe  = 14;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FVector _Origin = FVector::ZeroVector;
    private bool _GeometryIsBuilt = false;

    private FCkGroundNavGym_Field _Field;

    // The two probe entities. One each, re-asked rather than re-minted: a fresh entity per press would
    // leave one behind for every press, and each status row reads the LAST answer its own probe was
    // given. Neither is a mirror - the STATUS is read live off the entity through
    // utils_nav::Get_PathStatus every time a row or the verdict asks.
    private FCk_Handle _CrossingProbeEntity;
    private FCk_Handle _PocketProbeEntity;

    // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and the slab, the two planks and
    // the island are spawned actors that nothing here holds a handle to - so a second pass would stack
    // a whole second scene into the Jolt static world, invisible to every row. Spawned once per
    // controller.
    private bool _SceneSpawned = false;

    // The gym's own arithmetic, and the only two counters here. Nothing outside this gym counts how
    // many times a row asked for a route.
    private int32 _CrossingProbesRun = 0;
    private int32 _PocketProbesRun = 0;

    // Nothing outside this gym holds this. ck.GroundNav.PathAt is a COMMAND, not a cvar, so there is
    // no console state saying whether a crossing route is on screen - only the fact that every other
    // bake clears the drawing, which is what puts this back to false.
    private bool _PathDrawEnabled = false;

    // ---- Station ---------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // No Transform: the base grid places it, and the scene is built off the anchor it lands on.
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavRouting");
        Station.AutoSize = true;
        Station.Title = FText::FromString("GroundNav - Routing");

        auto Description = TArray<FText>();

        Description.Add(FText::FromString("One slab and three questions about what a GroundNav field says: which ground is walkable at all, whether a route holds together across tile seams, and what an unreachable place answers. All three are asked of a volume this gym mints and bakes for itself - a route is asked OF a volume, and a debug bake belongs to none."));

        Description.Add(FText::FromString("THE RAMP, north-west: two planks in series climbing west to east, the lower at 40 degrees and the upper at 50. The volume's agent profile keeps the default 45-degree slope limit, so the join between them is where the ramp stops being ground. The VERDICT row projects a point onto each plank's top face through the provider-neutral facade and expects exactly one of them to answer."));

        Description.Add(FText::FromString("Type ck.GroundNav.Debug.Mode 3 and then ck.GroundNav.BakeFieldAt over the ramp band to see it as the filters do: the lower plank survives, the upper one is red. The draw row on 2 pushes every bake tunable off this gym's own volume before it bakes, so the picture it leaves behind already carries the 45-degree limit the ramp is built around - that row leaves the mode on 5, so set it back to 3 before typing your own bake and you are asking the same filters the same question."));

        Description.Add(FText::FromString("THE CROSSING, across the middle: a 2800uu route over 800uu tiles, so four tiles lie under one corridor. Press 2 and the bake it runs sets draw mode 5, so the tiles and their seams are drawn under what it asks for - the corridor the search walked, and over that the string-pulled route an agent would actually take. A tiled bake that disagreed with itself would show as a kink at a seam and nowhere else."));

        Description.Add(FText::FromString("The draw row bakes a FIELD over the crossing band before it asks, and that is not incidental. ck.GroundNav.PathAt reads the DEBUG field, not a volume's published one, and a region bake produces no field to path through at all. The bake is pinned to the band rather than to your pawn, so flying around changes what you can see and never what was baked."));

        Description.Add(FText::FromString("THE POCKET, beyond the south edge: a 600uu island with 300uu of nothing between it and the slab. It is inside the volume and it bakes to real walkable ground - but no seam can span a gap with no ground in it, and nothing authors a link across it, so there is no way to reach it."));

        Description.Add(FText::FromString("Both routes are asked for with partial paths OFF, and for the pocket that is the whole station: with them on, a route that cannot reach the island answers with the closest point it COULD reach and reads as a success. Failed is the right answer there; Ready or Partial would mean something joined the island to the slab."));

        Description.Add(FText::FromString("Both probes are issued for you as soon as the field publishes, so the VERDICT row fills without a keypress. Press 3 to re-run them - after switching the provider on 1, or after anything else that would change the answer."));

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
            ck::groundnav::Warning("GroundNav routing gym: PC entity invalid; cannot start");
            return;
        }

        _Origin = Get_StationAnchorLocation("GroundNavRouting", ECk_GymStation_Anchor::FootprintCenter);

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav routing gym: the scene failed to bake into the Jolt static world - the field has nothing to bake over", n"GroundNavGym.Scene", 10.0);
        }

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        DoArm_Field();

        ck::groundnav::Log("GroundNav routing gym: scene built - both probes are issued once the field settles");
    }

    // Scene-local to world. Everything the gym spawns, bakes, probes and draws goes through here, so
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

        // The slab and the pocket both END inside the volume, so at the default sensitivity the ledge
        // filter would demote their whole perimeter - and the pocket, 600uu square, would lose its top
        // outright and fail its probe for a reason that has nothing to do with reachability.
        //
        // The slope limit is deliberately left at the profile default of 45 degrees: that number is
        // what the ramp is built around, and moving it would make the ramp say nothing.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(Get_ScenePoint(k_VolumeMin), Get_ScenePoint(k_VolumeMax));

        _Field.Request_Mint(_PcEntity, n"GroundNavGym_RoutingField", Bounds, Config, Profile,
            NAME_None, k_SettlePollCeiling,
            FCk_Delegate_Request_OnCompleted(this, n"OnFieldBuildCompleted"),
            FCk_Delegate_Timer(this, n"OnFieldSettlePoll"));
    }

    // The one named condition worth waiting on after a bake: nothing in flight and nothing pending, so
    // the field the volume publishes is the one every query answers from. Both probes are only worth
    // firing once that is true - a route asked for over a field still being written answers about the
    // field that was, not the one that is.
    UFUNCTION()
    private void OnFieldSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Step = _Field.Do_PollSettle();

        if (Step == ECkGroundNavGym_Settle::Settled)
        {
            DoProbe_Routes();
            return;
        }

        if (Step == ECkGroundNavGym_Settle::GaveUp)
        {
            _Field.Set_Stage("the surface never settled - neither route was probed");
            ck::groundnav::Log("GroundNav routing gym: the field never settled - the crossing and the pocket were not probed");
        }
    }

    UFUNCTION()
    private void OnFieldBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Field.Notify_BuildCompleted(InResult);
    }

    // ---- The provider row ------------------------------------------------------------------------

    private void DoCycle_Provider()
    {
        CkGroundNavGym::Request_CycleProvider();

        ck::groundnav::Log("GroundNav routing gym: provider switched - the volume stays baked either way, and the SURFACE row says which backend is answering now. Press 3 to re-ask both routes of the new one.");
    }

    // ---- The crossing draw -------------------------------------------------------------------------

    // ck.GroundNav.PathAt reads the DEBUG field and not a volume's published one, so this bakes a field
    // over the crossing band before it asks: a region bake produces no field to path through at all,
    // and a field baked anywhere else has no ground under this route.
    private void DoDraw_CrossingPath()
    {
        CkGroundNavGym::Request_BakeDebugFieldAt(_Field, Get_ScenePoint(k_CrossingBakeCentre),
            k_DebugBakeExtentUu, k_DebugBakeHeightUu, k_DebugBakeMaxCells, k_TileDrawMode);

        CkGroundNavGym::Request_DrawPathAt(
            Get_ScenePoint(k_CrossingWestPoint), Get_ScenePoint(k_CrossingEastPoint));

        _PathDrawEnabled = true;
    }

    // Turning it off is a Clear and not a re-bake: a bake replaces the FIELD group and leaves the
    // QUERY group standing, so the route would go on being drawn over fresh tiles.
    private void DoToggle_CrossingPath()
    {
        if (_PathDrawEnabled)
        {
            CkGroundNavGym::Request_ClearDebugDraw();
            _PathDrawEnabled = false;
            return;
        }

        DoDraw_CrossingPath();
    }

    // ---- The two probes ------------------------------------------------------------------------------
    //
    // Both go through the PROVIDER-NEUTRAL facade - utils_nav::Request_FindPath - which is the same
    // call the crowd makes: it names a start, a goal and nothing about which backend answers it. That
    // is what makes the provider row on key 1 worth having, and what makes an answer here a statement
    // about the world's chosen surface rather than about GroundNav's internals.

    private void DoProbe_Routes()
    {
        DoProbe_Crossing();
        DoProbe_Pocket();
    }

    private void DoProbe_Crossing()
    {
        if (ck::Is_NOT_Valid(_CrossingProbeEntity))
        {
            _CrossingProbeEntity = DoMake_ProbeEntity(n"GroundNavGym_CrossingProbe",
                Get_ScenePoint(k_CrossingWestPoint));
        }

        // Partial paths OFF here too, for a different reason than the pocket's: the question is whether
        // the route holds together over four tiles, and a partial answer that stopped at the first seam
        // would still read as a success.
        auto Request = FCk_Request_Nav_FindPath(Get_ScenePoint(k_CrossingEastPoint));
        Request.Set_AllowPartialPath(false);

        utils_nav::Request_FindPath(_CrossingProbeEntity, Request);

        _CrossingProbesRun += 1;
    }

    // One probe entity, re-asked rather than re-minted: a fresh entity per press would leave one behind
    // for every press, and the status row reads the LAST answer this one was given.
    private void DoProbe_Pocket()
    {
        if (ck::Is_NOT_Valid(_PocketProbeEntity))
        {
            _PocketProbeEntity = DoMake_ProbeEntity(n"GroundNavGym_PocketProbe",
                Get_ScenePoint(k_PocketProbeStart));
        }

        // Partial paths OFF, and that is the whole pocket: with them on, a route that cannot reach the
        // island answers with the closest point it COULD reach and reads as a success. The question
        // being asked is whether the island is reachable at all, and Failed is its answer.
        auto Request = FCk_Request_Nav_FindPath(Get_ScenePoint(k_PocketProbeGoal));
        Request.Set_AllowPartialPath(false);

        utils_nav::Request_FindPath(_PocketProbeEntity, Request);

        _PocketProbesRun += 1;
    }

    // A probe is a transform to plan FROM and the ability to plan at all - nothing else. The transform
    // is the start point: the facade plans from the entity's own place unless a request overrides it.
    private FCk_Handle DoMake_ProbeEntity(FName InDebugName, FVector InStart)
    {
        // Explicitly typed rather than auto: `auto` preserves const, and every call below wants a
        // non-const handle.
        FCk_Handle Probe = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        Probe.Set_DebugName(InDebugName);

        FVector Start = InStart;

        utils_transform::Add(Probe,
            FTransform(FRotator::ZeroRotator, Start, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_ground_nav_path::Add(Probe,
            FCk_Fragment_GroundNavPath_ParamsData(k_AgentRadiusUu));

        return Probe;
    }

    // ---- The verdict -------------------------------------------------------------------------------
    //
    // Every criterion is a LIVE readback and no member behind any of them mirrors engine state: the
    // provider comes off the facade, the field's built flag and tile count off the volume, both ramp
    // answers off the provider-neutral projection, and both route answers off each probe entity's own
    // result slot. The two counters this gym does keep - how many times each probe was asked - are its
    // own arithmetic and no criterion reads them.
    //
    // A probe that has not answered yet (None, never asked; Pending, in flight) is NOT a failure. It is
    // the one state where there is nothing to judge, and calling it red would paint the row for the
    // second or two between the field publishing and the search returning.

    // Split in two so the row can colour itself from the SAME evaluation it prints, rather than running
    // the two facade projections twice a frame to ask the string what it says.
    private TArray<FString> Get_VerdictFailures()
    {
        auto Failures = TArray<FString>();

        const auto Provider = utils_nav_surface::Get_Provider();

        // First and alone. On any other backend the volume this gym baked is not what answers, so every
        // criterion below would be a statement about something else.
        if (Provider != ECk_NavSurface_Provider::GroundNav)
        {
            Failures.Add(f"provider is {Provider} - the volume answers nothing");
            return Failures;
        }

        if (_Field.Get_IsBuilt() == false)
        { return Failures; }

        // The ramp. One filter, two answers - which is what makes the pair a check rather than a
        // reading: the lower plank clears the profile's 45-degree limit and the upper one does not.
        const auto LowerStatus = CkGroundNavGym::Get_ProjectedStatus(
            Get_ScenePoint(k_RampLowerProbe), k_ProbeHalfExtents);

        if (LowerStatus != ECk_NavSurface_QueryStatus::Success)
        { Failures.Add("ramp lower not ground"); }

        const auto UpperStatus = CkGroundNavGym::Get_ProjectedStatus(
            Get_ScenePoint(k_RampUpperProbe), k_ProbeHalfExtents);

        if (UpperStatus == ECk_NavSurface_QueryStatus::Success)
        { Failures.Add("ramp upper is ground"); }

        // The crossing. A route over four tiles is only a claim about seams if the field HAS seams, so
        // the tile count the volume published is read alongside the route's own status.
        //
        // The corridor's own tile identities are not readable here: FFragment_GroundNavPath_Diagnostics
        // exposes the links a corridor crosses and its epoch, and nothing exposes which tiles it walked.
        // The volume's built-tile count is what can honestly be asked instead.
        const auto BuiltTiles = utils_ground_nav_volume::Get_BuiltTileCount(_Field.Get_Volume());

        if (BuiltTiles < 2)
        { Failures.Add(f"the field built {BuiltTiles} tile(s) - the crossing cannot span four"); }

        const auto CrossingStatus = utils_nav::Get_PathStatus(_CrossingProbeEntity);

        if (Get_ProbeHasAnswered(CrossingStatus))
        {
            if (CrossingStatus != ECk_Nav_PathStatus::Ready)
            { Failures.Add(f"crossing {CrossingStatus}"); }
            else if (Get_CrossingWaypointCount() <= 0)
            { Failures.Add("crossing Ready with 0 waypoints"); }
        }

        // The pocket. Failed is the CONTRACT, not a disappointment: an island with no seam and no link,
        // asked for with partial paths off, must answer Failed. Ready or Partial would mean something
        // joined the island to the slab.
        const auto PocketStatus = utils_nav::Get_PathStatus(_PocketProbeEntity);

        if (Get_ProbeHasAnswered(PocketStatus) && PocketStatus != ECk_Nav_PathStatus::Failed)
        { Failures.Add(f"pocket answered {PocketStatus}"); }

        return Failures;
    }

    private FString Get_VerdictLine(const TArray<FString>&in InFailures)
    {
        // ONE reason, not all of them. The row is one line on a HUD, and the first failing criterion is
        // the one to go and look at; the rest are read off the section rows below it.
        if (InFailures.Num() > 0)
        {
            auto First = TArray<FString>();
            First.Add(InFailures[0]);

            return CkGroundNavGym::Get_VerdictText("", First);
        }

        if (_Field.Get_IsBuilt() == false)
        { return "field not built"; }

        const auto CrossingStatus = utils_nav::Get_PathStatus(_CrossingProbeEntity);
        const auto PocketStatus = utils_nav::Get_PathStatus(_PocketProbeEntity);

        if (Get_ProbeHasAnswered(CrossingStatus) == false || Get_ProbeHasAnswered(PocketStatus) == false)
        { return f"field built - crossing {CrossingStatus}, pocket {PocketStatus}"; }

        const auto Waypoints = Get_CrossingWaypointCount();

        return f"OK - ramp, crossing ({Waypoints} wps), pocket";
    }

    // None is "never asked" and Pending is "in flight". Neither is a verdict, and the enum carries no
    // other way to say so.
    private bool Get_ProbeHasAnswered(ECk_Nav_PathStatus InStatus)
    {
        return InStatus != ECk_Nav_PathStatus::None && InStatus != ECk_Nav_PathStatus::Pending;
    }

    private int32 Get_CrossingWaypointCount()
    {
        return utils_nav::Get_PathResult(_CrossingProbeEntity).Get_Waypoints().Num();
    }

    // ---- Scene construction ----------------------------------------------------------------------

    private bool DoBuildScene()
    {
        // Guarded, not idempotent by luck: see _SceneSpawned. A restart keeps the scene it already
        // spawned, which is also the scene the volume was baked over.
        if (_SceneSpawned)
        { return true; }

        _SceneSpawned = true;

        // The slab, the two ramp planks standing on it, then the pocket island beyond its south edge.
        // All of it goes into the Jolt static world through the same call - the volume bakes from that
        // world and from nothing else, so an actor that is visible but not baked is free space.
        if (CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_SlabCentre), k_SlabScale) == false)
        { return false; }

        if (CkGroundNavGym::Spawn_BoxRotated(this, Get_ScenePoint(k_RampLowerCentre),
                FRotator(k_RampLowerPitchDegrees, 0.0, 0.0), k_RampPlankScale) == false)
        { return false; }

        if (CkGroundNavGym::Spawn_BoxRotated(this, Get_ScenePoint(k_RampUpperCentre),
                FRotator(k_RampUpperPitchDegrees, 0.0, 0.0), k_RampPlankScale) == false)
        { return false; }

        if (CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_PocketCentre), k_PocketScale) == false)
        { return false; }

        return true;
    }

    private void DoBringPlayerToViewpoint()
    {
        CkGroundNavGym::Request_FlyToStation(this, "GroundNavRouting",
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
        return "GROUNDNAV: ROUTING";
    }

    // Readback: every value column below is asked for as the row is built - the field's counts off the
    // volume, the provider and its health off the facade, both ramp answers off the projection, both
    // route answers off their probe entities. Two columns are NOT read, and each says so where it
    // stands: how many times each probe has been asked (this gym's own arithmetic), and whether the
    // crossing route is on screen (PathAt is a command, not a cvar).
    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        const auto VerdictFailures = Get_VerdictFailures();

        Rows.Add(CkGym_Control::Header("SCENE"));
        Rows.Add(CkGym_Control::Status("Verdict", Get_VerdictLine(VerdictFailures), VerdictFailures.Num() > 0));
        Rows.Add(CkGym_Control::Status("Geometry",
            CkGroundNavGym::Get_GeometryStatusText(_GeometryIsBuilt,
                "a 3200x2400 slab, a two-plank ramp on it, and a 600uu island 300uu clear of its south edge"),
            _GeometryIsBuilt == false));

        Rows.Add(CkGym_Control::Header("FIELD - one volume over the slab, the ramp and the island"));
        Rows.Add(CkGym_Control::Status("Field", _Field.Get_FieldStatusText(), _Field.Get_IsBuilt() == false));
        Rows.Add(CkGym_Control::Status("Surface", CkGroundNavGym::Get_SurfaceStatusText()));
        Rows.Add(CkGym_Control::Cycle(EKeys::One, "1",
            "Provider (a per-WORLD choice - the volume here only answers on GroundNav)",
            CkGroundNavGym::Get_ProviderLabel()));

        Rows.Add(CkGym_Control::Header("RAMP - two planks at 40 then 50 degrees, either side of the 45 limit"));
        Rows.Add(CkGym_Control::Status("Ramp", Get_RampStatus()));

        Rows.Add(CkGym_Control::Header("CROSSING - 2800uu over 800uu tiles, so four tiles under one corridor"));
        Rows.Add(CkGym_Control::Toggle(EKeys::Two, "2",
            f"Draw the crossing route (bakes a FIELD over that band first, at draw mode {k_TileDrawMode} so the tiles and seams are under it)",
            _PathDrawEnabled));
        Rows.Add(CkGym_Control::Status("Crossing", Get_CrossingStatus()));

        Rows.Add(CkGym_Control::Header("NO-ROUTE POCKET - an island 300uu clear of the slab"));
        Rows.Add(CkGym_Control::Status("Pocket", Get_PocketStatus()));

        Rows.Add(CkGym_Control::Action(EKeys::Three, "3",
            "Re-ask both routes with partial paths OFF (they are asked once for you when the field publishes)"));

        return Rows;
    }

    // Both answers where they are shown, never remembered: the projection is the same call the verdict
    // makes, so the row and the verdict cannot disagree about what the slope limit did.
    private FString Get_RampStatus()
    {
        const auto Lower = CkGroundNavGym::Get_ProjectedStatus(
            Get_ScenePoint(k_RampLowerProbe), k_ProbeHalfExtents);

        const auto Upper = CkGroundNavGym::Get_ProjectedStatus(
            Get_ScenePoint(k_RampUpperProbe), k_ProbeHalfExtents);

        return f"lower plank (40 deg) projects {Lower} - upper plank (50 deg) projects {Upper} - the profile's slope limit is the authored default of 45";
    }

    private FString Get_CrossingStatus()
    {
        if (_CrossingProbesRun == 0)
        { return "not probed yet"; }

        const auto Status = utils_nav::Get_PathStatus(_CrossingProbeEntity);
        const auto Waypoints = Get_CrossingWaypointCount();
        const auto BuiltTiles = utils_ground_nav_volume::Get_BuiltTileCount(_Field.Get_Volume());

        return f"{_CrossingProbesRun} probes - last status {Status} - {Waypoints} waypoints over a field of {BuiltTiles} built tiles (partial paths OFF)";
    }

    private FString Get_PocketStatus()
    {
        if (_PocketProbesRun == 0)
        { return "not probed yet"; }

        const auto Status = utils_nav::Get_PathStatus(_PocketProbeEntity);

        return f"{_PocketProbesRun} probes - last status {Status} (Failed is what an island with no seam and no link is supposed to answer)";
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

        if (InRowIndex == k_Row_PathDraw)
        {
            DoToggle_CrossingPath();
            return;
        }

        if (InRowIndex == k_Row_Reprobe)
        {
            DoProbe_Routes();
            return;
        }
    }
}
