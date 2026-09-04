// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A PROFILE TAG SELECTS THE PROFILE'S FIELD
//============================================================================
//
// One volume, two agent profiles, two published fields. The untagged default
// steps 80uu; the variant tagged CkTests.GroundNav.Profile.Crawler steps 40uu.
// A 60uu slab sits on the floor inside the volume, which is a step one of them
// can take and the other cannot - so the slab's rim is ground for the default
// and a ledge for the crawler, out of the same triangles and the same bake.
//
// The claim is that a neutral query's _ProfileTag SELECTS, and never merely
// hints: the same probe, the same extents, the same world, answered Success
// without the tag and NoSurface with it. Nothing else about the query differs,
// which is what makes this a test of the seam rather than of the fixture.
//
//----------------------------------------------------------------------------
// WHY THE PROBE STANDS ON THE SLAB'S CORNER CELL
//----------------------------------------------------------------------------
//
// Step height reaches the walkable set through the LEDGE FILTER: a span is
// demoted when a neighbouring column holds nothing within one step below it.
// The slab's interior cells are surrounded by slab and stay walkable for both
// profiles; only the rim has bare floor 60uu down beside it. So the assertion
// has to stand on a rim cell, and the corner cell is the rim twice over.
//
// The lattice is arithmetic, not luck. Cells are 25uu from the volume's own
// corner and the slab's near edge sits an exact multiple of 25uu from it, so
// the slab covers whole cells and its corner cell is the 25uu square starting
// at that edge. The probe is that square's centre.
//
// The search half-extents are tighter than one cell horizontally and tighter
// than the riser vertically, so the projection can reach nothing but the cell
// the probe stands in. Without both, a demoted rim cell would be answered by
// the walkable interior beside it or the floor below, and the two profiles
// would agree.
//
//----------------------------------------------------------------------------
// THE POSITIVE THE NoSurface RESTS ON
//----------------------------------------------------------------------------
//
// A variant that was never published would answer NoProvider, not NoSurface -
// but a fixture that mistook one for the other would still read "the crawler
// cannot stand there". So the crawler is also asked about bare floor well away
// from the slab, where it must answer Success. That is what makes the rim
// answer a verdict from the crawler's own field rather than the silence of a
// field that does not exist.
//
// FIXTURE. Two Static JoltBody boxes - a floor whose top sits at Z 0 and
// overhangs the volume by more than the bake's halo on every horizontal side,
// so no cliff edge exists inside the field, and the 60uu slab. A box shape is
// convex and therefore closed; an open mesh would trip the bake's OPEN
// COLLISION warning, and the harness escalates a Warning into a failure.
//
//----------------------------------------------------------------------------
// A REPAIR ON A MULTI-PROFILE VOLUME KEEPS BOTH FIELDS
//----------------------------------------------------------------------------
//
// A local repair rewrites ONE field, so a volume carrying profile variants is
// served by a whole-volume rebuild instead: repairing the default alone would
// leave it describing the world as it is and the crawler describing it as it
// was - one volume answering two different worlds depending on which profile
// asked. The second phase raises a repair over the step slab and states what a
// caller may rely on when it lands:
//
//   1. IT SUCCEEDS. Taken over by a rebuild is not a rejection; the caller's
//      region is baked and published, so the request completes Succeeded.
//   2. THE FIELD IS NEW. The build epoch is strictly newer than the one that
//      was published before the repair, which is what a consumer diffs to know
//      its own cached answers are behind.
//   3. BOTH FIELDS CAME BACK. The default and the crawler are both built again
//      - a rebuild that republished one and dropped the other is exactly the
//      split-brain the takeover exists to prevent, and it would leave the
//      surviving field answering for a profile it was never baked for.
//   4. THE SEAM STILL HOLDS. The two projections of phase one are asked again
//      and must answer what they answered before. The geometry never moved, so
//      an answer that changed means the rebuild lost the profile keying rather
//      than that the ground did.
//
// LEDGE SENSITIVITY IS LEFT AT ITS DEFAULT on both profiles, unlike every other
// GroundNav fixture in this corpus, because the ledge filter is exactly where
// step height decides the walkable set. A fixture that switched it off would
// bake two identical fields and pin nothing. That is also why the floor
// overhangs by more than the halo: with the filter live, a perimeter cliff
// inside the field would demote ground this test says nothing about.
//
// The provider is per world and every other fixture in this map reads it, so
// the previous selection is captured before the swap and handed back both when
// this test concludes AND in DoEndPlay - every exit path, including the engine
// TimeLimit one, must put the world back.
//
// Isolated Y band: 144000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_ProfileVariant_QuerySelectsTheProfilesField : UCk_AutoTest_Base
{
    // Nine tiles baked twice over - once per profile - plus a provider switch and a settle, and then
    // the whole thing again: a repair on a volume holding variants is served by a WHOLE-VOLUME
    // rebuild, so the second phase costs a second bake of both fields and a second settle. Slack on
    // purpose: every wait below carries its own budget so it fails on its own condition rather than
    // on the harness's anonymous TimesUp.
    default _TimeoutSeconds = 420.0f;

    //------------------------------------------------------------------------
    // Fixture geometry
    //------------------------------------------------------------------------

    private const float BandY = 144000.0;

    // 1000 x 1000 uu of volume at 400uu tiles is a 3 x 3 lattice.
    private const float VolumeHalfX = 500.0;
    private const float VolumeHalfY = 500.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 400.0;

    // Overhangs the volume by 400uu on every horizontal side, which is more than the 200uu halo the
    // bake reads with, so the floor's own edge is never inside anything the field looks at.
    private const float FloorHalfX = 900.0;
    private const float FloorHalfY = 900.0;
    private const float FloorHalfZ = 50.0;

    private const float SurfaceZ = 0.0;

    // The riser sits strictly between the two step heights, so it is the one thing the two profiles
    // disagree about and the disagreement is not a matter of a cell height either way.
    private const float DefaultStepHeightUu = 80.0;
    private const float VariantStepHeightUu = 40.0;
    private const float StepRiseUu = 60.0;

    // The slab's near edge, as an offset from the volume's corner. An exact multiple of the cell size
    // so the slab covers WHOLE cells and its corner cell is the 25uu square starting right here.
    private const float SlabNearEdgeFromCornerUu = 600.0;
    private const float SlabSpanUu = 200.0;

    private const float AgentRadiusUu = 42.0;
    private const float AgentHalfHeightUu = 96.0;

    // Horizontally tighter than the 12.5uu gap to the nearest neighbouring cell; vertically tighter
    // than the 60uu drop to the floor. Both are what stop the projection reaching past the one cell
    // the two profiles disagree about.
    private const FVector ProbeHalfExtents = FVector(10.0, 10.0, 20.0);

    // Well away from the slab and on bare floor, where every profile has ground.
    private const float ControlOffsetUu = -300.0;

    // How far past the slab's own footprint the dirty box reaches. The box names ground whose
    // walkability a caller no longer trusts, and the cells the slab's rim demotes are outside the slab
    // itself, so a box drawn exactly on the slab would name less ground than the slab decides.
    private const float DirtyMarginUu = 25.0;

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 7200;
    private const int32 SettleFrameBudget = 1800;

    // The repair is taken over by a whole-volume rebuild, so this wait covers a second bake of both
    // fields AND the settle behind it - the build budget and the settle budget end to end.
    private const int32 RepairFrameBudget = 9000;

    //------------------------------------------------------------------------
    // Fixture handles
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _SlabEntity;
    private FCk_Handle _VolumeEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_JoltBody _SlabBody;
    private FCk_Handle_GroundNavVolume _Volume;

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

    private int32 _SettlePolls = 0;

    // What the first phase saw, so the second phase can say the answers came back UNCHANGED rather
    // than merely that they were right twice. NoProvider is the never-asked value: no query answers it
    // once the world is on the GroundNav provider, so a phase that never ran cannot look like one that
    // did.
    private ECk_NavSurface_QueryStatus _RimUntaggedBefore = ECk_NavSurface_QueryStatus::NoProvider;
    private ECk_NavSurface_QueryStatus _RimCrawlerBefore = ECk_NavSurface_QueryStatus::NoProvider;

    // The epoch of the field the first phase's answers came out of, read immediately before the repair
    // is raised.
    private int64 _EpochBeforeRepair = 0;

    private int32 _RepairCompletions = 0;
    private ECk_Request_OperationResult _LastRepairResult = ECk_Request_OperationResult::Failed;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage the floor, the step slab and a two-profile volume", n"Step_BuildFixture");
        Add_Step_WaitUntil("both bodies reach the Jolt static world",                 n"Check_BodiesAdded",  BodyFrameBudget);
        Add_Step(          "ask the volume to bake",                                  n"Step_RequestBake");
        Add_Step_WaitUntil("the field reports itself built",                          n"Check_FieldBuilt",   BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",                 n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles",                                 n"Check_SurfaceSettled", SettleFrameBudget);
        Add_Step(          "the profile tag selects the profile's own field",         n"Step_AssertTagSelects");
        Add_Step(          "raise a repair over the step slab",                       n"Step_RequestRepair");
        Add_Step_WaitUntil("the repair completes and the surface settles again",      n"Check_RepairSettled", RepairFrameBudget);
        Add_Step(          "the rebuild republished both profiles' fields",           n"Step_AssertRepairKeptBothFields");
        Add_Step(          "hand the world back",                                     n"Step_Cleanup");

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
        _FloorEntity.Set_DebugName(n"AutoTest_GroundNav_ProfileVariant_Floor");

        utils_transform::Add(_FloorEntity,
            FTransform(FRotator::ZeroRotator, FVector(0.0, BandY, SurfaceZ - FloorHalfZ)),
            ECk_Replication::DoesNotReplicate);

        _FloorBody = utils_jolt_body::Add(_FloorEntity,
            Make_StaticBoxParams(FVector(FloorHalfX, FloorHalfY, FloorHalfZ)));

        Assert_True(ck::IsValid(_FloorBody), "the floor's Jolt body must be valid");

        _SlabEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _SlabEntity.Request_OverrideToSelf();
        _SlabEntity.Set_DebugName(n"AutoTest_GroundNav_ProfileVariant_StepSlab");

        utils_transform::Add(_SlabEntity,
            FTransform(FRotator::ZeroRotator, Get_SlabCentre()),
            ECk_Replication::DoesNotReplicate);

        _SlabBody = utils_jolt_body::Add(_SlabEntity,
            Make_StaticBoxParams(FVector(SlabSpanUu * 0.5, SlabSpanUu * 0.5, StepRiseUu * 0.5)));

        Assert_True(ck::IsValid(_SlabBody), "the step slab's Jolt body must be valid");

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();
        _VolumeEntity.Set_DebugName(n"AutoTest_GroundNav_ProfileVariant_Volume");

        auto Config = FCk_GroundNav_BakeConfig(float32(CellSizeUu), float32(CellHeightUu));
        Config.Set_TileSizeUu(float32(TileSizeUu));

        const auto Bounds = FBox(
            FVector(-VolumeHalfX, BandY - VolumeHalfY, VolumeFloorZ),
            FVector( VolumeHalfX, BandY + VolumeHalfY, VolumeCeilingZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(
            Bounds, Config, Make_Profile(DefaultStepHeightUu));

        // The bake waited on must be the one asked for, not one that happened to run at setup.
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        TArray<FCk_GroundNav_ProfileVariant> Variants;
        Variants.Add(FCk_GroundNav_ProfileVariant(
            Get_CrawlerTag(), Make_Profile(VariantStepHeightUu)));

        VolumeParams.Set_ProfileVariants(Variants);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid GroundNav volume handle");
    }

    UFUNCTION()
    private void Check_BodiesAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_jolt_body::Get_IsBodyAdded(_FloorBody) &&
                utils_jolt_body::Get_IsBodyAdded(_SlabBody));
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

    // The ONE named settle to wait on after a provider switch: nothing is in flight and nothing is
    // pending, so the published surface is the one every query below will answer from. A fixed number
    // of ticks only ever happens to be enough for whichever provider it was measured against.
    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _SettlePolls += 1;

        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_IsSurfaceSettled());
    }

    //------------------------------------------------------------------------
    // The assertion
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertTagSelects(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto CrawlerTag = Get_CrawlerTag();

        const auto RimUntagged = Project(Get_SlabCornerCellCentre(), FGameplayTag());
        const auto RimCrawler = Project(Get_SlabCornerCellCentre(), CrawlerTag);
        const auto FloorCrawler = Project(Get_BareFloorProbe(), CrawlerTag);

        const auto Tags = utils_ground_nav_volume::Get_ProfileVariantTags(_Volume);
        const auto BuiltForCrawler = utils_ground_nav_volume::Get_IsBuilt_ForProfile(_Volume, CrawlerTag);
        const auto BuiltForDefault = utils_ground_nav_volume::Get_IsBuilt_ForProfile(_Volume, FGameplayTag());

        const auto SettleFrames = _SettlePolls;
        const auto RimUntaggedStatus = RimUntagged.Get_Status();
        const auto RimCrawlerStatus = RimCrawler.Get_Status();
        const auto FloorCrawlerStatus = FloorCrawler.Get_Status();
        const auto VariantCount = Tags.Num();

        // Kept for the second phase, which asks the same two probes after a rebuild and says they came
        // back unchanged. Recorded before the assertions below rather than after, so the second phase
        // reads what was measured even on a run this one is about to fail.
        _RimUntaggedBefore = RimUntaggedStatus;
        _RimCrawlerBefore = RimCrawlerStatus;

        ck::nav::Display(f"[GROUNDNAV-PROFILE] settleFrames={SettleFrames} variantTags={VariantCount} builtForDefault={BuiltForDefault} builtForCrawler={BuiltForCrawler} rimUntagged={RimUntaggedStatus} rimCrawler={RimCrawlerStatus} floorCrawler={FloorCrawlerStatus}");

        // What the volume AUTHORS, read back off the volume: the untagged default is not one of these,
        // and a list carrying it would be unusable as a set of selectors.
        Assert_Equals_Int(VariantCount, 1,
            f"the volume authored exactly one profile variant, and the tags it reports back are the variants alone (got {VariantCount})");

        const auto ReportedTag = Tags[0].ToString();

        Assert_True(Tags[0] == CrawlerTag,
            f"the reported tag must be the one that was authored (got {ReportedTag})");

        // What the volume has BUILT, which is the separate question: a tag is authored data and
        // survives a failed bake, where a field exists only once one published.
        Assert_True(BuiltForDefault,
            "a volume that reports itself built is built for its untagged default, which is what an empty profile tag asks about");

        Assert_True(BuiltForCrawler,
            "one bake produces one field per profile, so a volume that authored a variant and finished baking must be built for that variant's tag too - false here means the second field was never published and every projection below is measuring one field twice");

        // The POSITIVE the NoSurface rests on. A variant that was never published would answer
        // NoProvider on bare floor as well, and a fixture that read that as "the crawler cannot stand
        // there" would pass while pinning nothing.
        Assert_True(FloorCrawlerStatus == ECk_NavSurface_QueryStatus::Success,
            f"the crawler's own field covers the bare floor beside the slab, so a projection there carrying its tag must succeed (got {FloorCrawlerStatus})");

        // The claim. Same probe, same extents, same world - only the tag differs.
        Assert_True(RimUntaggedStatus == ECk_NavSurface_QueryStatus::Success,
            f"the untagged default steps {DefaultStepHeightUu}uu, which clears the {StepRiseUu}uu riser, so the slab's corner cell is ground it may stand on (got {RimUntaggedStatus})");

        const auto RimUntaggedZ = float32(RimUntagged.Get_Location().Z);

        Assert_True(Math::Abs(RimUntaggedZ - float32(StepRiseUu)) < 1.0f,
            f"the untagged answer must be the slab's own top face rather than the floor below it, or the probe never reached the ground the two profiles disagree about (got Z={RimUntaggedZ})");

        Assert_True(RimCrawlerStatus == ECk_NavSurface_QueryStatus::NoSurface,
            f"the crawler steps {VariantStepHeightUu}uu, which the {StepRiseUu}uu riser defeats, so the slab's corner cell is a ledge on ITS field and the same probe must find no surface. Success here means the tag was ignored and the query was answered from the default's ground, which is the one failure a profile variant exists to prevent (got {RimCrawlerStatus})");
    }

    //------------------------------------------------------------------------
    // The repair, and what a rebuild owes both profiles
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RequestRepair(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Read off the PUBLISHED field, and read here rather than at the assertion: this is the epoch
        // the answers just measured came out of, and it is what the rebuild has to move past.
        _EpochBeforeRepair = utils_ground_nav_volume::Get_BuildEpoch(_Volume);

        utils_ground_nav_volume::Request_Repair(_Volume,
            FCk_Request_GroundNavVolume_Repair(Get_StepSlabDirtyBounds()),
            FCk_Delegate_Request_OnCompleted(this, n"OnRepairCompleted"));
    }

    UFUNCTION()
    private void OnRepairCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RepairCompletions += 1;
        _LastRepairResult = InResult;
    }

    // Two conditions and both are needed. The completion is the EVENT - it fires where the rebuild
    // publishes, so it cannot be true on arrival - and the settle is what makes the projections below
    // read the field that publish produced rather than the one it replaced.
    UFUNCTION()
    private void Check_RepairSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RepairCompletions >= 1 && utils_nav_surface::Get_IsSurfaceSettled());
    }

    UFUNCTION()
    private void Step_AssertRepairKeptBothFields(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto CrawlerTag = Get_CrawlerTag();

        const auto RimUntagged = Project(Get_SlabCornerCellCentre(), FGameplayTag());
        const auto RimCrawler = Project(Get_SlabCornerCellCentre(), CrawlerTag);

        const auto EpochBefore = _EpochBeforeRepair;
        const auto EpochAfter = utils_ground_nav_volume::Get_BuildEpoch(_Volume);
        const auto BuiltForDefault = utils_ground_nav_volume::Get_IsBuilt_ForProfile(_Volume, FGameplayTag());
        const auto BuiltForCrawler = utils_ground_nav_volume::Get_IsBuilt_ForProfile(_Volume, CrawlerTag);
        const auto RepairResult = _LastRepairResult;
        const auto RimUntaggedStatus = RimUntagged.Get_Status();
        const auto RimCrawlerStatus = RimCrawler.Get_Status();
        const auto RimUntaggedWas = _RimUntaggedBefore;
        const auto RimCrawlerWas = _RimCrawlerBefore;

        ck::nav::Display(f"[GROUNDNAV-PROFILE-REPAIR] epochBefore={EpochBefore} epochAfter={EpochAfter} builtForDefault={BuiltForDefault} builtForCrawler={BuiltForCrawler} repairResult={RepairResult} rimUntagged={RimUntaggedStatus} rimCrawler={RimCrawlerStatus}");

        // A local repair rewrites one field, so a volume holding variants is served by a whole-volume
        // rebuild instead. Taken over is not turned away: the caller's region is baked and published by
        // the build that took it, so the request it raised completes.
        Assert_True(RepairResult == ECk_Request_OperationResult::Succeeded,
            f"a repair on a volume carrying profile variants is served by a whole-volume rebuild, which bakes and publishes the region the caller named - so the request must complete Succeeded rather than be refused (got {RepairResult})");

        // The epoch is what a consumer diffs to learn its cached answers are behind, so a publish that
        // did not move it is a publish no reader can tell happened.
        Assert_True(EpochAfter > EpochBefore,
            f"the rebuild published a new field, so the volume's build epoch must be strictly newer than the one the first phase's answers came out of (was {EpochBefore}, now {EpochAfter})");

        // Both halves of the publish, asked separately. A rebuild that republished one field and
        // dropped the other leaves the survivor answering for a profile it was never baked for, which
        // is the split-brain the whole-volume takeover exists to prevent.
        Assert_True(BuiltForDefault,
            "the rebuild that served the repair bakes every profile the volume authors, so the untagged default must be built again once it publishes");

        Assert_True(BuiltForCrawler,
            "one rebuild produces one field per profile, so the crawler's variant must be built again too - false here means the rebuild republished the default alone and left the crawler answering from a field baked against a world that has since been repaired");

        // The geometry never moved, so the seam the first phase pinned is the same seam. An answer that
        // changed across the rebuild means the profile keying was lost in it, not that the ground was.
        Assert_True(RimUntaggedStatus == RimUntaggedWas,
            f"nothing in the world moved across the repair, so the untagged default must answer the slab's corner cell exactly as it did before the rebuild (was {RimUntaggedWas}, now {RimUntaggedStatus})");

        Assert_True(RimCrawlerStatus == RimCrawlerWas,
            f"nothing in the world moved across the repair, so the crawler must answer the slab's corner cell exactly as it did before the rebuild - a rim that became ground for it means the rebuild published one field under both tags (was {RimCrawlerWas}, now {RimCrawlerStatus})");
    }

    //------------------------------------------------------------------------
    // Fixture geometry - arithmetic over the lattice, computed here rather than
    // read back out of the system under test.
    //------------------------------------------------------------------------

    private FCk_Fragment_JoltBody_ParamsData Make_StaticBoxParams(FVector InHalfExtents)
    {
        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);

        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);

        return Params;
    }

    // Radius is deliberately absent from the standing profile - clearance is answered per query as
    // clearance >= R - so only the height and the step matter to the bake.
    private FCk_GroundNav_AgentProfile Make_Profile(float InStepHeightUu)
    {
        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(float32(AgentHalfHeightUu), float32(AgentRadiusUu))));

        Profile.Set_StepHeightUu(float32(InStepHeightUu));

        // Left at the conservative default rather than switched off as the other GroundNav fixtures do:
        // the ledge filter is where step height decides the walkable set, so a fixture that disabled it
        // would bake two identical fields.
        return Profile;
    }

    private FGameplayTag Get_CrawlerTag()
    {
        // Registered natively by Test_GroundNav_ProfileVariants.cpp, which pins the same feature over
        // the registry. Resolving it by name rather than carrying a data asset for one test's sake.
        return utils_gameplay_tag::ResolveGameplayTag(n"CkTests.GroundNav.Profile.Crawler");
    }

    private float Get_SlabNearEdgeX()
    {
        return -VolumeHalfX + SlabNearEdgeFromCornerUu;
    }

    private float Get_SlabNearEdgeY()
    {
        return BandY - VolumeHalfY + SlabNearEdgeFromCornerUu;
    }

    private FVector Get_SlabCentre()
    {
        return FVector(
            Get_SlabNearEdgeX() + (SlabSpanUu * 0.5),
            Get_SlabNearEdgeY() + (SlabSpanUu * 0.5),
            SurfaceZ + (StepRiseUu * 0.5));
    }

    // The centre of the 25uu cell whose near corner is the slab's near corner: the slab's edge is an
    // exact multiple of the cell size from the volume's own corner, which the lattice is laid out
    // from, so this square is covered by slab and its -X and -Y neighbours are bare floor.
    private FVector Get_SlabCornerCellCentre()
    {
        return FVector(
            Get_SlabNearEdgeX() + (CellSizeUu * 0.5),
            Get_SlabNearEdgeY() + (CellSizeUu * 0.5),
            SurfaceZ + StepRiseUu);
    }

    private FVector Get_BareFloorProbe()
    {
        return FVector(ControlOffsetUu, BandY + ControlOffsetUu, SurfaceZ);
    }

    // The ground the repair names: the slab's footprint plus a cell of margin, spanning the volume's
    // whole vertical extent. Non-degenerate on all three axes, which Request_Repair requires - a flat
    // box is refused rather than enqueued.
    private FBox Get_StepSlabDirtyBounds()
    {
        const auto Centre = Get_SlabCentre();
        const auto HalfSpan = (SlabSpanUu * 0.5) + DirtyMarginUu;

        return FBox(
            FVector(Centre.X - HalfSpan, Centre.Y - HalfSpan, VolumeFloorZ),
            FVector(Centre.X + HalfSpan, Centre.Y + HalfSpan, VolumeCeilingZ));
    }

    private FCk_NavSurface_ProjectionResult Project(FVector InPoint, FGameplayTag InProfileTag)
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(ProbeHalfExtents);
        Query.Set_ProfileTag(InProfileTag);

        return utils_nav_surface::Try_ProjectPoint(Query);
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
    // every later fixture in this map reads, and the two static bodies would otherwise stay in the Jolt
    // static world for the rest of the lane, handing every later bake ground it did not stage.
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

        if (ck::IsValid(_SlabEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_SlabEntity);
            _SlabEntity = FCk_Handle();
        }

        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}
