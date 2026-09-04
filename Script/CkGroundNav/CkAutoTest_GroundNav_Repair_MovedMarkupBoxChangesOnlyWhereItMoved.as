// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A MOVED BOX CHANGES ONLY WHERE IT MOVED
//============================================================================
//
// The other half of the local-repair contract.
// CkAutoTest_GroundNav_Repair_DoorToggleRepairsLocally pins that a box painted
// and released in ONE place repairs only there; this pins that a box MOVED
// repairs only the ground it left and the ground it arrived on, and never the
// columns of field between which nothing happened.
//
// WHAT A MOVE IS HERE. The old box is destroyed and a new one painted 1200uu
// away in the SAME frame - the move idiom the Recast baseline
// CkAutoTest_NavSurface_RecastBudgets_MovedObstacleRepairLatency measures with,
// so the two providers are answering the same question. The two halves of the
// repair are timed SEPARATELY, because they are different tiles and there is no
// reason they should land on the same frame:
//
//   the OLD spot projecting again    - the tiles the box left reopening.
//   the NEW spot no longer projecting - the tiles the box entered closing.
//
// WHY ONE UNIONED BOX AND NOT TWO. The drain accumulates dirty ground into a
// single AABB (FProcessor_GroundNavVolume_HandleRepairRequests unions into
// _PendingDirtyBounds), so a drop and a paint landing in one frame cost ONE
// repair over the union of both records rather than two repairs over two boxes.
// That is the design - "for a body that MOVED the box is the union of where it
// was and where it is" - and it is what the expected tile set below is computed
// against. On this fixture the two readings coincide anyway: the union AABB
// selects tiles 1..6, and so does the union of the two spots' own selections.
//
// WHAT MAKES THE ASSERTION NON-VACUOUS. The lattice is 8 columns wide and a move
// between columns 2 and 5 reaches columns 1..6 once halo-inflated. Columns 0 and
// 7 - six tiles of twenty-four - are ground no move of this box can name, and a
// changed-bounds box that reaches them is a publish that re-baked the whole
// volume. Without the two spare columns the union would span the lattice and
// there would be nothing left over to assert about.
//
// WHY THE X AXIS CARRIES THE PIN AND Y DOES NOT. The volume is three tiles deep
// and the halo is 200uu, so a box on the middle row inflates into all three rows
// whatever else it does. A Y assertion would be restating the lattice rather
// than measuring the repair, so the containment below is on X, and Y is asserted
// only to the extent that a foreign publish is filtered out.
//
// WHY THE BAKE IS SLICED TO ONE TILE A TICK. At the default probe budget the
// repaired tiles land inside one frame and the two halves of a move are never
// separable. A budget of one probe admits exactly one tile per tick, so an
// eighteen-tile repair spans eighteen slices and the frames below are real.
//
// The frame counts are LOGGED and never asserted against a number - how many
// passes a sliced repair needs is a property of the probe budget and processor
// ordering. What is asserted is that both halves landed at all inside a generous
// named cap, that every publish stayed inside the expected columns, and that the
// surface revision moved on every move.
//
// FIXTURE. One Static JoltBody slab whose top sits at Z 0, overhanging the
// GroundNav volume by 200uu on every horizontal side so no cliff edge exists
// inside the field, auto-build disabled so the bake waited on is the one asked
// for. A box shape is convex and therefore closed - an open mesh would trip the
// bake's OPEN COLLISION warning, and the harness escalates a Warning into a
// failure.
//
// The provider is per world and every other fixture in this map reads it, so the
// previous selection is captured before the swap and handed back both when this
// test concludes AND in DoEndPlay. The rebuilt signal is a WORLD signal rather
// than an entity one, so the same teardown unbinds it.
//
// Isolated Y band: 138000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Repair_MovedMarkupBoxChangesOnlyWhereItMoved : UCk_AutoTest_Base
{
    // Twenty-four tiles of build plus one paint and three eighteen-tile repairs, every one of them
    // sliced to a tile a tick. Deliberately slack: a contract that expires on the harness's
    // anonymous TimesUp names nothing.
    default _TimeoutSeconds = 240.0f;

    //------------------------------------------------------------------------
    // Fixture geometry - an 8x3 lattice at 400uu tiles
    //------------------------------------------------------------------------

    private const float BandY = 138000.0;

    // 3200 x 1200 uu of volume at 400uu tiles is exactly an 8 x 3 lattice. The width is what buys
    // the two spare columns the locality assertion is made of - see the header.
    private const float VolumeHalfX = 1600.0;
    private const float VolumeHalfY = 600.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float SlabHalfX = 1800.0;
    private const float SlabHalfY = 800.0;
    private const float SlabHalfZ = 50.0;

    private const float SurfaceZ = 0.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 400.0;
    private const int32 TileColumns = 8;
    private const int32 TileRows = 3;
    private const int32 TileCountTotal = 24;

    private const int32 ProbeBudgetPerTick = 1;

    private const float AgentRadius = 42.0;
    private const float ProfileHalfHeightUu = 96.0;

    // Mirrored from FCk_Fragment_GroundNavVolume_ParamsData::_MaxClearanceUu's default and
    // DELIBERATELY NOT SET on the params below: the halo is the property under test.
    private const float MaxClearanceUu = 200.0;

    // ceil(MaxClearanceUu / cellSize) = ceil(200 / 25) = 8 cells = 200uu, which is what
    // Get_RepairTileIndices inflates the dirty box by in XY.
    private const float HaloUu = 200.0;

    private const float BoxHalfXY = 150.0;
    private const float BoxHalfZ = 200.0;

    // Spot A sits on the centre of tile column 2, spot B on the centre of column 5. Column c spans
    // [-1600 + 400c, -1600 + 400(c+1)], so their centres are -600 and +600: 1200uu apart, which is
    // wide enough that the two halos never touch and each spot's own repair is separable.
    private const int32 SpotColumnA = 2;
    private const int32 SpotColumnB = 5;
    private const float MoveDistanceUu = 1200.0;

    // Both spots sit on the middle row, so the move is along X alone.
    private const int32 SpotRow = 1;

    // Tighter than the hole a 300uu box leaves, so a probe inside the carve has nothing beside it to
    // snap to. The same numbers the Recast baseline probes with.
    private const FVector ProbeHalfExtents = FVector(60.0, 60.0, 80.0);

    private const int32 MoveCount = 3;

    // Per-move ceiling, and a CEILING only - it is what turns a wedged repair into a reported miss
    // instead of a hung test. The same 400 the Recast baseline caps a move at, so a miss here and a
    // miss there mean the same thing.
    private const int32 MoveFrameCap = 400;

    // What Recast measured for the same move, from the baseline fixture. LOGGED beside this
    // fixture's own numbers and never asserted against.
    private const int32 RecastMeasuredOldFrames = 2;
    private const int32 RecastMeasuredNewFrames = 2;

    private const float BoundsToleranceUu = 1.0;

    private const int32 Stage_Move = 0;
    private const int32 Stage_Await = 1;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 ProjectFrameBudget = 3600;
    private const int32 LiveFrameBudget = 3600;
    private const int32 MovesFrameBudget = 9000;

    // A repair's publish is delivered in the ECS signal-fire phase, which lands AFTER the step the
    // liveness wait resolves into - so the broadcast count is read one phase before the broadcast
    // arrives unless the sequence waits for it by name. A ceiling on that one phase gap and on
    // nothing else: the first paint's repair has already landed by the time it is reached. Every
    // MOVE already waits across the same delivery inside its own stage window and needs no step.
    private const int32 RebuiltFrameBudget = 120;

    //------------------------------------------------------------------------
    // Fixture handles
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _VolumeEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_NavSurfaceMarkup _Markup;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;
    private bool _RebuiltBound = false;

    //------------------------------------------------------------------------
    // Episode bookkeeping
    //------------------------------------------------------------------------

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    private FVector _FromCentre = FVector::ZeroVector;
    private FVector _ToCentre = FVector::ZeroVector;

    private int32 _Move = 0;
    private int32 _Stage = 0;
    private int64 _LastSampledFrame = -1;
    private int64 _StageStartFrame = 0;
    private int32 _StagePolls = 0;

    private int64 _RevisionBefore = -1;
    private int64 _RevisionAtStart = -1;

    private bool _OldSeen = false;
    private bool _NewSeen = false;
    private int32 _OldFrames = 0;
    private int32 _NewFrames = 0;

    private TArray<int32> _OldSamples;
    private TArray<int32> _NewSamples;

    private int32 _BothCount = 0;
    private int32 _RevisionRoseCount = 0;
    private int32 _WithinUnionCount = 0;
    private int32 _MovesWithABroadcast = 0;

    private bool _FirstPaintCarveSeen = false;
    private int32 _FirstPaintFrames = -1;

    // The stage's own observation window. The expected column range is set when a stage opens,
    // because the FIRST paint is one box and every move after it is the union of two.
    private bool _ObservingRepair = false;
    private float _ExpectedMinX = 0.0;
    private float _ExpectedMaxX = 0.0;
    private int32 _ExpectedColumnMin = 0;
    private int32 _ExpectedColumnMax = 0;

    private int32 _RebuiltThisStage = 0;
    private int32 _ForeignBoundsIgnored = 0;
    private bool _AnyChangedBoundsUnknown = false;
    private bool _AnyChangedBoundsOutsideExpected = false;

    private bool _WidestSeen = false;
    private FVector _WidestMin = FVector::ZeroVector;
    private FVector _WidestMax = FVector::ZeroVector;

    private int32 _StagesWithUnknownBounds = 0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage the floor and the volume",                     n"Step_BuildFixture");
        Add_Step_WaitUntil("the floor reaches the Jolt static world",            n"Check_FloorBodyAdded",          BodyFrameBudget);
        Add_Step(          "ask the volume to bake",                             n"Step_RequestBake");
        Add_Step_WaitUntil("the field reports itself built",                     n"Check_FieldBuilt",              BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",            n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles at Ready",                   n"Check_SurfaceSettled",          SurfaceFrameBudget);
        Add_Step_WaitUntil("both spots project on bare floor",                   n"Check_BothSpotsProject",        ProjectFrameBudget);
        Add_Step(          "paint the impassable box on spot A",                 n"Step_FirstPaint");
        Add_Step_WaitUntil("the first paint is live on the surface",             n"Check_FirstPaintIsLive",        LiveFrameBudget);
        Add_Step_WaitUntil("the rebuilt signal delivered the publish",           n"Check_RebuiltSignalDelivered",  RebuiltFrameBudget);
        Add_Step(          "the first paint carved a hole, locally",             n"Step_AssertFirstPaint");
        Add_Step_WaitUntil("every move has been observed",                       n"Check_MovesComplete",           MovesFrameBudget);
        Add_Step(          "report what a move cost the field",                  n"Step_Report");
        Add_Step(          "drop the last box",                                  n"Step_DropFinalBox");
        Add_Step_WaitUntil("both spots project again once the box is dropped",   n"Check_BothSpotsProject",        ProjectFrameBudget);
        Add_Step(          "judge the run",                                      n"Step_Judge");
        Add_Step(          "hand the world back",                                n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Staging
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_BuildFixture(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _FloorEntity.Request_OverrideToSelf();

        utils_transform::Add(_FloorEntity,
            FTransform(FRotator::ZeroRotator, FVector(0.0, BandY, SurfaceZ - SlabHalfZ)),
            ECk_Replication::DoesNotReplicate);

        auto SlabShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        SlabShape.Set_HalfExtents(FVector(SlabHalfX, SlabHalfY, SlabHalfZ));

        auto SlabParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        SlabParams.Set_ShapeDimensions(SlabShape);
        SlabParams.Set_MotionType(ECk_MotionType::Static);

        _FloorBody = utils_jolt_body::Add(_FloorEntity, SlabParams);

        Assert_True(ck::IsValid(_FloorBody), "the slab's Jolt body must be valid");

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(float32(CellSizeUu), float32(CellHeightUu));
        Config.Set_TileSizeUu(float32(TileSizeUu));

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(float32(ProfileHalfHeightUu), float32(AgentRadius))));
        // The slab's own edges lie OUTSIDE the volume, but the field is clipped to the volume, so the
        // ledge filter would otherwise demote the whole perimeter.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(-VolumeHalfX, BandY - VolumeHalfY, VolumeFloorZ),
            FVector( VolumeHalfX, BandY + VolumeHalfY, VolumeCeilingZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        VolumeParams.Set_ProbeBudgetPerTick(ProbeBudgetPerTick);
        // _MaxClearanceUu is left at its default on purpose - see the constant above.

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid GroundNav volume handle");

        // Bound before anything can publish, so what is counted is a count of broadcasts this fixture
        // saw arrive rather than of broadcasts it happened to be listening for. The signal is a WORLD
        // signal, so Teardown unbinds it.
        utils_nav_surface::BindTo_OnSurfaceRebuilt(
            FCk_Delegate_NavSurface_OnSurfaceRebuilt(this, n"OnSurfaceRebuilt"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        _RebuiltBound = true;
    }

    UFUNCTION()
    private void Check_FloorBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_jolt_body::Get_IsBodyAdded(_FloorBody));
    }

    UFUNCTION()
    private void Step_RequestBake(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
    }

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _BuildCompletions += 1;
        _LastBuildResult = InResult;
    }

    UFUNCTION()
    private void Check_FieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BuildCompletions >= 1 && utils_ground_nav_volume::Get_IsBuilt(_Volume));
    }

    UFUNCTION()
    private void Step_SelectProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastBuildResult == ECk_Request_OperationResult::Succeeded,
            f"a bake that finished must complete with Succeeded (got {_LastBuildResult})");

        const auto TileCount = utils_ground_nav_volume::Get_TileCount(_Volume);

        // Asserted rather than commented: every expected column index below is arithmetic over this
        // lattice, and a volume that tiled differently would make all of it quietly wrong.
        Assert_Equals_Int(TileCount, TileCountTotal,
            f"a {VolumeHalfX * 2.0}uu by {VolumeHalfY * 2.0}uu volume at {TileSizeUu}uu tiles must be a {TileColumns}x{TileRows} lattice, which is what every expected column in this fixture is computed against (got {TileCount} tiles)");

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
        _ProviderSwapped = true;

        _RevisionAtStart = utils_nav_surface::Get_SurfaceRevision();

        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::GroundNav,
            f"the world must report the provider it was told to answer on (got {ProviderNow})");
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Check_BothSpotsProject(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Get_SpotProjects(Get_SpotCentre(0)) && Get_SpotProjects(Get_SpotCentre(1)));
    }

    //------------------------------------------------------------------------
    // The first paint - one box, and the tighter of the two expected sets
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_FirstPaint(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ToCentre = Get_SpotCentre(0);

        Do_OpenStage(Get_ExpectedColumnMinFor(_ToCentre.X), Get_ExpectedColumnMaxFor(_ToCentre.X));

        Do_PaintMarkup(_ToCentre);

        Assert_True(ck::IsValid(_Markup),
            "Request_ImpassableBox hands back the handle the caller needs to observe and release the paint - an invalid one leaves nothing for this test to move");
    }

    UFUNCTION()
    private void Check_FirstPaintIsLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto IsLive = utils_nav_surface::Get_IsMarkupLive(_Markup);

        // Taken at the FIRST poll that answers true and never overwritten. The stage's observation
        // window is deliberately left OPEN here: the publish it is measuring is delivered in the
        // signal-fire phase that lands after the step this wait resolves into, and a window closed
        // here would drop it. It closes where the counters are reset - the first move's own stage.
        if (IsLive && _FirstPaintFrames < 0)
        { _FirstPaintFrames = int32(utils_time::Get_FrameCounter() - _StageStartFrame); }

        auto Res = OutResult;
        Res.Set(IsLive);
    }

    // A CONDITION rather than a settle: the first paint's repair has already published by the time
    // this is reached, but the signal carrying it fires in the ECS signal-fire phase, which lands
    // after the step the liveness wait resolved into. Without it the locality assertion below reads
    // zero broadcasts over a publish that did happen. How many phases the delivery takes is asserted
    // nowhere - only that it happened at all.
    UFUNCTION()
    private void Check_RebuiltSignalDelivered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RebuiltThisStage >= 1);
    }

    UFUNCTION()
    private void Step_AssertFirstPaint(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FirstPaintCarveSeen = Get_SpotProjects(_ToCentre) == false;

        const auto Frames = _FirstPaintFrames;
        const auto Broadcasts = _RebuiltThisStage;
        const auto Carved = _FirstPaintCarveSeen;

        ck::nav::Display(f"[GROUNDNAV-REPAIR] first paint: framesToLive={Frames} carved={Carved} rebuiltBroadcasts={Broadcasts}");

        Do_ReportStageBounds("first paint");

        // The whole run rests on this: nothing that follows is a MOVE of an obstacle unless the
        // first paint was an obstacle to begin with.
        Assert_True(_FirstPaintCarveSeen,
            "the first impassable box never carved a hole in the field, so nothing this test moves was ever an obstacle to the provider and every measurement below would be timing an empty repair");

        Do_AssertStageWasLocal("the first paint");
    }

    //------------------------------------------------------------------------
    // The move driver
    //------------------------------------------------------------------------
    //
    // One stage per frame, gated on the frame counter so a second poll inside one frame can never
    // double-count a repair into the numbers this test produces. A move whose two repairs do not
    // both land inside MoveFrameCap is recorded with whichever half did land and the run moves on -
    // the judgement is made once at the end, where it can say which half never came back rather
    // than dying as an anonymous timeout with the carve still in the shared world.

    UFUNCTION()
    private void Check_MovesComplete(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (_Move >= MoveCount)
        {
            Res.Set(true);
            return;
        }

        const auto Frame = utils_time::Get_FrameCounter();

        if (Frame <= _LastSampledFrame)
        {
            Res.Set(false);
            return;
        }

        _LastSampledFrame = Frame;

        if (_Stage == Stage_Move) { Do_Move(); }
        else                      { Do_AwaitRepair(); }

        Res.Set(_Move >= MoveCount);
    }

    // The drop and the repaint land in the same frame on purpose: what is being measured is one
    // obstacle arriving somewhere new, not an unpaint followed later by an unrelated paint.
    private void Do_Move()
    {
        if (!ck::IsValid(_Markup))
        {
            FinishFailure("the markup box went away mid-run, so there is nothing left to move - the fixture, not the provider, is broken");
            return;
        }

        _FromCentre = _ToCentre;
        _ToCentre = Get_SpotCentre(_Move + 1);

        // The union of where it WAS and where it IS, halo-inflated - the same box the drain
        // accumulates and the same tile set Get_RepairTileIndices will select from it.
        const auto ColumnMin = Math::Min(
            Get_ExpectedColumnMinFor(_FromCentre.X), Get_ExpectedColumnMinFor(_ToCentre.X));
        const auto ColumnMax = Math::Max(
            Get_ExpectedColumnMaxFor(_FromCentre.X), Get_ExpectedColumnMaxFor(_ToCentre.X));

        Do_OpenStage(ColumnMin, ColumnMax);

        _OldSeen = false;
        _NewSeen = false;
        _OldFrames = 0;
        _NewFrames = 0;
        _StagePolls = 0;

        Do_DropMarkup();
        Do_PaintMarkup(_ToCentre);

        _Stage = Stage_Await;
    }

    private void Do_AwaitRepair()
    {
        _StagePolls += 1;

        const auto Frames = int32(utils_time::Get_FrameCounter() - _StageStartFrame);

        if (_OldSeen == false && Get_SpotProjects(_FromCentre))
        {
            _OldSeen = true;
            _OldFrames = Frames;
        }

        if (_NewSeen == false && Get_SpotProjects(_ToCentre) == false)
        {
            _NewSeen = true;
            _NewFrames = Frames;
        }

        const auto BothSeen = _OldSeen && _NewSeen;

        if (BothSeen == false && _StagePolls < MoveFrameCap)
        { return; }

        Do_RecordMove(BothSeen);
    }

    private void Do_RecordMove(bool InBothSeen)
    {
        Do_CloseStage();

        const auto Ordinal = _Move + 1;
        const auto Broadcasts = _RebuiltThisStage;
        const auto WithinUnion = _AnyChangedBoundsOutsideExpected == false
            && _AnyChangedBoundsUnknown == false;
        const auto RevisionAfter = utils_nav_surface::Get_SurfaceRevision();
        const auto RevisionBefore = _RevisionBefore;
        const auto Cap = MoveFrameCap;
        const auto Moves = MoveCount;
        const auto OldFrames = _OldFrames;
        const auto NewFrames = _NewFrames;

        const auto OldVerdict = _OldSeen
            ? f"frames={OldFrames}"
            : f"NOT OBSERVED within {Cap} frames";

        const auto NewVerdict = _NewSeen
            ? f"frames={NewFrames}"
            : f"NOT OBSERVED within {Cap} frames";

        ck::nav::Display(f"[GROUNDNAV-REPAIR] move {Ordinal} of {Moves}: oldSpotProjectsAgain {OldVerdict} newSpotStopsProjecting {NewVerdict} rebuiltBroadcasts={Broadcasts} changedBoundsWithinUnion={WithinUnion}");

        Do_ReportStageBounds(f"move {Ordinal}");

        if (_OldSeen) { _OldSamples.Add(_OldFrames); }
        if (_NewSeen) { _NewSamples.Add(_NewFrames); }

        if (InBothSeen)      { _BothCount += 1; }
        if (WithinUnion)     { _WithinUnionCount += 1; }
        if (Broadcasts >= 1) { _MovesWithABroadcast += 1; }

        if (RevisionAfter > RevisionBefore) { _RevisionRoseCount += 1; }

        if (_AnyChangedBoundsUnknown) { _StagesWithUnknownBounds += 1; }

        _Move += 1;
        _Stage = Stage_Move;
    }

    //------------------------------------------------------------------------
    // Stage bookkeeping
    //------------------------------------------------------------------------

    private void Do_OpenStage(int32 InColumnMin, int32 InColumnMax)
    {
        _StageStartFrame = utils_time::Get_FrameCounter();
        _RevisionBefore = utils_nav_surface::Get_SurfaceRevision();

        _ExpectedColumnMin = InColumnMin;
        _ExpectedColumnMax = InColumnMax;
        _ExpectedMinX = Get_ColumnEdgeX(InColumnMin);
        _ExpectedMaxX = Get_ColumnEdgeX(InColumnMax + 1);

        _RebuiltThisStage = 0;
        _ForeignBoundsIgnored = 0;
        _AnyChangedBoundsUnknown = false;
        _AnyChangedBoundsOutsideExpected = false;

        _WidestSeen = false;

        _ObservingRepair = true;
    }

    private void Do_CloseStage()
    {
        _ObservingRepair = false;
    }

    UFUNCTION()
    private void OnSurfaceRebuilt(FCk_Handle InWorldEntity, FBox InChangedBounds)
    {
        if (IsFinished()) { return; }
        if (_ObservingRepair == false) { return; }

        // A publisher that did not know WHERE it rebuilt sends an invalid box, and every consumer
        // reads that as reaching everything. Recorded rather than skipped: it is the one payload
        // under which a containment assertion would mean nothing at all.
        if (!InChangedBounds.IsValid)
        {
            _RebuiltThisStage += 1;
            _AnyChangedBoundsUnknown = true;
            return;
        }

        // A foreign volume that outlived its own fixture publishes ground in another Y band. It is
        // not this test's to measure and it is not this test's to fail on.
        if (!Get_MeetsThisVolume(InChangedBounds))
        {
            _ForeignBoundsIgnored += 1;
            return;
        }

        _RebuiltThisStage += 1;

        if (InChangedBounds.Min.X < _ExpectedMinX - BoundsToleranceUu
         || InChangedBounds.Max.X > _ExpectedMaxX + BoundsToleranceUu)
        { _AnyChangedBoundsOutsideExpected = true; }

        Do_WidenSeenBounds(InChangedBounds);
    }

    private void Do_WidenSeenBounds(FBox InBounds)
    {
        if (_WidestSeen == false)
        {
            _WidestSeen = true;
            _WidestMin = InBounds.Min;
            _WidestMax = InBounds.Max;

            return;
        }

        _WidestMin = FVector(
            Math::Min(_WidestMin.X, InBounds.Min.X),
            Math::Min(_WidestMin.Y, InBounds.Min.Y),
            Math::Min(_WidestMin.Z, InBounds.Min.Z));

        _WidestMax = FVector(
            Math::Max(_WidestMax.X, InBounds.Max.X),
            Math::Max(_WidestMax.Y, InBounds.Max.Y),
            Math::Max(_WidestMax.Z, InBounds.Max.Z));
    }

    private void Do_ReportStageBounds(FString InLabel)
    {
        const auto ColumnMin = _ExpectedColumnMin;
        const auto ColumnMax = _ExpectedColumnMax;
        const auto ExpectedMinX = _ExpectedMinX;
        const auto ExpectedMaxX = _ExpectedMaxX;
        const auto WidestMin = _WidestMin;
        const auto WidestMax = _WidestMax;
        const auto Ignored = _ForeignBoundsIgnored;

        ck::nav::Display(f"[GROUNDNAV-REPAIR] {InLabel} bounds: expectedColumns={ColumnMin}..{ColumnMax} expectedX={ExpectedMinX}..{ExpectedMaxX} changedBounds={WidestMin}..{WidestMax} foreignBoundsIgnored={Ignored}");
    }

    private void Do_AssertStageWasLocal(FString InLabel)
    {
        const auto Broadcasts = _RebuiltThisStage;
        const auto ColumnMin = _ExpectedColumnMin;
        const auto ColumnMax = _ExpectedColumnMax;
        const auto ExpectedMinX = _ExpectedMinX;
        const auto ExpectedMaxX = _ExpectedMaxX;
        const auto WidestMin = _WidestMin;
        const auto WidestMax = _WidestMax;

        // The POSITIVE the containment rests on: with no broadcast at all there is nothing to have
        // been local, and the assertion below would pass over silence.
        Assert_True(Broadcasts >= 1,
            f"{InLabel}: the neutral OnSurfaceRebuilt signal must have delivered the publish this fixture is measuring (got {Broadcasts} broadcasts meeting this volume)");

        Assert_False(_AnyChangedBoundsUnknown,
            f"{InLabel}: a publish carried an INVALID changed-bounds box, which every consumer reads as reaching every corridor in the world. A repair knows exactly which tiles it re-baked, so bounds-unknown here means the publish lost that knowledge.");

        Assert_False(_AnyChangedBoundsOutsideExpected,
            f"{InLabel}: a changed-bounds box reached ground outside tile columns {ColumnMin}..{ColumnMax}, which is X {ExpectedMinX} to {ExpectedMaxX} - the columns the halo-inflated dirty box can select. The widest box seen was {WidestMin} to {WidestMax}. Reaching past it names columns this box never occupied and never crossed, which is what a WHOLE-VOLUME rebuild publishes.");
    }

    //------------------------------------------------------------------------
    // Reporting and the verdict
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Moves = MoveCount;
        const auto OldMin = Get_Min(_OldSamples);
        const auto OldMax = Get_Max(_OldSamples);
        const auto OldMean = Get_Mean(_OldSamples);
        const auto NewMin = Get_Min(_NewSamples);
        const auto NewMax = Get_Max(_NewSamples);
        const auto NewMean = Get_Mean(_NewSamples);
        const auto RecastOld = RecastMeasuredOldFrames;
        const auto RecastNew = RecastMeasuredNewFrames;

        ck::nav::Display(f"[GROUNDNAV-REPAIR] moved box over {Moves} moves: old frames min={OldMin} max={OldMax} mean={OldMean :.2} | new frames min={NewMin} max={NewMax} mean={NewMean :.2} (Recast measured {RecastOld} + {RecastNew})");
    }

    UFUNCTION()
    private void Step_DropFinalBox(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_DropMarkup();
    }

    // After the teardown wait on purpose: a verdict that fires before it strands the carve in the
    // shared world fails the next fixture for a reason it did not cause. Before Step_Cleanup, so the
    // volume is still published and the projections above answered against a real field.
    UFUNCTION()
    private void Step_Judge(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Moves = MoveCount;
        const auto Both = _BothCount;
        const auto Within = _WithinUnionCount;
        const auto Rose = _RevisionRoseCount;
        const auto WithBroadcast = _MovesWithABroadcast;
        const auto Cap = MoveFrameCap;
        const auto UnknownBoundsMoves = _StagesWithUnknownBounds;

        // Derived from the same selection arithmetic the assertions use rather than from a formula
        // of its own, so a fixture edit that widened the lattice or moved a spot cannot leave this
        // number claiming spare ground the move now reaches.
        const auto TouchedColumnMin = Math::Min(
            Get_ExpectedColumnMinFor(Get_SpotCentre(0).X), Get_ExpectedColumnMinFor(Get_SpotCentre(1).X));
        const auto TouchedColumnMax = Math::Max(
            Get_ExpectedColumnMaxFor(Get_SpotCentre(0).X), Get_ExpectedColumnMaxFor(Get_SpotCentre(1).X));
        const auto UntouchedColumns = TileColumns - (TouchedColumnMax - TouchedColumnMin + 1);

        // The fixture's whole reason for being eight columns wide: with no spare column the
        // containment below would span the lattice and assert nothing.
        Assert_True(UntouchedColumns >= 1,
            f"the lattice must leave at least one full tile column outside the columns a move can select ({TouchedColumnMin}..{TouchedColumnMax} of {TileColumns}), or the containment assertion below covers the whole volume and holds however un-local the publish was");

        // Positives first, so a run that measured nothing fails by naming what it never saw rather
        // than by a containment that held over silence.
        Assert_Equals_Int(WithBroadcast, MoveCount,
            f"every move must have published at least one changed-bounds box this volume owns (got {WithBroadcast} of {Moves}); a move that published nothing leaves the containment below asserting over silence");

        Assert_Equals_Int(UnknownBoundsMoves, 0,
            f"{UnknownBoundsMoves} move(s) carried an INVALID changed-bounds box, which every consumer reads as reaching everything");

        Assert_Equals_Int(Both, MoveCount,
            f"every move must have had BOTH halves of its repair land inside the {Cap}-frame cap - the old spot reopening and the new spot closing (got {Both} of {Moves}). A half that never lands is a repair that left the ground it was told about wrong.");

        Assert_Equals_Int(Rose, MoveCount,
            f"a move re-bakes the tiles the box left and the tiles it entered, so the surface revision must advance on every one of them (got {Rose} of {Moves})");

        // The pin.
        Assert_Equals_Int(Within, MoveCount,
            f"every move's changed-bounds boxes must lie inside the columns the union of the old and new halo-inflated boxes selects (got {Within} of {Moves}). {UntouchedColumns} full tile column(s) of this lattice are ground the box never occupied and never crossed, and a publish that named them re-baked the whole volume instead of repairing the two ends of a move.");

        Assert_True(_FirstPaintCarveSeen,
            "the first impassable box never carved the field, so nothing this test moved was ever an obstacle");
    }

    //------------------------------------------------------------------------
    // Markup
    //------------------------------------------------------------------------

    // Request_ImpassableBox ignores the area tag on the request and paints the well-known impassable
    // area, so the tag handed in here is deliberately empty.
    private void Do_PaintMarkup(FVector InCentre)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(BoxHalfXY, BoxHalfXY, BoxHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(FTransform(FRotator::ZeroRotator, InCentre, FVector::OneVector));

        _Markup = utils_nav_surface::Request_ImpassableBox(Request);

        // The markup entity is parented to the WORLD, not to this runner, so the subtree teardown the
        // harness runs never reaches it - registering it here is what unpaints the carve on every
        // exit path, including the boxes this test drops itself.
        Track_ForCleanup(FCk_Handle(_Markup));
    }

    private void Do_DropMarkup()
    {
        if (ck::IsValid(_Markup))
        { utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup)); }

        _Markup = FCk_Handle_NavSurfaceMarkup();
    }

    //------------------------------------------------------------------------
    // Fixture geometry - every expected column is arithmetic over the lattice,
    // computed here rather than read back out of the system under test.
    //------------------------------------------------------------------------

    // The two spots the box ping-pongs between, on the centres of columns 2 and 5 of the middle row.
    private FVector Get_SpotCentre(int32 InIndex)
    {
        const auto Column = InIndex % 2 == 0 ? SpotColumnA : SpotColumnB;

        return FVector(
            Get_ColumnEdgeX(Column) + (TileSizeUu * 0.5),
            BandY - VolumeHalfY + (float(SpotRow) * TileSizeUu) + (TileSizeUu * 0.5),
            SurfaceZ);
    }

    private float Get_ColumnEdgeX(int32 InColumn)
    {
        return (float(InColumn) * TileSizeUu) - VolumeHalfX;
    }

    // WHY THESE ARE THE EXPECTED COLUMNS. Get_RepairTileIndices inflates the dirty box in XY by the
    // field's halo width and takes every tile it meets, so a 150uu half box centred on a column
    // reaches [centre - 350, centre + 350]. Columns run from the volume's own corner at -1600 in
    // 400uu steps, so spot A at X -600 selects floor((-950 + 1600) / 400) = 1 through
    // floor((-250 + 1600) / 400) = 3, and spot B at X +600 selects floor((250 + 1600) / 400) = 4
    // through floor((950 + 1600) / 400) = 6. A move unions the two into columns 1..6, leaving
    // columns 0 and 7 - six of the twenty-four tiles - as ground no move of this box can name.
    private int32 Get_ExpectedColumnMinFor(float InCentreX)
    {
        return Get_ColumnAt(InCentreX - BoxHalfXY - HaloUu);
    }

    private int32 Get_ExpectedColumnMaxFor(float InCentreX)
    {
        return Get_ColumnAt(InCentreX + BoxHalfXY + HaloUu);
    }

    // The distance from the volume's corner is non-negative by construction - every spot and its
    // halo lie wholly inside the volume - so truncating to int32 is a floor rather than a round
    // toward zero.
    private int32 Get_ColumnAt(float InWorldX)
    {
        const auto FromCornerUu = InWorldX + VolumeHalfX;

        return int32(FromCornerUu / TileSizeUu);
    }

    // Answered on components rather than through FBox::Intersect, so the filter needs no box
    // operator this fixture cannot point at a binding for. Touching faces count as meeting, which is
    // the inclusive reading the tile selection itself uses.
    private bool Get_MeetsThisVolume(FBox InBounds)
    {
        if (InBounds.Min.X > VolumeHalfX || InBounds.Max.X < -VolumeHalfX)
        { return false; }

        if (InBounds.Min.Y > BandY + VolumeHalfY || InBounds.Max.Y < BandY - VolumeHalfY)
        { return false; }

        return true;
    }

    // The probe the carve can actually move: search half-extents tighter than the hole, so a point
    // inside the carve has nothing beside it to snap to.
    private bool Get_SpotProjects(FVector InCentre)
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InCentre);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(ProbeHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query).Get_Status()
            == ECk_NavSurface_QueryStatus::Success;
    }

    //------------------------------------------------------------------------
    // Sample arithmetic
    //------------------------------------------------------------------------

    private int32 Get_Min(const TArray<int32>& InSamples)
    {
        if (InSamples.Num() == 0) { return -1; }

        auto Smallest = InSamples[0];

        for (int32 Index = 1; Index < InSamples.Num(); Index++)
        { Smallest = Math::Min(Smallest, InSamples[Index]); }

        return Smallest;
    }

    private int32 Get_Max(const TArray<int32>& InSamples)
    {
        if (InSamples.Num() == 0) { return -1; }

        auto Largest = InSamples[0];

        for (int32 Index = 1; Index < InSamples.Num(); Index++)
        { Largest = Math::Max(Largest, InSamples[Index]); }

        return Largest;
    }

    private float Get_Mean(const TArray<int32>& InSamples)
    {
        if (InSamples.Num() == 0) { return 0.0; }

        auto Sum = 0;

        for (int32 Index = 0; Index < InSamples.Num(); Index++)
        { Sum += InSamples[Index]; }

        return float32(Sum) / float32(InSamples.Num());
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. Two things here outlive this
    // test's own subtree: the provider is a WORLD selection every later fixture in this map reads,
    // and OnSurfaceRebuilt is a WORLD signal that would keep calling into a finished script.
    private void Teardown()
    {
        if (_RebuiltBound)
        {
            _RebuiltBound = false;
            utils_nav_surface::UnbindFrom_OnSurfaceRebuilt(
                FCk_Delegate_NavSurface_OnSurfaceRebuilt(this, n"OnSurfaceRebuilt"));
        }

        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_Markup))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup));
            _Markup = FCk_Handle_NavSurfaceMarkup();
        }

        if (ck::IsValid(_VolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
            _VolumeEntity = FCk_Handle();
        }

        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}
