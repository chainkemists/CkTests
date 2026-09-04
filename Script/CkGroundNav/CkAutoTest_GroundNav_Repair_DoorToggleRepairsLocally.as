// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A DOOR OPENING AND CLOSING REPAIRS LOCALLY
//============================================================================
//
// The local-repair contract for a walkability paint, stated as what a caller
// can actually observe. An impassable markup box is painted on the middle tile
// of a 5x5 field and released again, three times over. Each paint and each
// release raises a LOCAL REPAIR: only the tiles the halo-inflated record reaches
// are re-baked, every other tile is carried across with its epoch untouched,
// and the publish broadcasts OnSurfaceRebuilt carrying exactly the ground the
// repair touched.
//
// Two things are asserted and they are the whole contract:
//
//   1. THE DOOR IS REAL. A tight-extent projection at the door centre fails
//      while the box is painted and succeeds again once it is released. Without
//      this the locality assertion below would be a statement about a publish
//      that changed nothing.
//   2. THE PUBLISH IS LOCAL. Every changed-bounds box a door repair broadcasts
//      lies inside the union of the nine tiles the door's halo-inflated record
//      reaches - never the whole 5x5 volume, which is what a whole-volume
//      rebuild publishes.
//
// WHY LOCALITY IS THE ASSERTION AND THE FRAME COUNTS ARE NOT. How many passes a
// sliced repair needs is a property of the probe budget and of processor
// ordering; pinning it would make an ordering change read as a defect. The
// frames are logged beside the Recast measurement for the same obstacle so the
// two providers can be compared, and nothing is asserted against a number.
//
// WHY THE BAKE IS SLICED TO ONE TILE A TICK. At the default probe budget the
// nine repaired tiles land inside one frame and there is no window in which the
// door is painted but not yet live. A budget of one probe admits exactly one
// tile per tick, so a nine-tile repair spans nine slices and Get_IsMarkupLive is
// a condition rather than a formality.
//
// FOREIGN PUBLISHES ARE FILTERED, NOT COUNTED. OnSurfaceRebuilt is a WORLD
// signal: a volume belonging to another fixture that outlived its own teardown
// would deliver a box from another Y band and fail a containment assertion this
// test did not earn. Only boxes meeting this volume's own bounds are measured,
// and the number ignored is logged.
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
// test concludes AND in DoEndPlay - every exit path, including the engine
// TimeLimit one, must put the world back. The rebuilt signal is a WORLD signal
// rather than an entity one, so the same teardown unbinds it.
//
// Isolated Y band: 136000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Repair_DoorToggleRepairsLocally : UCk_AutoTest_Base
{
    // Twenty-five tiles of build plus six nine-tile repairs, every one of them sliced to a tile a
    // tick. Deliberately slack: a contract that expires on the harness's anonymous TimesUp names
    // nothing, and every wait below carries its own budget so it fails on its own condition.
    default _TimeoutSeconds = 240.0f;

    //------------------------------------------------------------------------
    // Fixture geometry - a 5x5 lattice at 400uu tiles
    //------------------------------------------------------------------------

    private const float BandY = 136000.0;

    // 2000 x 2000 uu of volume at 400uu tiles is exactly a 5 x 5 lattice.
    private const float VolumeHalfX = 1000.0;
    private const float VolumeHalfY = 1000.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    // Overhangs the volume by 200uu on every horizontal side, so the volume's interior never
    // contains a slab edge for the ledge filter to find.
    private const float SlabHalfX = 1200.0;
    private const float SlabHalfY = 1200.0;
    private const float SlabHalfZ = 50.0;

    private const float SurfaceZ = 0.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 400.0;
    private const int32 TileDivisions = 5;
    private const int32 TileCountTotal = 25;

    // The budget gates whether the NEXT tile starts and a tile is never split, so one probe buys
    // exactly one tile a tick.
    private const int32 ProbeBudgetPerTick = 1;

    private const float AgentRadius = 42.0;
    private const float ProfileHalfHeightUu = 96.0;

    // The clearance ceiling this fixture bakes at, mirrored from
    // FCk_Fragment_GroundNavVolume_ParamsData::_MaxClearanceUu's default. DELIBERATELY NOT SET on
    // the params below: the halo is the property under test, and a fixture that shrank it would be
    // asserting a locality the field never had to work for.
    private const float MaxClearanceUu = 200.0;

    // Halo width is ceil(MaxClearanceUu / cellSize) cells, and Get_RepairTileIndices inflates the
    // dirty box by exactly that many cells in XY. ceil(200 / 25) = 8 cells = 200uu.
    private const float HaloUu = 200.0;

    // The door: an impassable box on the interior of tile (2,2), the middle of the lattice.
    private const float DoorHalfXY = 150.0;
    private const float DoorHalfZ = 200.0;

    // Tighter than the hole a 300uu box leaves, so a probe inside the carve has nothing beside it to
    // snap to. The vertical half-extent stays well under the box height, so nothing baked above the
    // carve is ever mistaken for floor. The same numbers the Recast baseline probes with.
    private const FVector ProbeHalfExtents = FVector(60.0, 60.0, 80.0);

    private const int32 RoundCount = 3;

    // What the Recast provider measured for the same obstacle, from
    // CkAutoTest_NavSurface_RecastBudgets_MovedObstacleRepairLatency. LOGGED beside this fixture's
    // own numbers and never asserted against.
    private const int32 RecastMeasuredCloseFrames = 3;
    private const int32 RecastMeasuredOpenFrames = 2;

    // Tile edges are exact multiples of the tile span from the volume corner and the published box
    // is assembled from the same numbers, so this covers accumulation and nothing else.
    private const float BoundsToleranceUu = 1.0;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 LiveFrameBudget = 3600;
    private const int32 ProjectFrameBudget = 3600;

    // A repair's publish is delivered in the ECS signal-fire phase, which lands AFTER the step the
    // liveness or projection wait resolves into - so the broadcast count is read one phase before
    // the broadcast arrives unless the sequence waits for it by name. A ceiling on that one phase
    // gap and on nothing else: the repair itself has already landed by the time it is reached.
    private const int32 RebuiltFrameBudget = 120;

    //------------------------------------------------------------------------
    // Fixture handles
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _VolumeEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_NavSurfaceMarkup _Door;

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

    private int32 _Round = 0;

    // Stamped when a paint or a release lands, read when the condition it opened resolves.
    private int64 _StageStartFrame = 0;
    private int64 _RevisionBefore = -1;
    private int64 _RevisionAfter = -1;

    private int32 _FramesToLive = -1;
    private int32 _FramesToProjecting = -1;

    // What OnSurfaceRebuilt broadcast while a repair was open, measured against this volume only.
    // The window opens with the stage and stays open until the NEXT one opens: the publish a stage
    // is measuring arrives after the wait that stage resolves on, so a window closed on that wait
    // would drop the one broadcast the locality assertion reads.
    private bool _ObservingRepair = false;
    private int32 _RebuiltThisStage = 0;
    private int32 _ForeignBoundsIgnored = 0;
    private bool _AnyChangedBoundsUnknown = false;
    private bool _AnyChangedBoundsOutsideExpected = false;

    // The union of every changed box this stage saw, carried as two corners rather than an FBox so
    // the accumulation needs no box operator this fixture cannot see the binding for.
    private bool _WidestSeen = false;
    private FVector _WidestMin = FVector::ZeroVector;
    private FVector _WidestMax = FVector::ZeroVector;

    private TArray<int32> _CloseFrames;
    private TArray<int32> _OpenFrames;

    private int32 _CloseRepairsObserved = 0;
    private int32 _OpenRepairsObserved = 0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage the floor and the volume",                      n"Step_BuildFixture");
        Add_Step_WaitUntil("the floor reaches the Jolt static world",             n"Check_FloorBodyAdded",         BodyFrameBudget);
        Add_Step(          "ask the volume to bake",                              n"Step_RequestBake");
        Add_Step_WaitUntil("the field reports itself built",                      n"Check_FieldBuilt",             BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",             n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles at Ready",                    n"Check_SurfaceSettled",         SurfaceFrameBudget);
        Add_Step_WaitUntil("the door spot projects on bare floor",                n"Check_DoorSpotProjects",       ProjectFrameBudget);

        // Unrolled rather than driven off a counter so a wait that expires names the ROUND it was
        // on. Every round runs the same handlers; only the labels differ.
        Add_Step(          "round 1 - close the door",                            n"Step_CloseDoor");
        Add_Step_WaitUntil("round 1 - the door is live on the surface",           n"Check_DoorIsLive",             LiveFrameBudget);
        Add_Step_WaitUntil("round 1 - the rebuilt signal delivered the publish",  n"Check_RebuiltSignalDelivered", RebuiltFrameBudget);
        Add_Step(          "round 1 - the door carved a hole where it stands",    n"Step_AssertClosed");
        Add_Step(          "round 1 - open the door",                             n"Step_OpenDoor");
        Add_Step_WaitUntil("round 1 - the door spot projects again",              n"Check_DoorSpotProjects",       ProjectFrameBudget);
        Add_Step_WaitUntil("round 1 - the rebuilt signal delivered the publish",  n"Check_RebuiltSignalDelivered", RebuiltFrameBudget);
        Add_Step(          "round 1 - the release repaired locally too",          n"Step_AssertOpened");

        Add_Step(          "round 2 - close the door",                            n"Step_CloseDoor");
        Add_Step_WaitUntil("round 2 - the door is live on the surface",           n"Check_DoorIsLive",             LiveFrameBudget);
        Add_Step_WaitUntil("round 2 - the rebuilt signal delivered the publish",  n"Check_RebuiltSignalDelivered", RebuiltFrameBudget);
        Add_Step(          "round 2 - the door carved a hole where it stands",    n"Step_AssertClosed");
        Add_Step(          "round 2 - open the door",                             n"Step_OpenDoor");
        Add_Step_WaitUntil("round 2 - the door spot projects again",              n"Check_DoorSpotProjects",       ProjectFrameBudget);
        Add_Step_WaitUntil("round 2 - the rebuilt signal delivered the publish",  n"Check_RebuiltSignalDelivered", RebuiltFrameBudget);
        Add_Step(          "round 2 - the release repaired locally too",          n"Step_AssertOpened");

        Add_Step(          "round 3 - close the door",                            n"Step_CloseDoor");
        Add_Step_WaitUntil("round 3 - the door is live on the surface",           n"Check_DoorIsLive",             LiveFrameBudget);
        Add_Step_WaitUntil("round 3 - the rebuilt signal delivered the publish",  n"Check_RebuiltSignalDelivered", RebuiltFrameBudget);
        Add_Step(          "round 3 - the door carved a hole where it stands",    n"Step_AssertClosed");
        Add_Step(          "round 3 - open the door",                             n"Step_OpenDoor");
        Add_Step_WaitUntil("round 3 - the door spot projects again",              n"Check_DoorSpotProjects",       ProjectFrameBudget);
        Add_Step_WaitUntil("round 3 - the rebuilt signal delivered the publish",  n"Check_RebuiltSignalDelivered", RebuiltFrameBudget);
        Add_Step(          "round 3 - the release repaired locally too",          n"Step_AssertOpened");

        Add_Step(          "report what a door cost the field",                   n"Step_Report");
        Add_Step(          "no hole was left behind",                             n"Step_AssertNoHoleLeftBehind");
        Add_Step(          "hand the world back",                                 n"Step_Cleanup");

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

        // Bound before anything can publish, so what is counted after a paint is a count of
        // broadcasts this fixture saw arrive rather than of broadcasts it happened to be listening
        // for. The signal is a WORLD signal, so Teardown unbinds it.
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

        // Asserted rather than commented: every expected tile index below is arithmetic over this
        // lattice, and a volume that tiled differently would make all of it quietly wrong.
        Assert_Equals_Int(TileCount, TileCountTotal,
            f"a {VolumeHalfX * 2.0}uu volume at {TileSizeUu}uu tiles must be a {TileDivisions}x{TileDivisions} lattice, which is what every expected tile index in this fixture is computed against (got {TileCount} tiles)");

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
        _ProviderSwapped = true;

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

    //------------------------------------------------------------------------
    // The door
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_CloseDoor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_OpenStage();

        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(DoorHalfXY, DoorHalfXY, DoorHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_DoorCentre(), FVector::OneVector));

        _Door = utils_nav_surface::Request_ImpassableBox(Request);

        Assert_True(ck::IsValid(_Door),
            "Request_ImpassableBox hands back the handle the caller needs to observe and release the paint - an invalid one leaves the carve unreachable");

        // The markup entity is parented to the WORLD, not to this runner, so the harness's own
        // subtree teardown never reaches it - registering it here is what unpaints the carve on
        // every exit path, including the doors this test drops itself.
        Track_ForCleanup(FCk_Handle(_Door));
    }

    UFUNCTION()
    private void Check_DoorIsLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto IsLive = utils_nav_surface::Get_IsMarkupLive(_Door);

        // Taken at the FIRST poll that answers true and never overwritten: the trace is about the
        // state of the surface at the moment the wait let go, not at the moment it was read out.
        if (IsLive && _FramesToLive < 0)
        { Do_CloseStage(); }

        auto Res = OutResult;
        Res.Set(IsLive);
    }

    // Shared by both phases of every round, and a CONDITION rather than a settle: the repair has
    // already published by the time this is reached, but the signal carrying it fires in the ECS
    // signal-fire phase, which lands after the step the liveness or projection wait resolved into.
    // Without it the locality assertion below reads zero broadcasts over a publish that did happen.
    // How many phases the delivery takes is asserted nowhere - only that it happened at all.
    UFUNCTION()
    private void Check_RebuiltSignalDelivered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RebuiltThisStage >= 1);
    }

    UFUNCTION()
    private void Step_AssertClosed(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Ordinal = _Round + 1;
        const auto Frames = _FramesToLive;
        const auto Before = _RevisionBefore;
        const auto After = _RevisionAfter;
        const auto ProbeReachUu = ProbeHalfExtents.X;

        ck::nav::Display(f"[GROUNDNAV-REPAIR] door close: framesFromPaintToLive={Frames} revisionBefore={Before} revisionAfter={After}");

        Do_ReportStage(Ordinal, true);

        // The POSITIVE that makes the locality assertion worth making: a publish that changed
        // nothing could be local to anything at all.
        Assert_False(Get_DoorSpotProjects(),
            f"round {Ordinal}: the door is live on the surface, so a projection at its centre with {ProbeReachUu}uu search half-extents must find no ground. The paint carved no hole, and a repair that published tight bounds around ground it never changed pins nothing.");

        Assert_True(_RevisionAfter > _RevisionBefore,
            f"round {Ordinal}: a walkability paint must repair the tiles it reaches and republish, so the surface revision has to advance across it (was {Before}, now {After})");

        Do_AssertStageWasLocal(Ordinal, true);

        _CloseFrames.Add(_FramesToLive);
        _CloseRepairsObserved += 1;
    }

    UFUNCTION()
    private void Step_OpenDoor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_OpenStage();

        if (ck::IsValid(_Door))
        { utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Door)); }

        _Door = FCk_Handle_NavSurfaceMarkup();
    }

    // Shared by the bare-floor wait before round 1 and by every round's re-open: the predicate is
    // the same question in both places - does the field carry ground where the door stands.
    UFUNCTION()
    private void Check_DoorSpotProjects(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto Projects = Get_DoorSpotProjects();

        if (Projects && _ObservingRepair && _FramesToProjecting < 0)
        { Do_CloseStage(); }

        auto Res = OutResult;
        Res.Set(Projects);
    }

    UFUNCTION()
    private void Step_AssertOpened(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Ordinal = _Round + 1;
        const auto Frames = _FramesToProjecting;
        const auto Before = _RevisionBefore;
        const auto After = _RevisionAfter;

        ck::nav::Display(f"[GROUNDNAV-REPAIR] door open: framesFromDropToProjecting={Frames} revisionBefore={Before} revisionAfter={After}");

        Do_ReportStage(Ordinal, false);

        Assert_True(_RevisionAfter > _RevisionBefore,
            f"round {Ordinal}: releasing a walkability record owes the same repair that painting it did, so the surface revision has to advance across the release (was {Before}, now {After})");

        Do_AssertStageWasLocal(Ordinal, false);

        _OpenFrames.Add(_FramesToProjecting);
        _OpenRepairsObserved += 1;

        _Round += 1;
    }

    //------------------------------------------------------------------------
    // Stage bookkeeping - one paint or one release, from the request to the
    // condition it opened resolving.
    //------------------------------------------------------------------------

    private void Do_OpenStage()
    {
        _StageStartFrame = utils_time::Get_FrameCounter();
        _RevisionBefore = utils_nav_surface::Get_SurfaceRevision();
        _RevisionAfter = -1;

        _FramesToLive = -1;
        _FramesToProjecting = -1;

        _RebuiltThisStage = 0;
        _ForeignBoundsIgnored = 0;
        _AnyChangedBoundsUnknown = false;
        _AnyChangedBoundsOutsideExpected = false;

        _WidestSeen = false;

        _ObservingRepair = true;
    }

    private void Do_CloseStage()
    {
        const auto Frames = int32(utils_time::Get_FrameCounter() - _StageStartFrame);

        if (_FramesToLive < 0 && _FramesToProjecting < 0)
        {
            // Which of the two this stage was measuring is decided by the door: a stage opened by a
            // paint resolves on liveness, one opened by a release resolves on the spot projecting.
            if (ck::IsValid(_Door)) { _FramesToLive = Frames; }
            else                    { _FramesToProjecting = Frames; }
        }

        _RevisionAfter = utils_nav_surface::Get_SurfaceRevision();

        // The observation window is deliberately NOT closed here. This runs from a wait predicate,
        // and the publish this stage is measuring is delivered in the signal-fire phase that lands
        // after the step the wait resolves into - closing here would drop the very broadcast the
        // locality assertion reads. The window closes where the counters are reset: the next stage.
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

        if (!Get_IsWithinExpectedRepairBounds(InChangedBounds))
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

    private void Do_ReportStage(int32 InOrdinal, bool InIsClose)
    {
        const auto Broadcasts = _RebuiltThisStage;
        const auto Ignored = _ForeignBoundsIgnored;
        const auto WidestMin = _WidestMin;
        const auto WidestMax = _WidestMax;

        if (InIsClose)
        {
            ck::nav::Display(f"[GROUNDNAV-REPAIR] round {InOrdinal} close: rebuiltBroadcasts={Broadcasts} changedBounds={WidestMin}..{WidestMax} foreignBoundsIgnored={Ignored}");
            return;
        }

        ck::nav::Display(f"[GROUNDNAV-REPAIR] round {InOrdinal} open: rebuiltBroadcasts={Broadcasts} changedBounds={WidestMin}..{WidestMax} foreignBoundsIgnored={Ignored}");
    }

    private void Do_AssertStageWasLocal(int32 InOrdinal, bool InIsClose)
    {
        const auto Broadcasts = _RebuiltThisStage;
        const auto WidestMin = _WidestMin;
        const auto WidestMax = _WidestMax;
        const auto ExpectedMin = Get_ExpectedRepairMin();
        const auto ExpectedMax = Get_ExpectedRepairMax();
        const auto IndexMin = Get_ExpectedTileIndexMin();
        const auto IndexMax = Get_ExpectedTileIndexMax();
        const auto ExpectedTiles = Get_ExpectedTileCount();
        const auto RimTiles = TileCountTotal - Get_ExpectedTileCount();

        // The POSITIVE the containment rests on: with no broadcast at all there is nothing to have
        // been local, and both assertions below would pass over silence.
        Assert_True(Broadcasts >= 1,
            f"round {InOrdinal}: the neutral OnSurfaceRebuilt signal must have delivered the publish this fixture is measuring (got {Broadcasts} broadcasts meeting this volume, isClose={InIsClose})");

        Assert_False(_AnyChangedBoundsUnknown,
            f"round {InOrdinal}: a publish carried an INVALID changed-bounds box, which every consumer reads as reaching every corridor in the world. A repair knows exactly which tiles it re-baked, so bounds-unknown here means the publish lost that knowledge and the containment below could not have decided anything. (isClose={InIsClose})");

        Assert_False(_AnyChangedBoundsOutsideExpected,
            f"round {InOrdinal}: a changed-bounds box reached ground outside the {ExpectedTiles} tiles the door's halo-inflated record can select - tile indices {IndexMin}..{IndexMax} on both axes, which is XY {ExpectedMin} to {ExpectedMax}. The widest box seen was {WidestMin} to {WidestMax}. Reaching past it means the publish named the {RimTiles} rim tiles this door never touched, which is exactly what a WHOLE-VOLUME rebuild publishes and what the local repair exists to stop. (isClose={InIsClose})");
    }

    //------------------------------------------------------------------------
    // Reporting and the final state of the world
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Rounds = RoundCount;
        const auto CloseMin = Get_Min(_CloseFrames);
        const auto CloseMax = Get_Max(_CloseFrames);
        const auto CloseMean = Get_Mean(_CloseFrames);
        const auto OpenMin = Get_Min(_OpenFrames);
        const auto OpenMax = Get_Max(_OpenFrames);
        const auto OpenMean = Get_Mean(_OpenFrames);
        const auto RecastClose = RecastMeasuredCloseFrames;
        const auto RecastOpen = RecastMeasuredOpenFrames;

        ck::nav::Display(f"[GROUNDNAV-REPAIR] door over {Rounds} rounds: closeFrames min={CloseMin} max={CloseMax} mean={CloseMean :.2} | openFrames min={OpenMin} max={OpenMax} mean={OpenMean :.2} (Recast markup box measured {RecastClose} close / {RecastOpen} open)");

        Assert_Equals_Int(_CloseRepairsObserved, RoundCount,
            f"every round must have observed a close (got {_CloseRepairsObserved} of {Rounds})");
        Assert_Equals_Int(_OpenRepairsObserved, RoundCount,
            f"every round must have observed an open (got {_OpenRepairsObserved} of {Rounds})");
    }

    // An ASSERTION rather than a wait, and deliberately so: round 3 already waited on this exact
    // condition, so a second wait would be satisfied on arrival and would prove nothing (the wait
    // rules in CkTests/CLAUDE.md, rule 1). Read directly it still fails a run that somehow left the
    // shared world with a hole in it - and it runs BEFORE the volume is destroyed, because a
    // projection against a torn-down field answers NoProvider whatever the ground under it looks
    // like, which would turn this into a check that cannot fail.
    UFUNCTION()
    private void Step_AssertNoHoleLeftBehind(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(ck::IsValid(_Door),
            "the last round released the door, so no markup of this fixture's may still be painted on the shared world");

        Assert_True(Get_DoorSpotProjects(),
            "the door spot must project on bare floor once the last door is released - a run that ends with the carve still in the field hands the next fixture a hole it did not paint");
    }

    //------------------------------------------------------------------------
    // Fixture geometry - every expected tile index is arithmetic over the
    // lattice, computed here rather than read back out of the system under test.
    //------------------------------------------------------------------------

    private FVector Get_DoorCentre() { return FVector(0.0, BandY, SurfaceZ); }

    // WHY THESE ARE THE EXPECTED INDICES. Get_RepairTileIndices inflates the dirty box in XY by the
    // field's halo width and takes every tile it meets. The door is a 150uu half box on the centre
    // of tile (2,2), so on each axis the dirty box is [-150, +150] about the volume centre and the
    // inflated box is [-350, +350]. The lattice runs from the volume corner in 400uu steps, so on X
    // that is floor((-350 + 1000) / 400) = 1 through floor((350 + 1000) / 400) = 3, and Y is the
    // same by symmetry. Nine tiles of twenty-five: the sixteen rim tiles are ground no door repair
    // may ever name.
    private int32 Get_ExpectedTileIndexMin()
    {
        return Get_TileIndexAt(-DoorHalfXY - HaloUu);
    }

    private int32 Get_ExpectedTileIndexMax()
    {
        return Get_TileIndexAt(DoorHalfXY + HaloUu);
    }

    private int32 Get_ExpectedTileCount()
    {
        const auto Span = Get_ExpectedTileIndexMax() - Get_ExpectedTileIndexMin() + 1;

        return Span * Span;
    }

    // An offset from the volume CENTRE to the index of the tile covering it. Both axes share this
    // because the volume is square about the band and the door sits on its centre. The distance
    // from the corner is non-negative by construction - the door and its halo lie wholly inside the
    // volume - so truncating to int32 is a floor rather than a round toward zero.
    private int32 Get_TileIndexAt(float InOffsetFromCentreUu)
    {
        const auto FromCornerUu = InOffsetFromCentreUu + VolumeHalfX;

        return int32(FromCornerUu / TileSizeUu);
    }

    private float Get_TileEdgeOffsetUu(int32 InTileIndex)
    {
        return (float(InTileIndex) * TileSizeUu) - VolumeHalfX;
    }

    // The union of the expected tiles' world bounds. WIDER than the halo-inflated box itself,
    // because a changed-bounds box is assembled from whole TILES: a tile the inflated box merely
    // clips is re-baked and published entire.
    private FVector Get_ExpectedRepairMin()
    {
        const auto Edge = Get_TileEdgeOffsetUu(Get_ExpectedTileIndexMin());

        return FVector(Edge, BandY + Edge, VolumeFloorZ);
    }

    private FVector Get_ExpectedRepairMax()
    {
        const auto Edge = Get_TileEdgeOffsetUu(Get_ExpectedTileIndexMax() + 1);

        return FVector(Edge, BandY + Edge, VolumeCeilingZ);
    }

    // Z is deliberately not tested: every tile's world bounds span the volume's whole vertical
    // extent whatever the repair touched, so a Z comparison would assert the lattice rather than
    // the repair.
    private bool Get_IsWithinExpectedRepairBounds(FBox InBounds)
    {
        const auto ExpectedMin = Get_ExpectedRepairMin();
        const auto ExpectedMax = Get_ExpectedRepairMax();

        return InBounds.Min.X >= ExpectedMin.X - BoundsToleranceUu
            && InBounds.Min.Y >= ExpectedMin.Y - BoundsToleranceUu
            && InBounds.Max.X <= ExpectedMax.X + BoundsToleranceUu
            && InBounds.Max.Y <= ExpectedMax.Y + BoundsToleranceUu;
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
    private bool Get_DoorSpotProjects()
    {
        auto Query = FCk_NavSurface_ProjectionQuery(Get_DoorCentre());
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

        if (ck::IsValid(_Door))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Door));
            _Door = FCk_Handle_NavSurfaceMarkup();
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
