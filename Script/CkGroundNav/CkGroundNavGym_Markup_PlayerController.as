class ACk_GroundNavGym_Markup_PlayerController : ACk_Gym_Base_PlayerController
{
    // ---- The scene -------------------------------------------------------------------------------
    //
    // Every dimension below is LOCAL, and the scene is placed off the station's own footprint anchor:
    // the grid layout places the station, so a hardcoded world position is wrong the moment the grid
    // changes. Stations face world -X, and the offset clears the slab's 1800uu half-width by 500.

    private const FVector k_SceneOffset = FVector(-2300.0, 0.0, 0.0);

    // 3600 x 2000, top face at Z 0, so the scene's local Z 0 is the ground everything stands on. The
    // Z scale is 2.0, well past the 0.5 below which a slab bakes to zero walkable tiles.

    private const FVector k_SlabCentre = FVector(0.0, 0.0, -100.0);
    private const FVector k_SlabScale  = FVector(36.0, 20.0, 2.0);

    // The strip: across the middle, Y -1000 to +600 - 1600 of the slab's 2000 width, 80% of it, with
    // the remaining 400uu open at the NORTH end. Nothing is cut off, so a walker holding with no route
    // is a fault and not the design. Z spans 100 under the top face to 300 over it, so the box
    // swallows the whole walkable band.

    private const FVector k_StripCentre      = FVector(0.0, -200.0, 100.0);
    private const FVector k_StripHalfExtents = FVector(100.0, 800.0, 200.0);

    // Four bodies west to east on four lanes, spread rather than stacked: bodies born inside each other
    // spend their first seconds pushing apart, which is avoidance and says nothing about routing. The
    // posts clear the east and west edges by 200uu, and the outermost lane (+/-525) the others by 475.

    private const int32   k_WalkerCount    = 4;
    private const float   k_LaneSpacingUu  = 350.0f;
    private const FVector k_WestPost       = FVector(-1600.0, 0.0, 100.0);
    private const FVector k_EastPost       = FVector(1600.0, 0.0, 100.0);
    private const float   k_WalkerHeightUu = 180.0f;

    // The volume: the slab and 200uu of margin on every side, so the perimeter cliff is inside the
    // region rather than clipped by it.

    private const FVector k_VolumeMin = FVector(-2000.0, -1200.0, -300.0);
    private const FVector k_VolumeMax = FVector(2000.0, 1200.0, 500.0);

    // The same 25uu lattice every GroundNav gym bakes on, so the volumes are directly comparable. The
    // agent is the default 34uu body at 180uu standing height.
    private const float k_CellSizeUu        = 25.0f;
    private const float k_CellHeightUu      = 10.0f;
    private const float k_TileSizeUu        = 800.0f;
    private const float k_AgentRadiusUu     = 34.0f;
    private const float k_AgentHalfHeightUu = 90.0f;

    // 0.05s a poll, so thirty seconds of waiting on a NAMED condition before the gym gives up and
    // says so in its own Verdict rather than hanging silently.
    private const int32 k_SettlePollCeiling = 600;

    // A paint is DEFERRED, so the picture and the replan are owed to the republish and not the keypress.
    // Ten seconds at 0.05s a poll, after which the redraw runs anyway on whatever the field holds.
    private const int32 k_OverlayPollCeiling = 200;

    // The debug picture. The extent is a half-extent and 1900 covers the slab's 1800 half-X - about
    // twenty-three thousand columns on the 25uu lattice, inside the cell ceiling - and the height is
    // centred 100uu over the top face. Only the REGION is stated here: every filter the bake runs is
    // pushed from the volume by Request_BakeDebugFieldAt, so the two cannot describe different fields.
    private const FVector k_BakeCentre        = FVector(0.0, 0.0, 100.0);
    private const float   k_DebugBakeExtentUu = 1900.0f;
    private const float   k_DebugBakeHeightUu = 400.0f;
    private const int32   k_DebugBakeMaxCells = 40000;

    // Where the one-line caption stands in the world, clear of the walkers' heads.
    private const FVector k_CaptionPoint = FVector(0.0, 0.0, 900.0);

    // Plates: ground the paint closes is a plate that was there before and is not now, which is the
    // only mode in which a paint reads as anything.
    private const int32 k_PlateDrawMode = 0;

    // Frames the whole slab, both post lines and the strip from the scene's south-east.
    private const FVector  k_ViewOffset   = FVector(2200.0, -2000.0, 1800.0);
    private const FRotator k_ViewRotation = FRotator(-31.0, 138.0, 0.0);

    // Row layout: the three demo header rows (This shows / Verdict / Walkers) are 0-2, the paint key is
    // 3, and the T picture row is LAST at 4. Nothing here is variable-length, so no row can move.
    private const int32 k_Row_Paint    = 3;
    private const int32 k_Row_DrawMode = 4;

    // ---- State -------------------------------------------------------------------------------------

    private FCk_Handle _PcEntity;
    private FVector _Origin = FVector::ZeroVector;
    private bool _GeometryIsBuilt = false;

    // Ck_Gym_Restart re-runs Request_StartGym on the SAME controller, and the slab is a spawned actor
    // nothing holds a handle to - a second pass would stack a second one, invisible to every row.
    private bool _SceneSpawned = false;

    private FCkGroundNavGym_Field _Field;
    private FCkGroundNavDemo_WalkerSet _Walkers;
    private FCkGroundNavGym_OverlayRefresh _OverlayRefresh;

    private int32 _DrawModeIndex = k_PlateDrawMode;

    // The paint's lifetime IS this handle - releasing it is destroying the markup entity - so whether
    // the strip is painted is read off the handle rather than off a bool.
    private FCk_Handle_NavSurfaceMarkup _Markup;

    // The build epoch as it stood the instant BEFORE the paint went on - a SNAPSHOT taken at the
    // action, and the verdict's claim that the paint took effect is its difference from the epoch now.
    private int64 _EpochAtPaint = 0;

    // The posts, in world space, kept so Tick can draw them where the walkers were actually sent.
    private TArray<FVector> _WestPosts;
    private TArray<FVector> _EastPosts;

    // ---- Station -----------------------------------------------------------------------------------

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // No Transform: the base grid places it, and the scene is built off the anchor it lands on.
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"GroundNavMarkup");
        Station.AutoSize = true;
        Station.Title = FText::FromString("GroundNav - Markup");

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Four walkers patrol west to east across one slab, each drawing the route it is walking."));
        Description.Add(FText::FromString("Press 2 to paint a strip impassable across the middle: it covers 80% of the slab and leaves a 400uu gap at the north end, so every route detours through that gap. Press 2 again to release it."));
        Description.Add(FText::FromString("T cycles what the debug picture under the walkers shows. The Verdict row is the pass/fail."));
        Station.Description = Description;

        Stations.Add(Station);

        return Stations;
    }

    // ---- Startup -----------------------------------------------------------------------------------

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        _PcEntity = ck::ToEntity(this);

        if (ck::Is_NOT_Valid(_PcEntity))
        {
            ck::groundnav::Warning("GroundNav markup gym: PC entity invalid; cannot start");
            return;
        }

        _Origin = Get_StationAnchorLocation("GroundNavMarkup", ECk_GymStation_Anchor::FootprintCenter);

        _GeometryIsBuilt = DoBuildScene();

        if (_GeometryIsBuilt == false)
        {
            ck::Error("GroundNav markup gym: the scene failed to bake into the Jolt static world - the field has nothing to bake over", n"GroundNavGym.Scene", 10.0);
        }

        DoBringPlayerToViewpoint();
        DoWaitOneFrame(n"OnViewpointSettle");

        DoArm_Field();

        ck::groundnav::Log("GroundNav markup gym: scene built - the walkers are released once the field settles");
    }

    // Scene-local to world. Everything the gym spawns, bakes, paints and walks goes through here, so
    // the scene is one translation away from the station the grid layout happened to place.
    private FVector Get_ScenePoint(FVector InLocal)
    {
        return _Origin + k_SceneOffset + InLocal;
    }

    private bool DoBuildScene()
    {
        // Guarded, not idempotent by luck: a restart keeps the scene it already spawned, which is also
        // the scene the volume was baked over.
        if (_SceneSpawned)
        { return true; }

        _SceneSpawned = true;

        return CkGroundNavGym::Spawn_Box(this, Get_ScenePoint(k_SlabCentre), k_SlabScale);
    }

    private void DoBringPlayerToViewpoint()
    {
        CkGroundNavGym::Request_FlyToStation(this, "GroundNavMarkup",
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

    // ---- The volume --------------------------------------------------------------------------------

    private void DoArm_Field()
    {
        if (_GeometryIsBuilt == false)
        {
            _Field.Set_Stage("the scene is not in the Jolt static world - nothing to bake over");
            return;
        }

        // A field is minted ONCE, so a restart is turned away by the mint's own guard and the settle
        // poll never fires again. The retained draw is command-driven, so the picture is owed here.
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
        // its whole perimeter - and the outermost lanes run within 475uu of that edge.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(Get_ScenePoint(k_VolumeMin), Get_ScenePoint(k_VolumeMax));

        _Field.Request_Mint(_PcEntity, n"GroundNavGym_MarkupField", Bounds, Config, Profile,
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
    // the published field is the one every route is planned against.
    UFUNCTION()
    private void OnFieldSettlePoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Step = _Field.Do_PollSettle();

        if (Step == ECkGroundNavGym_Settle::Settled)
        {
            DoRefresh_Picture();

            // Released ONCE, on the first settle. A rebuild settles again and must not put a second
            // set of bodies on the slab.
            if (_Walkers.Get_Count() == 0)
            { DoSpawn_Walkers(); }

            return;
        }

        if (Step == ECkGroundNavGym_Settle::GaveUp)
        {
            _Field.Set_Stage("the surface never settled - the walkers have nothing to stand on");
            ck::groundnav::Log("GroundNav markup gym: the field never settled - no walkers were released");
        }
    }

    // A draw MODE is not a draw: nothing redraws on its own, so the plates exist only because this ran.
    // DrawMarkup goes with it, so the strip is in the picture and not only in this gym's wireframe.
    private void DoRefresh_Picture()
    {
        System::ExecuteConsoleCommand("ck.GroundNav.Debug.DrawMarkup 1");

        CkGroundNavGym::Request_BakeDebugFieldAt(_Field, Get_ScenePoint(k_BakeCentre),
            k_DebugBakeExtentUu, k_DebugBakeHeightUu, k_DebugBakeMaxCells, _DrawModeIndex);
    }

    // Waits for the derive the paint provoked to publish, then redraws and re-plans. The named
    // condition - epoch moved, surface quiet - lives in FCkGroundNavGym_OverlayRefresh.
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

        // HERE and not at the keypress. This is the moment the ground under the bodies changed, so a
        // route re-asked now is planned against the field the paint is actually in.
        _Walkers.Request_ReplanAll();
    }

    // ---- The walkers -------------------------------------------------------------------------------

    private void DoSpawn_Walkers()
    {
        for (int32 Index = 0; Index < k_WalkerCount; Index++)
        {
            const auto Offset = (float(Index) - (float(k_WalkerCount - 1) * 0.5f)) * k_LaneSpacingUu;

            const auto PostA = Get_ScenePoint(k_WestPost + FVector(0.0, Offset, 0.0));
            const auto PostB = Get_ScenePoint(k_EastPost + FVector(0.0, Offset, 0.0));

            _WestPosts.Add(PostA);
            _EastPosts.Add(PostB);

            _Walkers.Request_Add(_PcEntity, FName(f"GroundNavGym_MarkupWalker{Index}"), PostA, PostB,
                k_AgentRadiusUu, k_WalkerHeightUu, CkGroundNavDemo::Get_WalkerColor(Index),
                FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerGoalReached"),
                FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerGoalFailed"));
        }
    }

    // A struct cannot carry a UFUNCTION, so the crowd's signals bind here and are forwarded to the
    // set, which finds the walker by its entity handle.
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

    // ---- The paint ---------------------------------------------------------------------------------
    //
    // The PROVIDER-NEUTRAL request the crowd itself goes through: it names a shape and a place and
    // nothing about which backend answers it. Releasing it is destroying the markup entity.

    private void DoToggle_Paint()
    {
        if (ck::IsValid(_Markup))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup));
            _Markup = FCk_Handle_NavSurfaceMarkup();

            DoArm_OverlayRefresh();

            ck::groundnav::Log("GroundNav markup gym: the strip is released - the lanes reopen once the field republishes");
            return;
        }

        // Nothing to paint over and no epoch to snapshot until a volume stands. The row is disabled
        // until then, but the panel polls raw keys, so the guard lives here too.
        if (ck::Is_NOT_Valid(_Field.Get_Volume()))
        { return; }

        // Read BEFORE the request, so the number the verdict compares against is the epoch the field
        // was published at when the paint went on rather than one the derive had already moved.
        _EpochAtPaint = utils_ground_nav_volume::Get_BuildEpoch(_Field.Get_Volume());

        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(k_StripHalfExtents)),
            FGameplayTag());
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_ScenePoint(k_StripCentre), FVector::OneVector));

        _Markup = utils_nav_surface::Request_ImpassableBox(Request);

        if (ck::Is_NOT_Valid(_Markup))
        {
            ck::groundnav::Warning("GroundNav markup gym: the paint request handed back no markup handle - nothing was carved");
            return;
        }

        DoArm_OverlayRefresh();

        ck::groundnav::Log("GroundNav markup gym: the strip is painted impassable - every lane detours through the 400uu gap at the north end");
    }

    // How far the field has moved since the paint went on. Zero while the derive has not answered yet,
    // which is a wait and not a fault.
    private int64 Get_EpochSincePaint()
    {
        return utils_ground_nav_volume::Get_BuildEpoch(_Field.Get_Volume()) - _EpochAtPaint;
    }

    // ---- Per-frame drawing -------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        _Walkers.Do_Tick();

        // Both post lines, each pair in its walker's own colour so a route can be traced to its ends.
        for (int32 Index = 0; Index < _WestPosts.Num(); Index++)
        {
            FLinearColor PostColor = CkGroundNavDemo::Get_WalkerColor(Index);

            CkGroundNavDemo::Draw_GoalPost(_WestPosts[Index], f"{Index} west", PostColor);
            CkGroundNavDemo::Draw_GoalPost(_EastPosts[Index], f"{Index} east", PostColor);
        }

        DoDraw_Strip();

        CkGroundNavDemo::Draw_WorldCaption(Get_ScenePoint(k_CaptionPoint), Get_Caption());
    }

    // The painted box, drawn each frame at zero duration so the reader sees WHERE the routes bend and
    // why. Only while the paint is held - a box drawn off a bool would outlive the thing it names.
    private void DoDraw_Strip()
    {
        if (ck::Is_NOT_Valid(_Markup))
        { return; }

        // Declared non-const: `auto` preserves const, and DrawDebugBox takes its colour BY VALUE.
        FLinearColor StripColor = FLinearColor(1.0, 0.20, 0.15, 1.0);
        FVector Centre = Get_ScenePoint(k_StripCentre);
        FVector Extent = k_StripHalfExtents;

        utils_debug_draw::DrawDebugBox(Centre, Extent, StripColor, FRotator::ZeroRotator, 0.0f, 6.0f);

        utils_debug_draw::DrawDebugString(Centre + FVector(0.0, 0.0, Extent.Z + 60.0),
            "painted impassable", StripColor, 0.0f);
    }

    // ---- The verdict -------------------------------------------------------------------------------
    //
    // Every criterion is a LIVE readback: the markup's live flag off its handle, the epoch off the
    // volume, each walker's state off its own agent. The one thing remembered is the epoch as it
    // stood at the paint - a measurement of the field at the instant of the action.

    private TArray<FString> Get_VerdictFailures()
    {
        auto Failures = TArray<FString>();

        if (_Field.Get_IsBuilt() == false)
        { return Failures; }

        const auto FailedCount = _Walkers.Get_FailedCount();

        if (FailedCount > 0)
        {
            Failures.Add(f"{FailedCount} of {_Walkers.Get_Count()} walkers hold with no route - the strip leaves a 400uu gap open at the north end, so every lane has a way round");
        }

        if (ck::Is_NOT_Valid(_Markup))
        { return Failures; }

        // A paint is answered a publish later, and reddening the row for that window would fail the gym
        // on its own keypress. The refresh has its own ceiling, so this cannot hide a paint that never
        // took - once it stops waiting, both clauses below apply.
        if (_OverlayRefresh.Get_IsWaiting())
        { return Failures; }

        if (Get_EpochSincePaint() <= 0)
        {
            Failures.Add("the strip is painted but the field has not republished since it went on");
        }
        else if (utils_nav_surface::Get_IsMarkupLive(_Markup) == false)
        {
            Failures.Add("the field republished but the markup never went live - the strip is not in effect");
        }

        return Failures;
    }

    private FString Get_VerdictLine(const TArray<FString>&in InFailures)
    {
        // Before any body has walked there is no route to judge, and the frame's own text says which
        // half of the wait the gym is in.
        if (_Walkers.Get_AnyHasWalked() == false)
        { return CkGroundNavDemo::Get_VerdictPendingText(_Field); }

        if (InFailures.Num() > 0)
        { return CkGroundNavGym::Get_VerdictText("", InFailures); }

        if (ck::IsValid(_Markup))
        {
            if (_OverlayRefresh.Get_IsWaiting())
            { return "painted - the field is republishing and the walkers are replanning"; }

            const auto Detouring = _Walkers.Get_WalkingCount() + _Walkers.Get_PendingCount();

            return f"OK - painted, epoch +{Get_EpochSincePaint()}, {Detouring} walkers detouring through the gap";
        }

        if (_Walkers.Get_AllHaveWalked() == false)
        { return f"clear - {_Walkers.Get_Count()} lanes open, waiting for every walker to start"; }

        return f"OK - the strip is clear and all {_Walkers.Get_Count()} walkers cross straight through";
    }

    private FString Get_Caption()
    {
        return "Paint a strip impassable - the field republishes and every walker detours through the gap";
    }

    // ---- Control panel -----------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "GROUNDNAV: MARKUP";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        const auto Failures = Get_VerdictFailures();

        // The failure list is only a verdict once a body has walked, and Get_VerdictLine says so - so
        // the hot flag is gated on the same thing rather than reddening the row during startup.
        const auto VerdictFails = _Walkers.Get_AnyHasWalked() && Failures.Num() > 0;

        auto HeaderRows = CkGroundNavDemo::Get_HeaderRows(Get_Caption(), Get_VerdictLine(Failures),
            VerdictFails, _Walkers.Get_StatusText());

        for (int32 Index = 0; Index < HeaderRows.Num(); Index++)
        { Rows.Add(HeaderRows[Index]); }

        // Disabled until the volume stands: there is nothing to paint over before it, and no epoch to
        // measure the paint against.
        Rows.Add(CkGym_Control::ToggleNamed(EKeys::Two, "2",
            "Paint the strip impassable (80% of the slab, a 400uu gap left open at the north end)",
            ck::IsValid(_Markup), "painted", "clear", false, _Field.Get_IsBuilt()));

        Rows.Add(CkGroundNavDemo::Get_DrawModeRow(_DrawModeIndex));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (HasAuthority() == false)
        { return; }

        if (InRowIndex == k_Row_Paint)
        {
            DoToggle_Paint();
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
