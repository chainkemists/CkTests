class ACk_GroundNavGym_Links_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- Where the scene stands ------------------------------------------------------------------
    //
    // Every dimension below is LOCAL to the scene, and the scene is placed off the station's own
    // footprint anchor rather than at a world constant: the station is placed by
    // Request_ApplyDefaultGridLayout, so a hardcoded world position is wrong the moment the grid
    // changes. Stations face world -X, so the scene is pushed into -X in front of the board.

    private const FVector k_SceneOffset = FVector(-1200.0, 0.0, 0.0);

    // ---- Scene constants -------------------------------------------------------------------------

    // The ground the deck stands on and the links land on. Z scale must stay >= 0.5 - thinner slabs
    // bake to zero walkable tiles. The walkable surface is at the actor origin, so the slab hangs
    // below the scene's Z 0.
    private const FVector k_FloorCentre = FVector(0.0, 0.0, 0.0);
    private const FVector k_FloorScale  = FVector(14.0, 14.0, 0.5);

    // 400 x 400 x 200 standing on the floor - X/Y +/-200, top face at Z 200. The Z scale is 2.0, well
    // past the 0.5 below which a slab bakes to zero walkable tiles.
    private const FVector k_DeckCentre = FVector(0.0, 0.0, 100.0);
    private const FVector k_DeckScale  = FVector(4.0, 4.0, 2.0);

    // The deck and the floor around it, stopping short of the floor's own perimeter cliff so nothing
    // in this gym's answers is about the edge of the ground it stands on.
    private const FVector k_VolumeMin = FVector(-650.0, -650.0, -100.0);
    private const FVector k_VolumeMax = FVector(650.0, 650.0, 400.0);

    // The DROP: off the deck's +X edge and down onto the floor beyond it. One-way, because walking off
    // a ledge is not the same act as climbing back up it - that is what the ladder is for.
    private const FVector k_DropStart = FVector(140.0, 0.0, 200.0);
    private const FVector k_DropEnd   = FVector(320.0, 0.0, 0.0);

    // The LADDER: off the floor south of the deck and up onto its top face. Priced at twice its own
    // span, so a route that has any way round prefers the way round; narrowed to 40uu of clearance,
    // which still admits the 34uu default agent and refuses anything wider.
    private const FVector k_LadderStart = FVector(0.0, -260.0, 0.0);
    private const FVector k_LadderEnd   = FVector(0.0, -140.0, 200.0);

    private const float k_LadderMultiplier  = 2.0f;
    private const float k_LadderClearanceUu = 40.0f;

    // The station's own bake, deliberately the same shape every GroundNav fixture in the corpus uses.
    // LedgeSensitivity is pinned off: the deck is a 400uu square that drops 200uu on all four sides,
    // and the ledge filter at its default would demote its whole top - leaving the two links with
    // nothing to land on for a reason that has nothing to do with links.
    private const float k_CellSizeUu        = 25.0f;
    private const float k_CellHeightUu      = 10.0f;
    private const float k_TileSizeUu        = 500.0f;
    private const float k_AgentRadiusUu     = 34.0f;
    private const float k_AgentHalfHeightUu = 90.0f;

    // 0.05s a poll, so this is thirty seconds of waiting on a NAMED condition before the gym gives up
    // and says so in its own status row rather than hanging silently.
    private const int32 k_SettlePollCeiling = 600;

    // Frames the deck, the drop's landing and the ladder's foot from the scene's south-east.
    private const FVector  k_ViewOffset   = FVector(500.0, -700.0, 500.0);
    private const FRotator k_ViewRotation = FRotator(-19.0, 125.5, 0.0);

    // The draw mode this gym is worth looking at in: links over the dimmed plates they join.
    private const int32 k_LinkDrawMode = 7;

    // ---- The debug bake the gym runs for the reader --------------------------------------------------
    //
    // The retained draw is COMMAND-driven: the mode selects what a bake draws and no sink redraws on
    // its own, so plates appear only after ck.GroundNav.BakeFieldAt and links only after
    // ck.GroundNav.LinksAt. Both are run for the reader, aimed at the deck.
    //
    // The extent is a half-extent, and 800 covers the floor's own 1400uu square with room to spare -
    // 1600uu of span on the debug bake's 25uu lattice is about four thousand columns, well inside the
    // ceiling. The height is centred on the deck's own centre, so the picture reaches from under the
    // floor to over the deck's top face and both plates the links join are in it.
    //
    // Only the REGION is stated here. Every filter the bake runs - the lattice, the agent capsule, the
    // slope limits, the ledge sensitivity this deck needs pinned off - is pushed from the volume by
    // Request_BakeDebugFieldAt, so the picture and the rows cannot describe different fields.
    private const float k_DebugBakeExtentUu = 800.0f;
    private const float k_DebugBakeHeightUu = 400.0f;
    private const int32 k_DebugBakeMaxCells = 40000;

    // A link request is DEFERRED and the colours LinksAt draws come off the field the DERIVE publishes
    // afterwards, so the overlay refresh waits on a named condition rather than a hop count: the
    // volume's build epoch has moved past the one read when the request went in, and the surface has
    // gone quiet again. At 0.05s a poll this ceiling is ten seconds, after which the overlays are
    // refreshed anyway so a toggle the derive never answered still leaves the reader looking at what
    // the field actually holds.
    private const int32 k_OverlayPollCeiling = 200;

    // ---- The walker ------------------------------------------------------------------------------
    //
    // One crowd body ping-ponging between a point on the floor west of the deck and the deck's top
    // face. The deck stands 200uu clear of the floor on all four sides and nothing ramps up to it, so
    // its top is an ISLAND: the only way up is the ladder off the south face and the only way down is
    // the drop off the east edge. A route between these two points that crosses no link is a route
    // that could not exist.
    //
    // Both points are 100uu above the ground under them, which is where a 180uu body's centre stands.
    // Neither is anywhere near the station board - the floor stops 500uu short of it.
    private const FVector k_WalkerFloorPoint = FVector(-450.0, 0.0, 100.0);
    private const FVector k_WalkerDeckPoint  = FVector(0.0, 0.0, 300.0);

    // The same body the volume was baked for: 34uu is what the ladder's 40uu of clearance admits, and
    // 180uu is twice the profile's own half-height.
    private const float k_WalkerHeightUu = 180.0f;

    // ---- The walker's route, drawn ------------------------------------------------------------------
    //
    // Drawn per frame at zero duration rather than retained: this is the walker's OWN installed route,
    // it is replaced on every replan, and a persistent line would leave the previous route lying under
    // the new one. The link segments get their own colour, which is the whole point of the drawing -
    // the deck top is reachable over a link and no other way, so the route's link half is the part
    // worth seeing.
    private const float k_RouteLineThickness = 5.0f;
    private const float k_RouteRiseUu = 15.0f;

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Header and Status rows never reach Request_ControlActivated but they DO occupy an index. Every
    // keyed row sits ABOVE the resolution block, and that is not a preference: how many resolution
    // rows there are depends on how many records the volume holds, so a keyed row placed after them
    // would move between frames and the panel dispatches on the index.

    private const int32 k_Row_LinksToggle = 6;
    private const int32 k_Row_Walker      = 8;
    private const int32 k_Row_RouteDraw   = 10;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FVector _Origin = FVector::ZeroVector;
    private bool _GeometryIsBuilt = false;

    private FCkGroundNavGym_Field _Field;

    // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and the floor and the deck are
    // spawned actors that nothing here holds a handle to - so a second pass would stack a whole second
    // scene into the Jolt static world, invisible to every row. Spawned once per controller.
    private bool _SceneSpawned = false;

    private FCk_Handle _DropEntity;
    private FCk_Handle _LadderEntity;

    // The batch's own completion. ONE delegate for both links, which is the only thing the batch
    // adds over two single requests - the drain takes the whole queue in a pass and the derive tag
    // is idempotent, so two singles landing in one tick already cost exactly one derive.
    private int32 _BatchCompletions = 0;
    private ECk_Request_OperationResult _LastBatchResult = ECk_Request_OperationResult::Failed;

    private bool _LinksAuthored = false;

    // The one body on the scene. The PLANNER handle is kept alongside the agent because
    // Get_LinksOnPath is asked of the planner and of nothing else - the crowd's own GroundNav dispatch
    // would compose one silently, and a feature added in there hands this gym nothing to hold.
    private FCk_Handle _WalkerEntity;
    private FCk_Handle_CrowdAgent _Walker;
    private FCk_Handle_GroundNavPath _WalkerPlanner;

    // Whether a live readback of the agent has EVER said Walking. A snapshot of a readback and not a
    // mirror of one: the movement state says what the body is doing now, and nothing in
    // ECk_CrowdAgent_MovementState says whether it has ever started. The verdict needs the difference -
    // a body spawned this frame reads Idle until the crowd has planned it a corridor, which is pending
    // and not a fault.
    private bool _WalkerHasWalked = false;

    // The walker asked for a goal it could not reach and is now standing still. Set by the crowd's own
    // OnGoalFailed and cleared by the retry, so it is a record of an EVENT the movement enum cannot
    // report afterwards rather than a mirror of a state.
    //
    // A failure with the links disabled is the CONTRACT - the deck top is an island - so the retry is
    // never issued from the callback. It is issued from the overlay refresh's settled step AND only on
    // the enable half of the toggle, which is the moment a previously impossible goal can have become
    // possible. Retrying on the callback, or on a disable, would spin a plan-fail-plan loop for as long
    // as the links stayed off.
    private bool _WalkerAwaitsRetry = false;

    // Nothing outside this gym holds this: the route below is drawn per frame at zero duration, so
    // there is no world state saying whether it is on - only whether this controller is still drawing.
    private bool _RouteDrawEnabled = false;

    // The deferred overlay redraw a link request owes. Armed at the request, fires a publish later.
    private FCkGroundNavGym_OverlayRefresh _OverlayRefresh;

    // ---- Station ---------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // No Transform: the base grid places it, and the scene is built off the anchor it lands on.
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavLinks");
        Station.AutoSize = true;
        Station.Title = FText::FromString("GroundNav - Nav Links");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("A deck standing on its own floor, joined to the ground beside it by two authored navigation links: a one-way DROP off the deck's east edge, and a one-way LADDER back up its south face. Both are authored on a volume this gym bakes for itself - a link has to be authored ON one, and a debug bake belongs to none."));
        Description.Add(FText::FromString("Nothing here has to be typed. As soon as the field publishes the gym runs a debug bake over the deck at draw mode 7 and then ck.GroundNav.LinksAt at the same point, so the plates are on the ground and both links are drawn over them: green traversable, grey disabled, orange an end over ground nobody has baked, red an end with no ground under it. The bake is a PICTURE that no volume holds; the link colours are read off the PUBLISHED field, which is why they are re-drawn every time a record changes."));
        Description.Add(FText::FromString("Press U to disable both links and again to re-enable them. A disabled link is invisible to search and to reachability, and the LINKS rows below report each one's live state, read off the volume rather than remembered. The links redraw a moment later rather than at the keypress - a link request is deferred, and the colours only become the new state's once the derive has republished the field."));
        Description.Add(FText::FromString("Press 1 to put a crowd walker on the scene. It ping-pongs between a point on the floor west of the deck and the deck's top face, and because the deck stands 200uu clear of the floor on all four sides that round trip has to climb the LADDER up the south face and take the DROP off the east edge. The WALKER row reads its movement state and the link ids its current route steps onto, straight off its planner."));
        Description.Add(FText::FromString("Disable the links while it is walking and its next goal FAILS, which is the contract and not a fault - the deck top is then an island. It holds where it stopped and the row says so; it is re-asked the moment the links change again, and not before, because re-asking on the failure itself would be a plan-fail-plan loop for as long as the links stayed off."));
        Description.Add(FText::FromString("Press 2 to draw the walker's own route: the waypoints its planner currently holds, drawn fresh every frame, with the segments that step onto a link in orange. It is deliberately not ck.GroundNav.PathAt - that command searches the DEBUG field, which is baked from a region and an agent profile and carries no link records at all, so a route drawn out of it could never cross the drop or the ladder. The row is disabled while there is no walker, because then there is no route."));
        Description.Add(FText::FromString("Under the toggle there is one RESOLUTION row per link, straight from Get_LinkResolution: what each end projected onto, the flat plate it landed in, and whether the record resolved and is live. Every index in it is valid only against the field currently published, which is why the row is rebuilt each frame rather than remembered."));
        Description.Add(FText::FromString("The ladder is priced at twice its own straight-line span and narrowed to 40uu of clearance; the drop is priced at its span and admits any agent. A link never costs less than its own length - that is what keeps the search's Euclidean heuristic admissible."));
        Description.Add(FText::FromString("The VERDICT row at the top is the whole station in one line: both records resolved and live when the toggle is on, both dead when it is off, and the id of the one that disagrees otherwise. Once a walker has been seen moving it adds the other half of the claim, and that half INVERTS with the toggle - with the links live its route must name one of them, and with them disabled its route must FAIL, because the deck top is then an island. Between the two it reads 'walker: replanning' and judges nothing: a toggle republishes the field, and until it has the body has no route worth calling right or wrong."));
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
            ck::groundnav::Warning("GroundNav links gym: PC entity invalid; cannot start");
            return;
        }

        _Origin = Get_StationAnchorLocation("GroundNavLinks", ECk_GymStation_Anchor::FootprintCenter);

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav links gym: the scene failed to bake into the Jolt static world - the field has nothing to bake over", n"GroundNavGym.Scene", 10.0);
        }

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        DoArm_Field();

        ck::groundnav::Log("GroundNav links gym: scene built - the drop and the ladder are authored once the field settles");
    }

    // Scene-local to world. Everything the gym spawns, bakes and authors goes through here, so the
    // scene is one translation away from the station the grid layout happened to place.
    private FVector Get_ScenePoint(FVector InLocal)
    {
        return _Origin + k_SceneOffset + InLocal;
    }

    // ---- The links volume ------------------------------------------------------------------------

    private void DoArm_Field()
    {
        if (_GeometryIsBuilt == false)
        {
            _Field.Set_Stage("the scene is not in the Jolt static world - nothing to bake over");
            return;
        }

        // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and a field is minted ONCE -
        // so the mint below is turned away the second time and the settle poll never fires again. The
        // retained draw is command-driven and nothing redraws on its own, so a restart that only
        // re-minted would leave the reader looking at whatever the last gym in this world drew. The
        // field is already standing and already settled, so the picture is owed here.
        if (_Field.Get_IsBuilt())
        {
            DoRefresh_Overlays();
            return;
        }

        auto Config = FCk_GroundNav_BakeConfig(k_CellSizeUu, k_CellHeightUu);
        Config.Set_TileSizeUu(k_TileSizeUu);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(k_AgentHalfHeightUu, k_AgentRadiusUu)));
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(Get_ScenePoint(k_VolumeMin), Get_ScenePoint(k_VolumeMax));

        _Field.Request_Mint(_PcEntity, n"GroundNavGym_LinksField", Bounds, Config, Profile,
            NAME_None, k_SettlePollCeiling,
            FCk_Delegate_Request_OnCompleted(this, n"OnFieldBuildCompleted"),
            FCk_Delegate_Timer(this, n"OnFieldSettlePoll"));
    }

    // The one named condition worth waiting on after a bake: nothing in flight and nothing pending, so
    // the field the volume publishes is the one every query - and every link resolution - answers
    // from. A fixed number of hops would bake a guess about the probe budget into the gym.
    UFUNCTION()
    private void OnFieldSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Step = _Field.Do_PollSettle();

        if (Step == ECkGroundNavGym_Settle::Settled)
        {
            // The links are authored ONCE. The redraw is owed on EVERY settle, which is why it is not
            // behind the same guard - a settle that authors nothing still put a new field on the
            // ground, and the picture is command-driven.
            if (_LinksAuthored == false)
            {
                DoAuthor_Links();
                return;
            }

            DoRefresh_Overlays();
            return;
        }

        if (Step == ECkGroundNavGym_Settle::GaveUp)
        {
            _Field.Set_Stage("the surface never settled - no links were authored");
            ck::groundnav::Log("GroundNav links gym: the field never settled - the drop and the ladder were not authored");
        }
    }

    UFUNCTION()
    private void OnFieldBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Field.Notify_BuildCompleted(InResult);
    }

    private void DoAuthor_Links()
    {
        if (_LinksAuthored)
        { return; }

        _LinksAuthored = true;

        _DropEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        _DropEntity.Request_OverrideToSelf();
        _DropEntity.Set_DebugName(n"GroundNavGym_DropLink");

        _LadderEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        _LadderEntity.Request_OverrideToSelf();
        _LadderEntity.Set_DebugName(n"GroundNavGym_LadderLink");

        DoRequest_Links(ECk_EnableDisable::Enable);

        const auto Polls = _Field.Get_SettlePolls();
        _Field.Set_Stage(f"authored after {Polls} settle polls");

        // The real command, not "0 0 0": this runs after the station anchor is known, so the line in
        // the log is one a reader can paste. It is also the line the gym has just run for them.
        ck::groundnav::Log(f"GroundNav links gym: the drop and the ladder are authored - {Get_LinksAtCommandText()} lists them, and is run for you");
    }

    // Both links, every time, from one place: the toggle re-requests them with the enable flag flipped
    // and nothing else changed, so the two forms cannot drift apart. Naming the SAME entities is what
    // keeps each record's id - an update keeps the id the entity was first admitted under.
    //
    // ONE BATCH, not two requests. A batch is ATOMIC: every entry is judged before any is applied, so
    // a drop the volume refused could never leave the ladder authored on its own and this gym's rows
    // half-populated. It also completes ONCE, which is the only thing the gym can act on - "the deck
    // is joined to the floor" is the state it wants, and two completions cannot say it.
    private void DoRequest_Links(ECk_EnableDisable InEnable)
    {
        auto Volume = _Field.Get_Volume();

        if (ck::Is_NOT_Valid(Volume))
        { return; }

        // The id is -1 because the VOLUME assigns it; the record's identity carries no setter.
        auto DropRecord = FCk_GroundNav_LinkRecord(-1, Get_ScenePoint(k_DropStart), Get_ScenePoint(k_DropEnd));

        DropRecord.Set_Direction(ECk_GroundNav_LinkDirection::Forward)
                  .Set_Enable(InEnable);

        auto LadderRecord = FCk_GroundNav_LinkRecord(-1, Get_ScenePoint(k_LadderStart), Get_ScenePoint(k_LadderEnd));

        LadderRecord.Set_Direction(ECk_GroundNav_LinkDirection::Forward)
                    .Set_CostMultiplierForward(k_LadderMultiplier)
                    .Set_ClearanceUu(k_LadderClearanceUu)
                    .Set_Enable(InEnable);

        // Built imperatively: AngelScript takes no brace initialiser for a TArray. The drop goes in
        // first, and ids are handed out monotonically, so the resolution rows below can name the
        // first record the drop and the second the ladder.
        auto Entries = TArray<FCk_Request_GroundNavVolume_Link>();
        Entries.Add(FCk_Request_GroundNavVolume_Link(_DropEntity, DropRecord));
        Entries.Add(FCk_Request_GroundNavVolume_Link(_LadderEntity, LadderRecord));

        utils_ground_nav_volume::Request_LinkBatch(Volume,
            FCk_Request_GroundNavVolume_LinkBatch(Entries),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinksBatchCompleted"));

        // Twice, on purpose. The immediate refresh puts the plates and the records on screen with no
        // typing and no wait; the armed one re-runs LinksAt once the derive has republished, which is
        // when the COLOURS are finally the new state's. Neither alone is enough - the first would draw
        // the field as it was before this request, and the second alone would leave the deck empty for
        // however long the derive takes.
        DoRefresh_Overlays();
        DoArm_OverlayRefresh();
    }

    // ---- The overlays the gym draws for the reader ---------------------------------------------------
    //
    // Nothing here is cvar-driven. ck.GroundNav.Debug.Mode selects WHAT a bake draws and no sink
    // redraws on its own, so the plates exist only because a debug bake ran and the links only because
    // ck.GroundNav.LinksAt did. The order is load-bearing: the bake replaces the FIELD group and
    // LinksAt replaces the QUERY group, so links last is links over plates.
    //
    // The bake is a DEBUG picture and belongs to no volume - the rows above read the volume's own
    // published field. The two describe the same ground only because Request_BakeDebugFieldAt pushes
    // every bake cvar off THIS field, so nothing another gym left in this world's console reaches it.

    private void DoRefresh_Overlays()
    {
        CkGroundNavGym::Request_BakeDebugFieldAt(_Field, Get_ScenePoint(k_DeckCentre),
            k_DebugBakeExtentUu, k_DebugBakeHeightUu, k_DebugBakeMaxCells, k_LinkDrawMode);

        CkGroundNavGym::Request_ReportLinksAt(Get_ScenePoint(k_DeckCentre));
    }

    // Waits for the derive the link request provoked to publish, then redraws. The wait itself lives
    // in FCkGroundNavGym_OverlayRefresh - the named condition and the ceiling are the same in every
    // gym here; what differs is only what each one redraws afterwards.
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

        DoRefresh_Overlays();

        // HERE and not in the failure callback. The links have just changed and the field has just
        // republished, so this is the one moment a goal the walker could not reach may have become
        // reachable - and the only moment at which re-asking is not a loop.
        DoRetry_WalkerIfAwaiting();
    }

    // ---- The route draw ------------------------------------------------------------------------------
    //
    // The WALKER'S OWN installed route, read off its planner and drawn per frame. Not ck.GroundNav.PathAt:
    // that command searches the DEBUG field, whose bake params carry no links at all - Make_BakeParams
    // builds a region, a lattice and an agent profile and nothing else - so a PathAt route can never
    // step onto the drop or the ladder, which is the only thing this station is about. The route the
    // walker is actually walking crosses them, and it is the one worth drawing.

    private void DoToggle_RouteDraw()
    {
        if (ck::Is_NOT_Valid(_Walker))
        { return; }

        _RouteDrawEnabled = _RouteDrawEnabled == false;
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        if (_RouteDrawEnabled == false)
        { return; }

        DoDraw_WalkerRoute();
    }

    // Zero duration, so every frame draws the route as it stands THIS frame. A replan replaces the
    // whole waypoint array, and a persistent line would leave the abandoned route lying under the new
    // one with nothing to say which was which.
    //
    // The link segments are drawn in their own colour over the top rather than instead: a span names
    // the waypoint it steps ON at and the one it steps OFF at, so the segments between those two
    // indices are the part of the route that is a link.
    private void DoDraw_WalkerRoute()
    {
        if (ck::Is_NOT_Valid(_WalkerPlanner))
        { return; }

        const auto Waypoints = utils_ground_nav_path::Get_Result(_WalkerPlanner).Get_Waypoints();

        if (Waypoints.Num() < 2)
        { return; }

        // Lifted off the ground it was planned on, or the plates drawn at the same height swallow it.
        FVector Rise = FVector(0.0, 0.0, k_RouteRiseUu);

        // Declared non-const: `auto` preserves const and DrawDebugLine takes its colour BY VALUE.
        FLinearColor RouteColor = FLinearColor(0.35, 0.80, 1.0, 1.0);
        FLinearColor LinkColor = FLinearColor(1.0, 0.55, 0.10, 1.0);

        for (int32 Index = 0; Index < Waypoints.Num() - 1; Index++)
        {
            utils_debug_draw::DrawDebugLine(Waypoints[Index] + Rise, Waypoints[Index + 1] + Rise,
                RouteColor, 0.0f, k_RouteLineThickness);
        }

        auto Spans = utils_ground_nav_path::Get_LinksOnPath(_WalkerPlanner);

        for (int32 SpanIndex = 0; SpanIndex < Spans.Num(); SpanIndex++)
        {
            const auto Entry = Spans[SpanIndex].Get_EntryWaypointIndex();
            const auto Exit = Spans[SpanIndex].Get_ExitWaypointIndex();

            // A span whose exit has not been closed yet, or whose indices name a route that has since
            // been replaced, is skipped rather than clamped: an index is only valid against the plan
            // it was made for.
            if (Waypoints.IsValidIndex(Entry) == false || Waypoints.IsValidIndex(Exit) == false)
            { continue; }

            for (int32 Index = Entry; Index < Exit; Index++)
            {
                utils_debug_draw::DrawDebugLine(Waypoints[Index] + Rise, Waypoints[Index + 1] + Rise,
                    LinkColor, 0.0f, k_RouteLineThickness * 2.0f);
            }
        }
    }

    UFUNCTION()
    private void OnLinksBatchCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _BatchCompletions += 1;
        _LastBatchResult = InResult;

        if (InResult != ECk_Request_OperationResult::Succeeded)
        {
            ck::groundnav::Log("GroundNav links gym: the link batch was REFUSED - a batch is atomic, so neither the drop nor the ladder was applied");
        }
    }

    private void DoToggle_Links()
    {
        if (ck::Is_NOT_Valid(_Field.Get_Volume()))
        { return; }

        auto Enable = ECk_EnableDisable::Enable;

        if (Get_LinksAreEnabled())
        { Enable = ECk_EnableDisable::Disable; }

        // DoRequest_Links arms the overlay refresh, so ck.GroundNav.LinksAt is re-run for the reader
        // once the derive has republished rather than at this keypress - the colours it draws come off
        // the field, and at this instant the field is still the one the toggle is about to change.
        DoRequest_Links(Enable);

        ck::groundnav::Log("GroundNav links gym: link enable flipped - the derive republishes, then ck.GroundNav.LinksAt is re-run and shows the new state");
    }

    // Read off the record the volume holds rather than mirrored in a bool: the volume IS the state,
    // and a member that disagreed with it would report links the field no longer carries.
    private bool Get_LinksAreEnabled()
    {
        // The panel rebuilds every frame, including the frames before the volume is minted and the ones
        // after a teardown, so every read of the records has to survive an invalid volume.
        auto Volume = _Field.Get_Volume();

        if (ck::Is_NOT_Valid(Volume))
        { return false; }

        auto Records = utils_ground_nav_volume::Get_LinkRecords(Volume);

        if (Records.Num() == 0)
        { return false; }

        return Records[0].Get_Enable() == ECk_EnableDisable::Enable;
    }

    // ---- The walker ----------------------------------------------------------------------------------
    //
    // One body, and it is the only thing on this station that can show what a link is FOR. Everything
    // else here is a record and a resolution; this is a route.

    private void DoToggle_Walker()
    {
        if (ck::IsValid(_WalkerEntity))
        {
            DoDespawn_Walker();
            return;
        }

        DoSpawn_Walker();
    }

    private void DoSpawn_Walker()
    {
        const auto Spawn = Get_ScenePoint(k_WalkerFloorPoint);
        const auto Goal = Get_ScenePoint(k_WalkerDeckPoint);

        auto WalkerEntity = utils_entity_lifetime::Request_CreateEntity(_PcEntity);
        WalkerEntity.Set_DebugName(n"GroundNavGym_LinkWalker");

        // YAW ONLY. The deck point stands 200uu above the floor point, so the full rotation towards it
        // pitches the body's whole capsule nose-up before it has taken a step - the goal being higher
        // than the spawn is a fact about the route, not about which way the body faces.
        FRotator Facing = FRotator(0.0, (Goal - Spawn).Rotation().Yaw, 0.0);

        auto WalkerTransform = utils_transform::Add(WalkerEntity,
            FTransform(Facing, Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto Walker = utils_crowd_agent::Add(WalkerTransform,
            FCk_Fragment_CrowdAgent_ParamsData(k_AgentRadiusUu, k_WalkerHeightUu));

        if (ck::Is_NOT_Valid(Walker))
        {
            ck::groundnav::Warning("GroundNav links gym: the walker got no crowd agent handle");
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

        // Composed HERE with the radius the crowd's own GroundNav dispatch would have used. The
        // dispatch adds the feature only when it is missing, so what runs is identical either way -
        // but the HANDLE is what Get_LinksOnPath is asked of, and one composed in there is one this
        // gym never sees.
        _WalkerPlanner = utils_ground_nav_path::Add(WalkerEntity,
            FCk_Fragment_GroundNavPath_ParamsData(k_AgentRadiusUu));

        utils_crowd_agent::BindTo_OnGoalReached(Walker,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Bound BESIDE the reached signal, because on this scene the two are equally ordinary: with
        // both links disabled the deck top is an island, so a failure is the contract rather than a
        // fault. Without this the body simply stands where it stopped and never moves again, and the
        // row goes on reading Idle with nothing to say why.
        utils_crowd_agent::BindTo_OnGoalFailed(Walker,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(Walker, FCk_Request_CrowdAgent_MoveTo(Goal));

        _WalkerEntity = WalkerEntity;
        _Walker = Walker;
        _WalkerHasWalked = false;
        _WalkerAwaitsRetry = false;
    }

    private void DoDespawn_Walker()
    {
        if (ck::IsValid(_WalkerEntity))
        { utils_entity_lifetime::Request_DestroyEntity(_WalkerEntity); }

        _WalkerEntity = FCk_Handle();
        _Walker = FCk_Handle_CrowdAgent();
        _WalkerPlanner = FCk_Handle_GroundNavPath();
        _WalkerHasWalked = false;
        _WalkerAwaitsRetry = false;

        // The route was this body's. Nothing else draws one, so the toggle has nothing left to mean.
        _RouteDrawEnabled = false;
    }

    // The walker turns round rather than parking at whichever end it reached: a body that climbed once
    // and stopped says nothing about a link disabled a minute later, and the round trip is what makes
    // it take BOTH links - the ladder up the south face and the drop off the east edge.
    UFUNCTION()
    private void OnWalkerGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        auto WalkerEntity = FCk_Handle(InAgent);

        if (ck::Is_NOT_Valid(WalkerEntity))
        { return; }

        const auto Here = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(WalkerEntity));

        const auto FloorEnd = Get_ScenePoint(k_WalkerFloorPoint);
        const auto DeckEnd = Get_ScenePoint(k_WalkerDeckPoint);

        FVector Destination = DeckEnd;

        // Which end it is nearer, not a world sign test: the scene is placed off the station anchor,
        // so its midpoint is wherever the grid layout put it.
        if ((Here - DeckEnd).Size() < (Here - FloorEnd).Size())
        { Destination = FloorEnd; }

        utils_crowd_agent::Request_MoveTo(InAgent, FCk_Request_CrowdAgent_MoveTo(Destination));

        _WalkerAwaitsRetry = false;
    }

    // Records the failure and asks for NOTHING. Re-issuing here would be a plan-fail-plan loop for as
    // long as the links stayed disabled - which is a state this station exists to hold, not an error.
    // The retry is owed to the next link change, and that is where it is issued from.
    UFUNCTION()
    private void OnWalkerGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        _WalkerAwaitsRetry = true;
    }

    // Called from the overlay refresh's settled step, which is the moment after a link toggle at which
    // the field has republished. The far end, not the nearer one: the body failed on its way somewhere
    // and the point of the retry is to send it back over the link that has just come back.
    //
    // Only on the ENABLE half of the toggle. A settled step with the links off is the moment a goal
    // became impossible rather than possible - the deck top is an island by construction - so re-asking
    // there fails again, re-latches the flag, and holds the row replanning forever. The flag is left
    // STANDING rather than cleared: the retry is still owed, to the next enable.
    private void DoRetry_WalkerIfAwaiting()
    {
        if (Get_LinksAreEnabled() == false)
        { return; }

        if (_WalkerAwaitsRetry == false)
        { return; }

        if (ck::Is_NOT_Valid(_Walker))
        {
            _WalkerAwaitsRetry = false;
            return;
        }

        const auto Here = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(_WalkerEntity));

        const auto FloorEnd = Get_ScenePoint(k_WalkerFloorPoint);
        const auto DeckEnd = Get_ScenePoint(k_WalkerDeckPoint);

        FVector Destination = DeckEnd;

        if ((Here - DeckEnd).Size() < (Here - FloorEnd).Size())
        { Destination = FloorEnd; }

        utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(Destination));

        _WalkerAwaitsRetry = false;
    }

    // Records that the walker has been seen Walking, and answers whether it ever has. The record is
    // made by the same pass that reads the state, so nothing reads the agent twice to keep it.
    private bool Get_WalkerHasWalked()
    {
        if (ck::Is_NOT_Valid(_Walker))
        { return false; }

        if (utils_crowd_agent::Get_MovementState(_Walker) == ECk_CrowdAgent_MovementState::Walking)
        { _WalkerHasWalked = true; }

        return _WalkerHasWalked;
    }

    // The links the walker's CURRENT route steps onto, in walk order, off the planner it holds. Read
    // where it is used and never remembered: a span names the route that is installed now, and a
    // replan replaces the whole array.
    private TArray<int32> Get_WalkerLinkIds()
    {
        auto Ids = TArray<int32>();

        if (ck::Is_NOT_Valid(_WalkerPlanner))
        { return Ids; }

        auto Spans = utils_ground_nav_path::Get_LinksOnPath(_WalkerPlanner);

        for (int32 Index = 0; Index < Spans.Num(); Index++)
        { Ids.Add(Spans[Index].Get_LinkId()); }

        return Ids;
    }

    private FString Get_WalkerLinkIdsText()
    {
        auto Ids = Get_WalkerLinkIds();

        if (Ids.Num() == 0)
        { return "none"; }

        FString Text = "";

        for (int32 Index = 0; Index < Ids.Num(); Index++)
        {
            if (Index > 0)
            { Text += ", "; }

            Text += f"{Ids[Index]}";
        }

        return Text;
    }

    private FString Get_WalkerStatus()
    {
        if (ck::Is_NOT_Valid(_Walker))
        { return "none spawned"; }

        const auto State = utils_crowd_agent::Get_MovementState(_Walker);
        const auto PathStatus = utils_nav::Get_PathStatus(_WalkerEntity);
        const auto Links = Get_WalkerLinkIdsText();

        FString Text = f"{State} - route {PathStatus} - links on this route: {Links}";

        // The one thing the enum cannot say: this body asked for a goal it could not reach and is
        // holding until the links change, rather than having stopped for no reason.
        if (_WalkerAwaitsRetry)
        { Text += " - its last goal FAILED; it is re-asked when the links next come back on"; }

        return Text;
    }

    // ---- The verdict -------------------------------------------------------------------------------
    //
    // Every criterion is a LIVE readback off the published field: each end's projection status, the
    // record's own resolved flag, and its live flag - the same rule Get_IsLinkLive answers, carried on
    // the resolution so one read covers both questions. Nothing here is mirrored, and the enable
    // state the live flags are judged against is itself read off record 0.
    //
    // The walker's clause is the same discipline one layer out: the link spans come off its planner and
    // the route status off its agent entity, both at the instant the row is built. The one thing it
    // remembers is that a readback ONCE said Walking, which the movement enum cannot say afterwards -
    // and that is what gates the clause, because a body with no route yet is pending and not wrong.

    private TArray<FString> Get_VerdictFailures()
    {
        auto Failures = TArray<FString>();

        auto Volume = _Field.Get_Volume();

        if (_Field.Get_IsBuilt() == false)
        { return Failures; }

        auto Records = utils_ground_nav_volume::Get_LinkRecords(Volume);

        if (Records.Num() == 0)
        { return Failures; }

        const auto Enabled = Get_LinksAreEnabled();

        for (int32 Index = 0; Index < Records.Num(); Index++)
        {
            const auto LinkId = Records[Index].Get_Id();
            const auto Resolution = utils_ground_nav_volume::Get_LinkResolution(Volume, LinkId);

            const auto Live = Resolution.Get_Live();

            // Disabled is a STATE, not a fault: the only thing a disabled link owes is to be dead. Its
            // ends may or may not still project, and asserting on that would fail the toggle's own
            // purpose.
            if (Enabled == false)
            {
                if (Live)
                { Failures.Add(f"link {LinkId} is still live with the links switched off"); }

                continue;
            }

            const auto StartStatus = Resolution.Get_StartStatus();

            if (StartStatus != ECk_NavSurface_QueryStatus::Success)
            { Failures.Add(f"link {LinkId} start resolved {StartStatus}"); }

            const auto EndStatus = Resolution.Get_EndStatus();

            if (EndStatus != ECk_NavSurface_QueryStatus::Success)
            { Failures.Add(f"link {LinkId} end resolved {EndStatus}"); }

            if (Resolution.Get_Resolved() == false)
            { Failures.Add(f"link {LinkId} did not resolve"); }

            if (Live == false)
            { Failures.Add(f"link {LinkId} is enabled but not live"); }
        }

        const auto WalkerFailure = Get_WalkerVerdictFailure(Enabled);

        if (WalkerFailure.Len() > 0)
        { Failures.Add(WalkerFailure); }

        return Failures;
    }

    // The walker's own criterion, and it INVERTS with the toggle. With the links live the deck top is
    // reachable only over one of them, so a route that names no link is a route that could not exist -
    // something other than a link joined the deck to the floor. With them disabled the deck top is an
    // island, so Failed is the CONTRACT: a Ready route there would mean a disabled record is still
    // being searched.
    //
    // Both are gated on the body having been seen Walking at least once. Before that there is no route
    // to judge, and colouring the row red for the second between the spawn and the first plan would
    // fail the station on its own keypress. Every read is live - the spans off the planner, the status
    // off the agent entity - and the only thing remembered is that a readback once said Walking.
    // The walker between two settled states: the field is still moving, or the search has not answered
    // yet, or a failure is standing that the next ENABLE is going to retry. That last one counts only
    // while the links are on: with them off a failed route is the settled answer this station asks
    // for, not a pending one, and counting it would hide the OK line behind a permanent replan.
    // None of the three is a verdict - a toggle republishes the field and the body cannot have a route to judge until it has -
    // and colouring the row red for that window fails the station on its own keypress, which is exactly
    // what the U press was doing.
    private bool Get_WalkerIsReplanning()
    {
        if (ck::Is_NOT_Valid(_Walker))
        { return false; }

        if (_OverlayRefresh.Get_IsWaiting())
        { return true; }

        if (_WalkerAwaitsRetry && Get_LinksAreEnabled())
        { return true; }

        const auto Status = utils_nav::Get_PathStatus(_WalkerEntity);

        return Status == ECk_Nav_PathStatus::None || Status == ECk_Nav_PathStatus::Pending;
    }

    private FString Get_WalkerVerdictFailure(bool InLinksAreEnabled)
    {
        if (Get_WalkerHasWalked() == false)
        { return ""; }

        // Pending, not FAIL and not OK.
        if (Get_WalkerIsReplanning())
        { return ""; }

        if (InLinksAreEnabled)
        {
            if (Get_WalkerLinkIds().Num() == 0)
            { return "walker route crosses no link"; }

            return "";
        }

        if (utils_nav::Get_PathStatus(_WalkerEntity) == ECk_Nav_PathStatus::Ready)
        { return "walker route is Ready with both links disabled - the deck top is an island"; }

        return "";
    }

    // Appended to the OK line, from the same live readbacks the failure clause above ran. Silent while
    // there is no walker or no route yet: a station with nothing on it should not claim a crossing.
    private FString Get_WalkerVerdictSuffix(bool InLinksAreEnabled)
    {
        if (Get_WalkerHasWalked() == false)
        { return ""; }

        // The same pending window the failure clause steps over, said out loud: the reader who just
        // pressed U should see the row waiting rather than see it claim anything.
        if (Get_WalkerIsReplanning())
        { return " - walker: replanning"; }

        if (InLinksAreEnabled)
        {
            auto Ids = Get_WalkerLinkIds();

            if (Ids.Num() == 0)
            { return ""; }

            return " - walker crossed link " + Get_WalkerLinkIdsText();
        }

        if (utils_nav::Get_PathStatus(_WalkerEntity) == ECk_Nav_PathStatus::Failed)
        { return ", walker route Failed as expected"; }

        return "";
    }

    private FString Get_VerdictLine(const TArray<FString>&in InFailures)
    {
        if (_Field.Get_IsBuilt() == false)
        { return "field not built"; }

        const auto Records = utils_ground_nav_volume::Get_LinkRecords(_Field.Get_Volume()).Num();

        if (Records == 0)
        { return "field built - no links authored yet"; }

        if (InFailures.Num() > 0)
        { return CkGroundNavGym::Get_VerdictText("", InFailures); }

        if (Get_LinksAreEnabled() == false)
        { return "OK - both disabled" + Get_WalkerVerdictSuffix(false); }

        return "OK - both links resolved and live" + Get_WalkerVerdictSuffix(true);
    }

    // ---- Scene construction ----------------------------------------------------------------------

    private bool DoBuildScene()
    {
        // Guarded, not idempotent by luck: see _SceneSpawned. A restart keeps the scene it already
        // spawned, which is also the scene the volume was baked over.
        if (_SceneSpawned)
        { return true; }

        _SceneSpawned = true;

        if (CkGroundNavGym::Spawn_Floor(Get_ScenePoint(k_FloorCentre), k_FloorScale) == nullptr)
        { return false; }

        // The deck is scene geometry like everything else here, so it goes into the Jolt static world
        // through the same call - the links volume bakes from that world and from nothing else.
        if (CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_DeckCentre), k_DeckScale) == false)
        { return false; }

        return true;
    }

    private void DoBringPlayerToViewpoint()
    {
        CkGroundNavGym::Request_FlyToStation(this, "GroundNavLinks",
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
        return "GROUNDNAV: LINKS";
    }

    // Readback: every value column below is asked for as the row is built. The two that are NOT read
    // off the volume are the batch counters, and they say so where they stand - how many times the
    // link batch completed, and what the last one answered, are this gym's own arithmetic.
    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        const auto VerdictFailures = Get_VerdictFailures();

        Rows.Add(CkGym_Control::Header("SCENE"));
        Rows.Add(CkGym_Control::Status("Verdict", Get_VerdictLine(VerdictFailures), VerdictFailures.Num() > 0));
        Rows.Add(CkGym_Control::Status("Geometry",
            CkGroundNavGym::Get_GeometryStatusText(_GeometryIsBuilt,
                "a 400uu deck standing 200uu above its own floor"),
            _GeometryIsBuilt == false));

        // Every value here is read off the volume as the row is built, so the panel reports the links
        // the field actually carries rather than what this controller last asked for.
        Rows.Add(CkGym_Control::Header("LINKS - a drop off the deck's east edge, a ladder up its south face"));
        Rows.Add(CkGym_Control::Status("Field", _Field.Get_FieldStatusText(), _Field.Get_IsBuilt() == false));
        Rows.Add(CkGym_Control::Status("Drop / ladder", Get_LinksLiveStatus()));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::U, "U",
            "Links (a disabled link is invisible to search and to reachability)",
            Get_LinksAreEnabled(), "enabled", "disabled"));

        Rows.Add(CkGym_Control::Header("THE WALKER - the deck top is reachable over a link and no other way"));
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::One, "1",
            "Crowd walker (ping-pongs between the floor west of the deck and the deck's top face)",
            ck::IsValid(_Walker), "on the scene", "none spawned"));
        Rows.Add(CkGym_Control::Status("Walker", Get_WalkerStatus()));

        // Disabled while there is no body, because there is then no route: this row draws the WALKER'S
        // OWN installed plan and nothing else, so with the scene empty it has nothing to turn on.
        Rows.Add(CkGym_Control::Toggle(EKeys::Two, "2",
            "Draw the walker's route",
            _RouteDrawEnabled, false, ck::IsValid(_Walker)));
        Rows.Add(CkGym_Control::Status("Draw", Get_DrawStatus()));
        Rows.Add(CkGym_Control::Status("Surface", CkGroundNavGym::Get_SurfaceStatusText()));

        // LAST, and that is not a preference. How many resolution rows there are depends on how many
        // records the volume holds, so a section of them placed ABOVE a keyed row would move that
        // row's index between frames, and the panel dispatches on the index.
        Rows.Add(CkGym_Control::Header("LINK RESOLUTION - one row per record the volume holds"));

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

        auto Volume = _Field.Get_Volume();

        if (ck::Is_NOT_Valid(Volume))
        { return OutRows; }

        auto Records = utils_ground_nav_volume::Get_LinkRecords(Volume);

        for (int32 Index = 0; Index < Records.Num(); Index++)
        {
            const auto LinkId = Records[Index].Get_Id();
            const auto Resolution = utils_ground_nav_volume::Get_LinkResolution(Volume, LinkId);

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

    // The console line a reader can actually type, aimed at THIS deck. A hardcoded "0 0 0" would name
    // the world origin, and the scene is wherever Request_ApplyDefaultGridLayout put the station -
    // several thousand units from it - so the command as printed would draw the links of nothing.
    private FString Get_LinksAtCommandText()
    {
        return CkGroundNavGym::Get_LinksAtCommandText(Get_ScenePoint(k_DeckCentre));
    }

    // What is on screen and what put it there. The retained draw is command-driven, so this row states
    // what the gym RAN rather than what a reader could type - the typing was the old row's whole point,
    // and it is what the maintainer's walk found nothing had done.
    private FString Get_DrawStatus()
    {
        const auto BakeText = CkGroundNavGym::Get_BakeFieldAtCommandText(Get_ScenePoint(k_DeckCentre));

        FString Text = f"{BakeText} at draw mode {k_LinkDrawMode}, then {Get_LinksAtCommandText()}, are run for you whenever the links change - the plates are the DEBUG bake's picture, the links are read off the PUBLISHED field";

        // The route is NOT one of the retained commands and says so, because the difference is the
        // reason key 2 stopped being a PathAt: the debug field those commands query is baked from a
        // region and a profile and carries no links at all, so a route drawn out of it could never
        // step onto the drop or the ladder.
        if (_RouteDrawEnabled)
        { Text += " - over them, the walker's own installed route, drawn each frame off its planner, with its link segments in orange"; }

        return Text;
    }

    private FString Get_LinksLiveStatus()
    {
        auto Volume = _Field.Get_Volume();

        if (ck::Is_NOT_Valid(Volume))
        { return "no volume minted yet"; }

        const auto Records = utils_ground_nav_volume::Get_LinkRecords(Volume).Num();

        if (Records == 0)
        { return "nothing authored yet"; }

        const auto DropLive = utils_ground_nav_volume::Get_IsLinkLive(_DropEntity);
        const auto LadderLive = utils_ground_nav_volume::Get_IsLinkLive(_LadderEntity);
        const auto Unresolved = utils_ground_nav_volume::Get_UnresolvedLinkCount(Volume);
        const auto Batches = _BatchCompletions;
        const auto LastResult = _LastBatchResult;

        return f"{Records} records - drop live: {DropLive} - ladder live: {LadderLive} - ends that found no ground: {Unresolved} - batches: {Batches} (last {LastResult})";
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (HasAuthority() == false)
        { return; }

        if (InRowIndex == k_Row_LinksToggle)
        {
            DoToggle_Links();
            return;
        }

        if (InRowIndex == k_Row_Walker)
        {
            DoToggle_Walker();
            return;
        }

        if (InRowIndex == k_Row_RouteDraw)
        {
            DoToggle_RouteDraw();
            return;
        }
    }
}
