// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: BUILD READS CURRENT UNTIL THE WORLD MOVES
//============================================================================
//
// Get_IsBuildCurrent answers one question - has the world or the authored
// records moved under the published field with no publish yet - and it answers
// it out of two stored halves: the input fingerprint the standing field went
// out with, and the geometry revision it was produced against. This pin drives
// both halves, one at a time, and asserts the same three-beat shape for each:
//
//   TRUE right after the build publishes, because nothing has moved yet.
//   FALSE the moment the input moves, before the publish that answers it lands.
//   TRUE again once that publish has landed and the volume has settled.
//
// The middle beat is the one worth having. Without it the pin would say only
// that a settled volume reads current, which a function returning a constant
// true would also satisfy.
//
// TWO MOVERS, because two different halves drift. A neutral impassable-box
// paint moves the AUTHORED records; a second static body raised inside the
// volume moves the WORLD, which nothing but a repair republishes against, so
// the repair is asked for explicitly the way a consumer that knows its own
// ground moved would ask for it.
//
// WHY THE BAKE IS SLICED TO ONE TILE A TICK. At the default probe budget the
// paint's repair lands inside the frame the paint drained in, and there is no
// window in which the records have moved and the publish has not. A budget of
// one probe admits exactly one tile per tick, so the window is many frames wide
// and the FALSE beat is a condition rather than a coin toss.
//
// FIXTURE. One Static JoltBody slab whose top sits at Z 0, overhanging the
// volume by 200uu on every horizontal side so no cliff edge exists inside the
// field, auto-build disabled so the bake waited on is the one asked for. A box
// shape is convex and therefore closed - an open mesh would trip the bake's
// OPEN COLLISION warning, and the harness escalates a Warning into a failure.
//
// The provider is per world and every other fixture in this map reads it, so
// the previous selection is captured before the swap and handed back both when
// this test concludes AND in DoEndPlay - every exit path, including the engine
// TimeLimit one, must put the world back.
//
// Isolated Y band: 146000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Fingerprint_BuildReadsCurrentUntilTheWorldMoves : UCk_AutoTest_Base
{
    // Nine tiles of build plus two sliced repairs, every tile of them a tick apart. Deliberately
    // slack: a contract that expires on the harness's anonymous TimesUp names nothing, and every
    // wait below carries its own budget so it fails on its own condition.
    default _TimeoutSeconds = 300.0f;

    //------------------------------------------------------------------------
    // Fixture geometry - a 3x3 lattice at 400uu tiles
    //------------------------------------------------------------------------

    private const float BandY = 146000.0;

    private const float VolumeHalfX = 600.0;
    private const float VolumeHalfY = 600.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    // Overhangs the volume by 200uu on every horizontal side, so the volume's interior never
    // contains a slab edge for the ledge filter to find.
    private const float SlabHalfX = 800.0;
    private const float SlabHalfY = 800.0;
    private const float SlabHalfZ = 50.0;

    private const float SurfaceZ = 0.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 400.0;

    // The budget gates whether the NEXT tile starts and a tile is never split, so one probe buys
    // exactly one tile a tick - which is what makes the not-current window observable.
    private const int32 ProbeBudgetPerTick = 1;

    private const float AgentRadius = 42.0;
    private const float ProfileHalfHeightUu = 96.0;

    // The paint: an impassable box on the interior of the middle tile.
    private const float DoorHalfXY = 150.0;
    private const float DoorHalfZ = 200.0;

    // The pillar: a second Static body raised inside the volume AFTER the field published, which is
    // the geometry half of the identity moving.
    private const float PillarHalfXY = 100.0;
    private const float PillarHalfZ = 150.0;
    private const float PillarOffsetX = -300.0;
    private const float PillarOffsetY = -300.0;

    // The ground the repair names: the pillar's footprint plus a margin, spanning the volume's whole
    // vertical extent. Non-degenerate on all three axes, which Request_Repair requires.
    private const float DirtyMarginUu = 100.0;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 3600;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 NotCurrentFrameBudget = 1800;
    private const int32 SettleFrameBudget = 3600;

    //------------------------------------------------------------------------
    // Fixture handles
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _PillarEntity;
    private FCk_Handle _VolumeEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_JoltBody _PillarBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_NavSurfaceMarkup _Door;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    //------------------------------------------------------------------------
    // Episode bookkeeping
    //------------------------------------------------------------------------

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    private int32 _RepairCompletions = 0;
    private ECk_Request_OperationResult _LastRepairResult = ECk_Request_OperationResult::Failed;

    // How many polls each not-current window stayed open for. Reported and never asserted against:
    // how many passes a sliced repair needs is a property of the probe budget and of processor
    // ordering, and pinning it would make an ordering change read as a defect.
    private int32 _PaintNotCurrentPolls = 0;
    private int32 _WorldNotCurrentPolls = 0;

    // The identity the volume reported at each beat, so the report says which number moved.
    private int64 _PrintAfterBuild = 0;
    private int64 _PrintAfterPaint = 0;
    private int64 _PrintAfterRepair = 0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage the floor and the volume",                 n"Step_BuildFixture");
        Add_Step_WaitUntil("the floor reaches the Jolt static world",        n"Check_FloorBodyAdded",   BodyFrameBudget);
        Add_Step(          "ask the volume to bake",                         n"Step_RequestBake");
        Add_Step_WaitUntil("the field reports itself built",                 n"Check_FieldBuilt",       BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",        n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles at Ready",               n"Check_SurfaceSettled",   SurfaceFrameBudget);
        Add_Step(          "a freshly published field reads current",        n"Step_AssertCurrentAfterBuild");

        Add_Step(          "paint an impassable box on the middle tile",     n"Step_PaintDoor");
        Add_Step_WaitUntil("the records moved ahead of the publish",         n"Check_PaintNotCurrent",  NotCurrentFrameBudget);
        Add_Step_WaitUntil("the paint's repair publishes and settles",       n"Check_Settled",          SettleFrameBudget);
        Add_Step(          "the publish caught the records up",              n"Step_AssertCurrentAfterPaint");

        Add_Step(          "raise a pillar inside the published field",      n"Step_RaisePillar");
        Add_Step_WaitUntil("the pillar reaches the Jolt static world",       n"Check_PillarBodyAdded",  BodyFrameBudget);
        Add_Step_WaitUntil("the world moved under the published field",      n"Check_WorldNotCurrent",  NotCurrentFrameBudget);
        Add_Step(          "ask for a repair of the ground that moved",      n"Step_RequestRepair");
        Add_Step_WaitUntil("the repair publishes and settles",               n"Check_RepairSettled",    SettleFrameBudget);
        Add_Step(          "the publish caught the world up",                n"Step_AssertCurrentAfterRepair");

        Add_Step(          "report what each half cost",                     n"Step_Report");
        Add_Step(          "hand the world back",                            n"Step_Cleanup");

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

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid GroundNav volume handle");

        // Nothing has published, so there is no bake for an identity to be OF - which is a different
        // answer from "the inputs still match", and the one a caller polling before the first build
        // has to be given.
        Assert_False(utils_ground_nav_volume::Get_IsBuildCurrent(_Volume),
            "a volume that has published nothing cannot be build-current: there is no bake for its inputs to be current with");
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

    UFUNCTION()
    private void Check_Settled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_IsSurfaceSettled());
    }

    //------------------------------------------------------------------------
    // Beat one: a freshly published field
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertCurrentAfterBuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PrintAfterBuild = utils_ground_nav_volume::Get_BuildFingerprint(_Volume);

        Assert_True(_PrintAfterBuild != 0,
            "a published field carries the fingerprint of the inputs it went out with, and zero is what an unpublished volume reports");

        Assert_True(utils_ground_nav_volume::Get_IsBuildCurrent(_Volume),
            "a field that has just published, with nothing moved since, must read build-current - otherwise every later assertion here is measuring noise");
    }

    //------------------------------------------------------------------------
    // Beat two: the authored records move
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PaintDoor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(DoorHalfXY, DoorHalfXY, DoorHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_DoorCentre(), FVector::OneVector));

        _Door = utils_nav_surface::Request_ImpassableBox(Request);

        Assert_True(ck::IsValid(_Door),
            "Request_ImpassableBox hands back the handle the caller needs to observe and release the paint - an invalid one leaves the carve unreachable");

        // The markup entity is parented to the WORLD rather than to this runner, so the harness's own
        // subtree teardown never reaches it.
        Track_ForCleanup(FCk_Handle(_Door));
    }

    UFUNCTION()
    private void Check_PaintNotCurrent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _PaintNotCurrentPolls += 1;

        auto Res = OutResult;
        Res.Set(!utils_ground_nav_volume::Get_IsBuildCurrent(_Volume));
    }

    UFUNCTION()
    private void Step_AssertCurrentAfterPaint(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PrintAfterPaint = utils_ground_nav_volume::Get_BuildFingerprint(_Volume);

        Assert_True(_PrintAfterPaint != _PrintAfterBuild,
            f"a record the volume did not hold before is an authored input that moved, so the identity the publish stamped must differ from the one before it (both read {_PrintAfterPaint})");

        Assert_True(utils_ground_nav_volume::Get_IsBuildCurrent(_Volume),
            "the repair the paint raised has published and the volume has settled, so the stored identity names the records that are on the volume now");
    }

    //------------------------------------------------------------------------
    // Beat three: the world moves
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RaisePillar(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PillarEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _PillarEntity.Request_OverrideToSelf();

        utils_transform::Add(_PillarEntity,
            FTransform(FRotator::ZeroRotator, Get_PillarCentre(), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto PillarShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        PillarShape.Set_HalfExtents(FVector(PillarHalfXY, PillarHalfXY, PillarHalfZ));

        auto PillarParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        PillarParams.Set_ShapeDimensions(PillarShape);
        PillarParams.Set_MotionType(ECk_MotionType::Static);

        _PillarBody = utils_jolt_body::Add(_PillarEntity, PillarParams);

        Assert_True(ck::IsValid(_PillarBody), "the pillar's Jolt body must be valid");
    }

    UFUNCTION()
    private void Check_PillarBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_jolt_body::Get_IsBodyAdded(_PillarBody));
    }

    UFUNCTION()
    private void Check_WorldNotCurrent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _WorldNotCurrentPolls += 1;

        auto Res = OutResult;
        Res.Set(!utils_ground_nav_volume::Get_IsBuildCurrent(_Volume));
    }

    UFUNCTION()
    private void Step_RequestRepair(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Nothing republishes a volume because the world moved - a moved body is the consumer's own
        // news - so the repair is asked for here the way a consumer that knows which ground moved
        // asks for it.
        utils_ground_nav_volume::Request_Repair(_Volume,
            FCk_Request_GroundNavVolume_Repair(Get_PillarDirtyBounds()),
            FCk_Delegate_Request_OnCompleted(this, n"OnRepairCompleted"));
    }

    UFUNCTION()
    private void OnRepairCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RepairCompletions += 1;
        _LastRepairResult = InResult;
    }

    // Both conditions are needed. The completion is the EVENT - it fires where the repair publishes,
    // so it cannot be true on arrival - and the settle is what makes the read below land on the field
    // that publish produced rather than on the one it replaced.
    UFUNCTION()
    private void Check_RepairSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RepairCompletions >= 1 && utils_nav_surface::Get_IsSurfaceSettled());
    }

    UFUNCTION()
    private void Step_AssertCurrentAfterRepair(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastRepairResult == ECk_Request_OperationResult::Succeeded,
            f"a repair over ground the published field covers must succeed (got {_LastRepairResult})");

        _PrintAfterRepair = utils_ground_nav_volume::Get_BuildFingerprint(_Volume);

        // Nothing AUTHORED moved across the pillar, so the input half is the same number it was: the
        // half that moved and came back is the geometry revision, which is exactly the separation the
        // two stored halves exist for.
        Assert_True(_PrintAfterRepair == _PrintAfterPaint,
            f"a world that moved changes no authored input, so the input fingerprint must be the one the paint left (was {_PrintAfterPaint}, now {_PrintAfterRepair})");

        Assert_True(utils_ground_nav_volume::Get_IsBuildCurrent(_Volume),
            "the repair republished against the world as it stands now, so the stored revision names it and the volume reads current again");
    }

    //------------------------------------------------------------------------
    // Report
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto PaintPolls = _PaintNotCurrentPolls;
        const auto WorldPolls = _WorldNotCurrentPolls;
        const auto BuildPrint = _PrintAfterBuild;
        const auto PaintPrint = _PrintAfterPaint;
        const auto RepairPrint = _PrintAfterRepair;

        ck::nav::Display(f"[GROUNDNAV-BUILD-CURRENT] paint window {PaintPolls} polls, world window {WorldPolls} polls | inputPrint build={BuildPrint} paint={PaintPrint} repair={RepairPrint}");
    }

    //------------------------------------------------------------------------
    // Geometry
    //------------------------------------------------------------------------

    private FVector Get_DoorCentre()
    {
        return FVector(0.0, BandY, SurfaceZ);
    }

    private FVector Get_PillarCentre()
    {
        return FVector(PillarOffsetX, BandY + PillarOffsetY, SurfaceZ + PillarHalfZ);
    }

    private FBox Get_PillarDirtyBounds()
    {
        const auto Centre = Get_PillarCentre();
        const auto HalfSpan = PillarHalfXY + DirtyMarginUu;

        return FBox(
            FVector(Centre.X - HalfSpan, Centre.Y - HalfSpan, VolumeFloorZ),
            FVector(Centre.X + HalfSpan, Centre.Y + HalfSpan, VolumeCeilingZ));
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. The provider is a WORLD selection
    // every later fixture in this map reads, and the two static bodies would otherwise stay in the
    // Jolt static world for the rest of the lane, handing every later bake ground it did not stage.
    private void Teardown()
    {
        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_VolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
            _VolumeEntity = FCk_Handle();
        }

        if (ck::IsValid(_PillarEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_PillarEntity);
            _PillarEntity = FCk_Handle();
        }

        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}
