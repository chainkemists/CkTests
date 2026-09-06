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

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Header and Status rows never reach Request_ControlActivated but they DO occupy an index. The
    // one keyed row sits ABOVE the resolution block, and that is not a preference: how many
    // resolution rows there are depends on how many records the volume holds, so a keyed row placed
    // after them would move between frames and the panel dispatches on the index.

    private const int32 k_Row_LinksToggle = 6;

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
        Description.Add(FText::FromString("The draw mode is set to 7 as soon as the field publishes, so the links are drawn over the plates they join. The DRAW row on the panel prints a ck.GroundNav.LinksAt aimed at this deck - the scene is placed off the station anchor, so the coordinates are only known once the gym has started - and that command draws both links and prints what each end resolved to. It reads the PUBLISHED field, so it needs no bake at all: green means traversable, grey disabled, orange an end over ground nobody has baked, red an end with no ground under it."));
        Description.Add(FText::FromString("Press U to disable both links and again to re-enable them. A disabled link is invisible to search and to reachability, and the LINKS rows below report each one's live state, read off the volume rather than remembered."));
        Description.Add(FText::FromString("Under the toggle there is one RESOLUTION row per link, straight from Get_LinkResolution: what each end projected onto, the flat plate it landed in, and whether the record resolved and is live. Every index in it is valid only against the field currently published, which is why the row is rebuilt each frame rather than remembered."));
        Description.Add(FText::FromString("The ladder is priced at twice its own straight-line span and narrowed to 40uu of clearance; the drop is priced at its span and admits any agent. A link never costs less than its own length - that is what keeps the search's Euclidean heuristic admissible."));
        Description.Add(FText::FromString("The VERDICT row at the top is the whole station in one line: both records resolved and live when the toggle is on, both dead when it is off, and the id of the one that disagrees otherwise."));
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
            DoAuthor_Links();
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

        // Mode 7 is the mode this gym is worth looking at in, so it is the mode it opens in. Set only
        // once the field publishes: before that there is nothing under the links to dim.
        System::ExecuteConsoleCommand(f"ck.GroundNav.Debug.Mode {k_LinkDrawMode}");

        const auto Polls = _Field.Get_SettlePolls();
        _Field.Set_Stage(f"authored after {Polls} settle polls");

        // The real command, not "0 0 0": this runs after the station anchor is known, so the line in
        // the log is one a reader can paste.
        ck::groundnav::Log(f"GroundNav links gym: the drop and the ladder are authored - {Get_LinksAtCommandText()} lists them");
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

        DoRequest_Links(Enable);

        ck::groundnav::Log("GroundNav links gym: link enable flipped - the derive republishes, then ck.GroundNav.LinksAt shows the new state");
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

    // ---- The verdict -------------------------------------------------------------------------------
    //
    // Every criterion is a LIVE readback off the published field: each end's projection status, the
    // record's own resolved flag, and its live flag - the same rule Get_IsLinkLive answers, carried on
    // the resolution so one read covers both questions. Nothing here is mirrored, and the enable
    // state the live flags are judged against is itself read off record 0.

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

        return Failures;
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
        { return "OK - both disabled"; }

        return "OK - both links resolved and live";
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
        Rows.Add(CkGym_Control::Status("Draw",
            f"{Get_LinksAtCommandText()} lists both and needs no bake; ck.GroundNav.Debug.Mode {k_LinkDrawMode} (already set) draws them over the plates they join"));
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
    // Rounded because the command line is read by a person, not parsed back.
    private FString Get_LinksAtCommandText()
    {
        const auto Where = Get_ScenePoint(k_DeckCentre);

        const auto X = Math::RoundToInt(float32(Where.X));
        const auto Y = Math::RoundToInt(float32(Where.Y));
        const auto Z = Math::RoundToInt(float32(Where.Z));

        return f"ck.GroundNav.LinksAt {X} {Y} {Z}";
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
    }
}
