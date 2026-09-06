class ACk_GroundNavGym_Parity_PlayerController : ACk_Gym_Base_PlayerController
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
    // The Walk gym's ground without its ramp or its island: 3600 x 2400, walkable face at the scene's
    // Z 0. ACk_Gym_Floor's surface is at the ACTOR'S ORIGIN, so the centre below IS the Z bodies stand
    // on. Z scale must stay >= 0.5 - thinner slabs bake to zero walkable tiles.
    private const FVector k_SlabCentre = FVector(0.0, 0.0, 0.0);
    private const FVector k_SlabScale  = FVector(36.0, 24.0, 0.5);

    // ---- The pillars ------------------------------------------------------------------------------
    //
    // Four 150 x 150 x 300 boxes standing on the slab's middle band, two of them planted squarely on a
    // walker lane and two between lanes, so a west-east route has to weave rather than run straight.
    // Straight routes on both backends would compare nothing.
    private const FVector k_PillarScale = FVector(1.5, 1.5, 3.0);

    private const FVector k_Pillar0Centre = FVector(-800.0, -150.0, 150.0);
    private const FVector k_Pillar1Centre = FVector(-300.0, 300.0, 150.0);
    private const FVector k_Pillar2Centre = FVector(300.0, -300.0, 150.0);
    private const FVector k_Pillar3Centre = FVector(800.0, 150.0, 150.0);

    // ---- The volume -------------------------------------------------------------------------------
    //
    // The slab and the pillars standing on it, with a margin past the slab's own perimeter cliff so
    // nothing this gym answers is about the edge of the ground it stands on.
    private const FVector k_VolumeMin = FVector(-2000.0, -1400.0, -300.0);
    private const FVector k_VolumeMax = FVector(2000.0, 1400.0, 500.0);

    // The same 25uu lattice every GroundNav fixture in the corpus bakes on. The 800uu tiles suit a slab
    // this wide, and the agent is the default 34uu body at 180uu standing height - the same body the
    // walkers are spawned as, so the field and the walkers describe one agent.
    private const float k_CellSizeUu        = 25.0f;
    private const float k_CellHeightUu      = 10.0f;
    private const float k_TileSizeUu        = 800.0f;
    private const float k_AgentRadiusUu     = 34.0f;
    private const float k_AgentHalfHeightUu = 90.0f;
    private const float k_WalkerHeightUu    = 180.0f;

    // 0.05s a poll, so this is thirty seconds of waiting on a NAMED condition before the gym gives up
    // and says so in the Verdict rather than hanging silently.
    private const int32 k_SettlePollCeiling = 600;

    // ---- The walkers ------------------------------------------------------------------------------
    //
    // Three bodies on three lanes 300uu apart, patrolling between posts 3000uu apart in X. Both posts
    // are 100uu above the slab, which is where a 180uu body's centre stands.
    private const int32   k_WalkerCount       = 3;
    private const float   k_WalkerLaneUu      = 300.0f;
    private const FVector k_WalkerWestPoint   = FVector(-1500.0, 0.0, 100.0);
    private const FVector k_WalkerEastPoint   = FVector(1500.0, 0.0, 100.0);

    // ---- The picture ------------------------------------------------------------------------------
    //
    // Only the REGION is stated here: 1850 is a half-extent, so the bake covers the slab's own 3600uu
    // span with room to spare, and 400uu of height reaches from under the slab to over the pillars'
    // heads. Every filter - the lattice, the agent capsule, the slope limits, the ledge sensitivity
    // this slab needs pinned off - is pushed from the volume by Request_BakeDebugFieldAt, so the
    // picture and the field cannot describe different ground.
    private const FVector k_PictureBakeCentre = FVector(0.0, 0.0, 100.0);
    private const float   k_DebugBakeExtentUu = 1850.0f;
    private const float   k_DebugBakeHeightUu = 400.0f;
    private const int32   k_DebugBakeMaxCells = 40000;

    // Where the picture starts: the plates, which is the surface the walkers are routing over.
    private const int32 k_PlateDrawMode = 0;

    // Frames the whole slab, both post lines and all four pillars from the scene's south-east, high
    // enough that the weave between the pillars reads as a weave.
    private const FVector  k_ViewOffset   = FVector(2400.0, -1800.0, 1700.0);
    private const FRotator k_ViewRotation = FRotator(-29.5, 143.1, 0.0);

    // ---- Control row indices ---------------------------------------------------------------------
    //
    // Layout: the three shared demo header rows (This shows / Verdict / Walkers) occupy 0-2, so the
    // first keyed row is CkGroundNavDemo::k_DemoHeaderRowCount. The T row is LAST, as it is on every
    // demo gym. Status rows never reach Request_ControlActivated but they DO occupy an index.
    //
    //   0-2  header rows
    //   3    1 - provider
    //   4    2 - Recast's navmesh draw
    //   5    T - picture

    private const int32 k_Row_Provider = 3;
    private const int32 k_Row_NavDraw  = 4;
    private const int32 k_Row_DrawMode = 5;

    // ---- State -----------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FVector _Origin = FVector::ZeroVector;
    private bool _GeometryIsBuilt = false;

    // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and the slab and the pillars are
    // spawned actors that nothing here holds a handle to - so a second pass would stack a whole second
    // scene into the Jolt static world, invisible to every row. Spawned once per controller.
    private bool _SceneSpawned = false;

    private FCkGroundNavGym_Field _Field;
    private FCkGroundNavDemo_WalkerSet _Walkers;

    private int32 _DrawModeIndex = k_PlateDrawMode;

    // The posts, in world space, kept so Tick can draw them where the walkers were sent. Rebuilt with
    // the walkers, because the lanes are derived from how many there are.
    private TArray<FVector> _PostsWest;
    private TArray<FVector> _PostsEast;

    // Mirrored rather than read back, and that is forced: `show Navigation` is a viewport show flag
    // with no binding AngelScript can query. The row therefore reports what this controller last asked
    // for - the one value on this panel that is not a readback.
    private bool _NavDrawEnabled = false;

    // ---- Station ---------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // No Transform: the base grid places it, and the scene is built off the anchor it lands on.
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavParity");
        Station.AutoSize = true;
        Station.Title = FText::FromString("GroundNav - GroundNav vs Recast");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Three walkers weave west to east through four pillars while one navigation backend or the other answers their routes."));
        Description.Add(FText::FromString("Press 1 to flip the provider - the walkers respawn so the Verdict judges the backend that is answering now. Press 2 for Recast's own navmesh draw."));
        Description.Add(FText::FromString("T cycles what the GroundNav picture under them shows."));
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
            ck::groundnav::Warning("GroundNav parity gym: PC entity invalid; cannot start");
            return;
        }

        _Origin = Get_StationAnchorLocation("GroundNavParity", ECk_GymStation_Anchor::FootprintCenter);

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav parity gym: the scene failed to bake into the Jolt static world - the field has nothing to bake over", n"GroundNavGym.Scene", 10.0);
        }

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        DoArm_Field();

        ck::groundnav::Log("GroundNav parity gym: scene built - the walkers start once the field settles, and key 1 swaps which backend routes them");
    }

    // Scene-local to world. Everything the gym spawns, bakes and sends a body to goes through here, so
    // the scene is one translation away from the station the grid layout happened to place.
    private FVector Get_ScenePoint(FVector InLocal)
    {
        return _Origin + k_SceneOffset + InLocal;
    }

    // ---- The field --------------------------------------------------------------------------------

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
        // re-minted would leave the reader looking at whatever the last gym in this world drew.
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
        // its whole perimeter - and the posts sit 1500uu out towards that edge, so bodies released on
        // them would be standing on ground the filter had thrown away.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(Get_ScenePoint(k_VolumeMin), Get_ScenePoint(k_VolumeMax));

        _Field.Request_Mint(_PcEntity, n"GroundNavGym_ParityField", Bounds, Config, Profile,
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
            DoRefresh_Picture();

            if (_Walkers.Get_Count() == 0)
            { DoSpawn_Walkers(); }

            return;
        }

        if (Step == ECkGroundNavGym_Settle::GaveUp)
        {
            _Field.Set_Stage("the surface never settled - no walkers were released");
            ck::groundnav::Log("GroundNav parity gym: the field never settled - the walkers have nothing to route over");
        }
    }

    UFUNCTION()
    private void OnFieldBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Field.Notify_BuildCompleted(InResult);
    }

    // The GroundNav debug picture, and it is deliberately NOT provider-aware: ck.GroundNav.BakeFieldAt
    // bakes GroundNav's own debug field whichever backend is currently routing, so what the reader sees
    // under the walkers stays the same while the routes over it change. Recast's own surface is drawn
    // by its show flag on key 2, beside this rather than instead of it.
    private void DoRefresh_Picture()
    {
        CkGroundNavGym::Request_BakeDebugFieldAt(_Field, Get_ScenePoint(k_PictureBakeCentre),
            k_DebugBakeExtentUu, k_DebugBakeHeightUu, k_DebugBakeMaxCells, _DrawModeIndex);
    }

    // ---- The walkers ------------------------------------------------------------------------------
    //
    // Destroyed and respawned rather than replanned on a provider swap, and that is the verdict's
    // requirement rather than a convenience: FCkGroundNavDemo_Walker remembers that it has been seen
    // walking, and a record earned on GroundNav would go on vouching for Recast. A fresh body has
    // walked nowhere, so the Verdict judges the backend that is answering now. The spawn asks for the
    // first leg itself, so no replan is owed on top of it.

    private void DoSpawn_Walkers()
    {
        _Walkers.Request_DestroyAll();

        _PostsWest.Empty();
        _PostsEast.Empty();

        for (int32 Index = 0; Index < k_WalkerCount; Index++)
        {
            const auto Lane = (float(Index) - (float(k_WalkerCount - 1) * 0.5f)) * k_WalkerLaneUu;

            // Declared non-const: TArray::Add takes a non-const reference, and `auto` would preserve
            // the const-ness of a `const auto` local.
            FVector West = Get_ScenePoint(k_WalkerWestPoint + FVector(0.0, Lane, 0.0));
            FVector East = Get_ScenePoint(k_WalkerEastPoint + FVector(0.0, Lane, 0.0));

            _PostsWest.Add(West);
            _PostsEast.Add(East);

            _Walkers.Request_Add(_PcEntity, FName(f"GroundNavGym_ParityWalker{Index}"), West, East,
                k_AgentRadiusUu, k_WalkerHeightUu, CkGroundNavDemo::Get_WalkerColor(Index),
                FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerGoalReached"),
                FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerGoalFailed"));
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

    // ---- The provider -----------------------------------------------------------------------------

    private void DoCycle_Provider()
    {
        CkGroundNavGym::Request_CycleProvider();

        // The walkers go with it - see the note above DoSpawn_Walkers.
        DoSpawn_Walkers();

        ck::groundnav::Log("GroundNav parity gym: provider swapped and the walkers respawned - the Verdict now judges the backend that is answering");
    }

    private FString Get_ProviderShortName()
    {
        if (utils_nav_surface::Get_Provider() == ECk_NavSurface_Provider::GroundNav)
        { return "GroundNav"; }

        return "Recast";
    }

    // ---- Recast's own draw ------------------------------------------------------------------------

    // The show flag is a TOGGLE with no reader, so the bool is flipped beside it rather than read back.
    // It draws Recast's navmesh wherever the level's own NavMeshBoundsVolume has baked one - which is
    // exactly what makes a Recast route failure legible: no green sheet under the slab means no navmesh
    // covers the station, and there is nothing there for a body to walk on.
    private void DoToggle_NavDraw()
    {
        _NavDrawEnabled = _NavDrawEnabled == false;

        System::ExecuteConsoleCommand("show Navigation");
    }

    // ---- The picture control ----------------------------------------------------------------------

    private void DoCycle_DrawMode()
    {
        _DrawModeIndex = (_DrawModeIndex + 1) % CkGroundNavGym::Get_DrawModeCount();

        if (_Field.Get_IsBuilt() == false)
        { return; }

        DoRefresh_Picture();
    }

    // ---- Per frame --------------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        _Walkers.Do_Tick();

        for (int32 Index = 0; Index < _PostsWest.Num(); Index++)
        {
            FLinearColor Color = CkGroundNavDemo::Get_WalkerColor(Index);

            CkGroundNavDemo::Draw_GoalPost(_PostsWest[Index], f"W{Index} west", Color);
            CkGroundNavDemo::Draw_GoalPost(_PostsEast[Index], f"W{Index} east", Color);
        }

        CkGroundNavDemo::Draw_WorldCaption(Get_ScenePoint(FVector(0.0, 0.0, 900.0)), Get_Caption());
    }

    // ---- The verdict ------------------------------------------------------------------------------
    //
    // One rule, asked of whichever backend is answering: every walker crosses. A body that is refused a
    // route is the failure, and on Recast it has exactly one cause worth naming - the level's
    // NavMeshBoundsVolume has baked nothing over this station, so there is no surface under the slab
    // for a route to exist on. GroundNav bakes its own volume from the Jolt static world and has no
    // such dependency, which is the whole comparison this station is for.
    //
    // The record the rule reads is reset on every provider swap by respawning the walkers, so it can
    // never vouch for the backend that is no longer answering.

    private FString Get_VerdictLine()
    {
        if (_Walkers.Get_AnyHasWalked() == false)
        { return CkGroundNavDemo::Get_VerdictPendingText(_Field); }

        const auto Provider = Get_ProviderShortName();
        const auto Failed = _Walkers.Get_FailedCount();
        const auto Total = _Walkers.Get_Count();

        if (Failed > 0)
        {
            FString Reason = f"{Provider}: no route for {Failed} walkers";

            if (utils_nav_surface::Get_Provider() == ECk_NavSurface_Provider::Recast)
            { Reason += " - on Recast this means no navmesh covers the station"; }

            auto Failures = TArray<FString>();
            Failures.Add(Reason);

            return CkGroundNavGym::Get_VerdictText("", Failures);
        }

        // Not a fault and not an OK: bodies that have not had their first route yet.
        if (_Walkers.Get_AllHaveWalked() == false)
        {
            const auto Started = _Walkers.Get_WalkingCount();
            return f"{Provider}: {Started} of {Total} walking - verdict pending";
        }

        return f"OK - {Provider}: {Total} walkers crossing";
    }

    private bool Get_VerdictFails()
    {
        if (_Walkers.Get_AnyHasWalked() == false)
        { return false; }

        return _Walkers.Get_FailedCount() > 0;
    }

    // ---- Control panel ----------------------------------------------------------------------------

    private FString Get_Caption()
    {
        return "The same walkers, the same scene, the provider flipped live - both surfaces answer";
    }

    FString Get_ControlPanelTitle() override
    {
        return "GROUNDNAV: VS RECAST";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        auto Header = CkGroundNavDemo::Get_HeaderRows(Get_Caption(), Get_VerdictLine(),
            Get_VerdictFails(), _Walkers.Get_StatusText());

        for (int32 Index = 0; Index < Header.Num(); Index++)
        { Rows.Add(Header[Index]); }

        // The value is read off the world as the row is built - the provider is a per-WORLD choice and
        // this gym is not the only thing that can have set it.
        Rows.Add(CkGym_Control::Cycle(EKeys::One, "1",
            "Provider (the walkers respawn, so the Verdict judges the one answering now)",
            CkGroundNavGym::Get_ProviderLabel()));

        Rows.Add(CkGym_Control::ToggleNamed(EKeys::Two, "2",
            "Recast's own navmesh draw (show Navigation)",
            _NavDrawEnabled, "drawn", "off"));

        // LAST, on every demo gym.
        Rows.Add(CkGroundNavDemo::Get_DrawModeRow(_DrawModeIndex));

        return Rows;
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

        if (InRowIndex == k_Row_NavDraw)
        {
            DoToggle_NavDraw();
            return;
        }

        if (InRowIndex == k_Row_DrawMode)
        {
            DoCycle_DrawMode();
            return;
        }
    }

    // ---- Scene construction -----------------------------------------------------------------------

    private bool DoBuildScene()
    {
        // Guarded, not idempotent by luck: see _SceneSpawned. A restart keeps the scene it already
        // spawned, which is also the scene the volume was baked over.
        if (_SceneSpawned)
        { return true; }

        _SceneSpawned = true;

        if (CkGroundNavGym::Spawn_Floor(Get_ScenePoint(k_SlabCentre), k_SlabScale) == nullptr)
        { return false; }

        // The pillars are scene geometry like the slab, so they go into the Jolt static world through
        // the same call - the volume bakes from that world and from nothing else. Recast reads the
        // level's own collision instead, which is why the same four boxes have to be real actors and
        // not markup: this station only compares two backends if both can see the same obstacles.
        if (CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_Pillar0Centre), k_PillarScale) == false)
        { return false; }

        if (CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_Pillar1Centre), k_PillarScale) == false)
        { return false; }

        if (CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_Pillar2Centre), k_PillarScale) == false)
        { return false; }

        if (CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_Pillar3Centre), k_PillarScale) == false)
        { return false; }

        return true;
    }

    private void DoBringPlayerToViewpoint()
    {
        CkGroundNavGym::Request_FlyToStation(this, "GroundNavParity",
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
}
