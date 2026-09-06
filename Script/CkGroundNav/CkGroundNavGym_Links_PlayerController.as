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

    // ---- The posts the walkers patrol between -----------------------------------------------------
    //
    // Two posts on the floor WEST of the deck and one on the deck's top face. The deck stands 200uu
    // clear of the floor on all four sides and nothing ramps up to it, so its top is an ISLAND: the
    // only way up is the ladder off the south face and the only way down is the drop off the east
    // edge. A round trip from either floor post therefore takes BOTH links, which is the picture.
    //
    // Each is 100uu above the ground under it - where a 180uu body's centre stands - and none is near
    // the station board, which the floor stops 500uu short of.
    private const FVector k_FloorPostNorth = FVector(-450.0, 220.0, 100.0);
    private const FVector k_FloorPostSouth = FVector(-450.0, -220.0, 100.0);
    private const FVector k_DeckPost       = FVector(0.0, 0.0, 300.0);

    // The one-line "what this is", standing in the world over the deck.
    private const FVector k_CaptionLocal = FVector(0.0, 0.0, 650.0);

    // ---- Bake constants ---------------------------------------------------------------------------
    //
    // The station's own bake, deliberately the same shape every GroundNav fixture in the corpus uses.
    // LedgeSensitivity is pinned off: the deck is a 400uu square that drops 200uu on all four sides,
    // and the ledge filter at its default would demote its whole top - leaving the two links with
    // nothing to land on for a reason that has nothing to do with links.
    private const float k_CellSizeUu        = 25.0f;
    private const float k_CellHeightUu      = 10.0f;
    private const float k_TileSizeUu        = 500.0f;
    private const float k_AgentRadiusUu     = 34.0f;
    private const float k_AgentHalfHeightUu = 90.0f;

    // The same body the volume was baked for: 34uu is what the ladder's 40uu of clearance admits, and
    // 180uu is twice the profile's own half-height.
    private const float k_WalkerHeightUu = 180.0f;

    // 0.05s a poll, so this is thirty seconds of waiting on a NAMED condition before the gym gives up
    // and says so rather than hanging silently.
    private const int32 k_SettlePollCeiling = 600;

    // A link request is DEFERRED and the colours LinksAt draws come off the field the DERIVE publishes
    // afterwards, so the overlay refresh waits on a named condition rather than a hop count. At 0.05s
    // a poll this ceiling is ten seconds, after which the picture is refreshed anyway.
    private const int32 k_OverlayPollCeiling = 200;

    // Only the REGION of the debug picture is stated here. Every filter the bake runs - the lattice,
    // the agent capsule, the slope limits, the ledge sensitivity this deck needs pinned off - is
    // pushed from the volume by Request_BakeDebugFieldAt, so the picture and the walkers cannot be
    // standing on different fields. 800 is a half-extent and covers the floor's 1400uu square.
    private const float k_DebugBakeExtentUu = 800.0f;
    private const float k_DebugBakeHeightUu = 400.0f;
    private const int32 k_DebugBakeMaxCells = 40000;

    // Frames the deck, the ladder's foot, the drop's landing and both floor posts from the south-east.
    private const FVector  k_ViewOffset   = FVector(750.0, -950.0, 700.0);
    private const FRotator k_ViewRotation = FRotator(-24.0, 128.0, 0.0);

    // The draw mode this gym is worth looking at in: links over the dimmed plates they join. T cycles
    // it from there through the shared list.
    private const int32 k_LinkDrawMode = 7;

    private const FString k_Caption = "Two authored links - a ladder up, a drop down - and walkers that can reach the deck no other way";

    // ---- Control row layout ------------------------------------------------------------------------
    //
    // Rows 0-2 are the frame's header (This shows / Verdict / Walkers), so the first keyed row is
    // CkGroundNavDemo::k_DemoHeaderRowCount. The T row is LAST, as on every demo gym.
    //
    //   0-2  header      3  U links on/off      4  T picture

    // Literals rather than CkGroundNavDemo::k_DemoHeaderRowCount arithmetic: a class const
    // initialised off a const in another file depends on AS's global init order. 3 IS that count.
    private const int32 k_Row_LinksToggle = 3;
    private const int32 k_Row_DrawMode    = 4;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FVector _Origin = FVector::ZeroVector;
    private bool _GeometryIsBuilt = false;

    // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and the floor and the deck are
    // spawned actors that nothing here holds a handle to - so a second pass would stack a whole second
    // scene into the Jolt static world, invisible to everything. Spawned once per controller.
    private bool _SceneSpawned = false;

    private FCkGroundNavGym_Field _Field;
    private FCkGroundNavDemo_WalkerSet _Walkers;
    private FCkGroundNavGym_OverlayRefresh _OverlayRefresh;

    private int32 _DrawModeIndex = k_LinkDrawMode;

    private FCk_Handle _DropEntity;
    private FCk_Handle _LadderEntity;

    private bool _LinksAuthored = false;

    // The batch's own completion. ONE delegate for both links, which is the only thing the batch adds
    // over two single requests - the drain takes the whole queue in a pass and the derive tag is
    // idempotent, so two singles landing in one tick already cost exactly one derive.
    private int32 _BatchCompletions = 0;
    private ECk_Request_OperationResult _LastBatchResult = ECk_Request_OperationResult::Failed;

    // The posts, in world space, kept so Tick can draw them with their labels. Built once with the
    // walkers, because the walkers are what makes a post a post.
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
        Station.Tags.Add(n"GroundNavLinks");
        Station.AutoSize = true;
        Station.Title = FText::FromString("GroundNav - Links");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("A deck standing 200uu clear of its own floor on all four sides, joined to the ground only by two authored links: a one-way LADDER up its south face and a one-way DROP off its east edge."));
        Description.Add(FText::FromString("Two walkers patrol from the floor posts to the deck top, so every round trip has to climb the ladder and take the drop."));
        Description.Add(FText::FromString("U disables both links and the deck becomes an island - the walkers hold. T cycles what the picture under them shows."));
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

        ck::groundnav::Log("GroundNav links gym: scene built - the drop and the ladder are authored once the field settles, then the walkers go on");
    }

    // Scene-local to world. Everything the gym spawns, bakes, authors and walks between goes through
    // here, so the scene is one translation away from the station the grid layout happened to place.
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
            // The links are authored ONCE, and authoring already draws the picture and arms the
            // deferred redraw. A later settle - a rebuild - owes only the redraw.
            if (_LinksAuthored == false)
            { DoAuthor_Links(); }
            else
            { DoRefresh_Picture(); }

            if (_Walkers.Get_Count() == 0)
            { DoSpawn_Walkers(); }

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

        ck::groundnav::Log("GroundNav links gym: the drop and the ladder are authored, and the picture is drawn for you");
    }

    // Both links, every time, from one place: the toggle re-requests them with the enable flag flipped
    // and nothing else changed, so the two forms cannot drift apart. Naming the SAME entities is what
    // keeps each record's id - an update keeps the id the entity was first admitted under.
    //
    // ONE BATCH, not two requests. A batch is ATOMIC: every entry is judged before any is applied, so
    // a drop the volume refused could never leave the ladder authored on its own. It also completes
    // ONCE, which is the only thing the gym can act on.
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
        // first, and ids are handed out monotonically.
        auto Entries = TArray<FCk_Request_GroundNavVolume_Link>();
        Entries.Add(FCk_Request_GroundNavVolume_Link(_DropEntity, DropRecord));
        Entries.Add(FCk_Request_GroundNavVolume_Link(_LadderEntity, LadderRecord));

        utils_ground_nav_volume::Request_LinkBatch(Volume,
            FCk_Request_GroundNavVolume_LinkBatch(Entries),
            FCk_Delegate_Request_OnCompleted(this, n"OnLinksBatchCompleted"));

        // Twice, on purpose. The immediate refresh puts the plates and the records on screen with no
        // wait; the armed one re-runs the picture once the derive has republished, which is when the
        // COLOURS are finally the new state's. Neither alone is enough - the first would draw the
        // field as it was before this request, and the second alone would leave the deck empty for
        // however long the derive takes.
        DoRefresh_Picture();
        DoArm_OverlayRefresh();
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

        // DoRequest_Links arms the overlay refresh, so the links are re-drawn for the reader once the
        // derive has republished rather than at this keypress - the colours come off the field, and at
        // this instant the field is still the one the toggle is about to change.
        DoRequest_Links(Enable);

        ck::groundnav::Log("GroundNav links gym: link enable flipped - the derive republishes, then the picture and the walkers follow");
    }

    // Read off the record the volume holds rather than mirrored in a bool: the volume IS the state,
    // and a member that disagreed with it would report links the field no longer carries.
    private bool Get_LinksAreEnabled()
    {
        // The panel rebuilds every frame, including the frames before the volume is minted and the
        // ones after a teardown, so every read of the records has to survive an invalid volume.
        auto Volume = _Field.Get_Volume();

        if (ck::Is_NOT_Valid(Volume))
        { return false; }

        auto Records = utils_ground_nav_volume::Get_LinkRecords(Volume);

        if (Records.Num() == 0)
        { return false; }

        return Records[0].Get_Enable() == ECk_EnableDisable::Enable;
    }

    // ---- The picture ------------------------------------------------------------------------------
    //
    // The retained draw is COMMAND-driven: the mode selects WHAT a bake draws and no sink redraws on
    // its own, so the plates exist only because a debug bake ran and the links only because LinksAt
    // did. The order is load-bearing: the bake replaces the FIELD group and LinksAt replaces the QUERY
    // group, so links last is links over plates.

    private void DoRefresh_Picture()
    {
        CkGroundNavGym::Request_BakeDebugFieldAt(_Field, Get_ScenePoint(k_DeckCentre),
            k_DebugBakeExtentUu, k_DebugBakeHeightUu, k_DebugBakeMaxCells, _DrawModeIndex);

        CkGroundNavGym::Request_ReportLinksAt(Get_ScenePoint(k_DeckCentre));
    }

    // Waits for the derive the link request provoked to publish, then redraws. The wait itself lives
    // in FCkGroundNavGym_OverlayRefresh - the named condition and the ceiling are the same in every
    // gym here; what differs is only what each one does afterwards.
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

        // HERE and not in the failure callback. The links have just changed and the field has just
        // republished, so this is the one moment a goal a walker could not reach may have become
        // reachable - and the only moment at which re-asking is not a plan-fail-plan loop. On the
        // DISABLE half there is nothing to retry into: the deck top is an island by construction, and
        // re-asking would fail again and hold every row replanning forever.
        if (Get_LinksAreEnabled())
        { _Walkers.Request_RetryAll(); }
    }

    // ---- The walkers -------------------------------------------------------------------------------

    private void DoSpawn_Walkers()
    {
        _PostPoints.Empty();
        _PostLabels.Empty();
        _PostColors.Empty();

        // Declared non-const: it is pushed into _PostPoints below, and TArray::Add takes a NON-CONST
        // reference - AS rejects a const element there (ARCHITECTURE.md 9.2 (6)).
        FVector DeckPost = Get_ScenePoint(k_DeckPost);

        auto FloorPosts = TArray<FVector>();
        FloorPosts.Add(Get_ScenePoint(k_FloorPostNorth));
        FloorPosts.Add(Get_ScenePoint(k_FloorPostSouth));

        for (int32 Index = 0; Index < FloorPosts.Num(); Index++)
        {
            FLinearColor Color = CkGroundNavDemo::Get_WalkerColor(Index);

            _Walkers.Request_Add(_PcEntity, FName(f"GroundNavGym_LinksWalker{Index}"),
                FloorPosts[Index], DeckPost, k_AgentRadiusUu, k_WalkerHeightUu, Color,
                FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerGoalReached"),
                FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerGoalFailed"));

            _PostPoints.Add(FloorPosts[Index]);
            _PostLabels.Add(f"floor {Index + 1}");
            _PostColors.Add(Color);
        }

        FLinearColor DeckColor = FLinearColor(1.0, 1.0, 1.0, 1.0);

        _PostPoints.Add(DeckPost);
        _PostLabels.Add("deck");
        _PostColors.Add(DeckColor);
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

    // ---- Per frame ----------------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        // Observes, then draws every route and every body. Zero-lifetime lines throughout, so a replan
        // never leaves the abandoned route lying under the new one.
        _Walkers.Do_Tick();

        for (int32 Index = 0; Index < _PostPoints.Num(); Index++)
        { CkGroundNavDemo::Draw_GoalPost(_PostPoints[Index], _PostLabels[Index], _PostColors[Index]); }

        // Laundered into a typed local: the constant is const and Draw_WorldCaption takes its text
        // BY VALUE, and AS rejects a const value handed to a non-const value parameter.
        FString Caption = k_Caption;

        CkGroundNavDemo::Draw_WorldCaption(Get_ScenePoint(k_CaptionLocal), Caption);
    }

    // ---- The verdict ---------------------------------------------------------------------------------
    //
    // Two halves, and they INVERT with the toggle. With the links live both records must be resolved
    // and live and the walkers' routes must between them have named BOTH ids - the deck top is
    // reachable over a link and no other way, so a crossing is the only proof the join exists. With
    // them disabled both records must be dead and every walker must be holding - the deck is then an
    // island, and a body still walking to it would mean a disabled record is still being searched.
    //
    // Every criterion is a live readback off the published field, and the crossing record is the
    // walker set's own - the ids its planners have ever stepped onto, folded in as they are observed.

    // The window in which the station is between two settled answers and judges NOTHING: the field is
    // still republishing after a change, or the walkers have not yet finished proving the new state.
    // A verdict here would fail the station on its own keypress.
    private bool Get_IsBetween()
    {
        if (_OverlayRefresh.Get_IsWaiting())
        { return true; }

        if (Get_LinksAreEnabled() == false)
        { return _Walkers.Get_FailedCount() < _Walkers.Get_Count(); }

        return Get_UncrossedLinkCount() > 0;
    }

    // How many of the volume's records no walker's route has ever stepped onto. Read off the records
    // rather than counted to two, so a scene that authored a third link would be judged on it.
    private int32 Get_UncrossedLinkCount()
    {
        auto Volume = _Field.Get_Volume();

        if (ck::Is_NOT_Valid(Volume))
        { return 0; }

        auto Records = utils_ground_nav_volume::Get_LinkRecords(Volume);
        auto Crossed = _Walkers.Get_LinkIdsEverCrossed();

        int32 Count = 0;

        for (int32 Index = 0; Index < Records.Num(); Index++)
        {
            const auto LinkId = Records[Index].Get_Id();

            if (Crossed.Contains(LinkId) == false)
            { Count += 1; }
        }

        return Count;
    }

    private FString Get_CrossedIdsText()
    {
        auto Ids = _Walkers.Get_LinkIdsEverCrossed();

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

    private TArray<FString> Get_VerdictFailures()
    {
        auto Failures = TArray<FString>();

        // Nothing is judged before a body has moved, or while the field is still republishing under
        // one. Both windows are pending, not wrong.
        if (_Walkers.Get_AnyHasWalked() == false || _OverlayRefresh.Get_IsWaiting())
        { return Failures; }

        auto Volume = _Field.Get_Volume();

        if (_Field.Get_IsBuilt() == false || ck::Is_NOT_Valid(Volume))
        { return Failures; }

        auto Records = utils_ground_nav_volume::Get_LinkRecords(Volume);

        if (Records.Num() == 0)
        { return Failures; }

        // The gym's own arithmetic rather than a readback, and the only thing here that is: a batch
        // is atomic, so a refusal means NEITHER link was applied and every clause below is judging a
        // field the last keypress never reached.
        if (_BatchCompletions > 0 && _LastBatchResult != ECk_Request_OperationResult::Succeeded)
        { Failures.Add("the last link batch was refused - a batch is atomic, so neither link was applied"); }

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

        // With both links live, a body holding with no route has been refused a deck the ladder should
        // have given it. With them off, holding is the contract and is judged in Get_IsBetween.
        const auto Holding = _Walkers.Get_FailedCount();

        if (Enabled && Holding > 0)
        { Failures.Add(f"{Holding} walker(s) hold with no route while both links are live"); }

        return Failures;
    }

    private FString Get_VerdictLine(const TArray<FString>&in InFailures)
    {
        if (_Walkers.Get_AnyHasWalked() == false)
        { return CkGroundNavDemo::Get_VerdictPendingText(_Field); }

        if (InFailures.Num() > 0)
        { return CkGroundNavGym::Get_VerdictText("", InFailures); }

        if (Get_IsBetween())
        { return "replanning - the field is republishing under the walkers"; }

        if (Get_LinksAreEnabled() == false)
        { return "OK - both disabled, the deck is an island, walkers hold"; }

        return "OK - both links live; walkers crossed link " + Get_CrossedIdsText();
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
        return "GROUNDNAV: LINKS";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        const auto Failures = Get_VerdictFailures();

        FString Caption = k_Caption;

        TArray<FCkGym_ControlRow> Rows = CkGroundNavDemo::Get_HeaderRows(Caption,
            Get_VerdictLine(Failures), Failures.Num() > 0, _Walkers.Get_StatusText());

        Rows.Add(CkGym_Control::ToggleNamed(EKeys::U, "U",
            "Links (a disabled link is invisible to search and to reachability - the deck becomes an island)",
            Get_LinksAreEnabled(), "enabled", "disabled"));

        Rows.Add(CkGroundNavDemo::Get_DrawModeRow(_DrawModeIndex));

        return Rows;
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

        if (InRowIndex == k_Row_DrawMode)
        {
            _DrawModeIndex = (_DrawModeIndex + 1) % CkGroundNavGym::Get_DrawModeCount();

            if (_Field.Get_IsBuilt())
            { DoRefresh_Picture(); }

            return;
        }
    }
}
