// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: TWO TILINGS OF ONE WORLD AGREE
//============================================================================
//
// The halo exists so that a tile agrees with a bake of a far wider region
// EXACTLY rather than within a tolerance - clearance saturates at the ceiling
// and the halo is sized from it, so no cell's value depends on how the world
// happened to be tiled. Nothing had ever tested that claim against real Jolt
// geometry: the headless suite drives the box-list stub, and the volume test
// beside this one bakes one tiling only, so a halo that read short at a seam
// would have gone unnoticed.
//
// Two volumes over the SAME slab, over the SAME bounds, with the SAME cell
// size - differing only in tile size, and therefore only in where the seams
// fall and how many halo boxes get pushed at Jolt:
//
//     A: TileSizeUu 500 -> span 500 -> 2x2 =  4 tiles
//     B: TileSizeUu 250 -> span 250 -> 4x4 = 16 tiles
//
// Both spans are exact. A span is snapped UP to a whole number of cells
// (ceil(size / 25) * 25), and 500 and 250 are already whole multiples of the
// 25uu cell; the 1000uu volume then divides evenly by both, so the two fields
// cover byte-for-byte the same region rather than one of them overhanging.
// That is what makes the walkable-cell equality below an exact assertion and
// not an approximate one.
//
// What is asserted, and why each one is not redundant:
//   - both built, and BuiltTileCount == TileCount on both: a tile that failed
//     is present and says Unbuilt, so a field can report Built while missing
//     ground, and every count below would then be comparing two different
//     amounts of world.
//   - equal walkable cell counts: the actual claim. Different halo boxes over
//     one Jolt world must rasterize the same walkable set.
//   - seam portals > 0 on both, and strictly more on the smaller tiling: the
//     equality above would also hold if seam derivation had quietly produced
//     nothing on either side, and a finer tiling has strictly more internal
//     seams to derive across (4 tile-pair seams against 24).
//
// The harness escalates warnings to failures, so an unmatched-seam warning
// out of seam derivation fails this test rather than passing quietly. That is
// the intent: a seam the two tilings disagree about is exactly the defect
// this exists to catch.
//
// Isolated Y band: 102000 - free per a census of every numeric literal under
// CkTests/Script (nothing else uses a coordinate between 100000 and 200000).
//============================================================================

class UCk_AutoTest_GroundNav_TiledBakeAgreesAcrossTileSizes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 40.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _CoarseVolume;
    private FCk_Handle_GroundNavVolume _FineVolume;

    private FVector _Centre = FVector(0.0, 102000.0, 0.0);
    private FVector _FloorHalfExtents = FVector(700.0, 700.0, 50.0);
    private FVector _VolumeHalfExtents = FVector(500.0, 500.0, 200.0);

    private int32 _CoarseCompletions = 0;
    private int32 _FineCompletions = 0;
    private ECk_Request_OperationResult _CoarseResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult _FineResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // One slab, wider than either volume, so every tile of both tilings has real world in its
        // halo rather than the edge of the fixture. Its TOP sits at the volumes' mid height.
        auto FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(FloorEntity,
            FTransform(FRotator::ZeroRotator, _Centre - FVector(0.0, 0.0, _FloorHalfExtents.Z)),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(_FloorHalfExtents);

        auto FloorParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);

        _FloorBody = utils_jolt_body::Add(FloorEntity, FloorParams);

        _CoarseVolume = DoAdd_Volume(500.0f);
        _FineVolume = DoAdd_Volume(250.0f);

        Assert_True(ck::IsValid(_CoarseVolume), "Add() must return a valid coarse volume handle");
        Assert_True(ck::IsValid(_FineVolume), "Add() must return a valid fine volume handle");

        Add_Step_WaitUntil("the floor's static body joins the Jolt world", n"Check_FloorBodyAdded");
        Add_Step(          "request both bakes",                           n"Step_RequestBuilds");
        Add_Step_WaitUntil("both bakes report back to their caller",       n"Check_BothCompleted");
        Add_Step(          "assert the two tilings agree",                 n"Step_AssertAgreement");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private FCk_Handle_GroundNavVolume DoAdd_Volume(float32 InTileSizeUu)
    {
        auto VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(25.0f, 10.0f);
        Config.Set_TileSizeUu(InTileSizeUu);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(FCk_ShapeCapsule_Dimensions(70.0f, 20.0f)));
        Profile.Set_LedgeSensitivity(0.0f);

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(
            FBox(_Centre - _VolumeHalfExtents, _Centre + _VolumeHalfExtents), Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        return utils_ground_nav_volume::Add(VolumeEntity, VolumeParams);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RequestBuilds(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_ground_nav_volume::Request_Build(_CoarseVolume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnCoarseCompleted"));

        utils_ground_nav_volume::Request_Build(_FineVolume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnFineCompleted"));
    }

    UFUNCTION()
    private void Step_AssertAgreement(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_CoarseCompletions, 1, "the coarse bake must report back exactly once");
        Assert_Equals_Int(_FineCompletions, 1, "the fine bake must report back exactly once");

        Assert_True(_CoarseResult == ECk_Request_OperationResult::Succeeded,
            f"the coarse bake must complete with Succeeded (got {_CoarseResult})");
        Assert_True(_FineResult == ECk_Request_OperationResult::Succeeded,
            f"the fine bake must complete with Succeeded (got {_FineResult})");

        Assert_True(utils_ground_nav_volume::Get_IsBuilt(_CoarseVolume),
            "the coarse volume must publish its field");
        Assert_True(utils_ground_nav_volume::Get_IsBuilt(_FineVolume),
            "the fine volume must publish its field");

        // Nothing below means anything if the two fields cover different amounts of world. A tile
        // that failed is PRESENT and says Unbuilt, so Built alone does not rule that out.
        auto CoarseTiles = utils_ground_nav_volume::Get_TileCount(_CoarseVolume);
        auto FineTiles = utils_ground_nav_volume::Get_TileCount(_FineVolume);

        Assert_Equals_Int(utils_ground_nav_volume::Get_BuiltTileCount(_CoarseVolume), CoarseTiles,
            "every tile of the coarse field must have baked");
        Assert_Equals_Int(utils_ground_nav_volume::Get_BuiltTileCount(_FineVolume), FineTiles,
            "every tile of the fine field must have baked");

        Assert_True(FineTiles > CoarseTiles,
            f"halving the tile size must divide the volume more finely, got {CoarseTiles} and {FineTiles}");

        // The claim. Different halo boxes over the same Jolt world, the same walkable set.
        auto CoarseCells = utils_ground_nav_volume::Get_WalkableCellCount(_CoarseVolume);
        auto FineCells = utils_ground_nav_volume::Get_WalkableCellCount(_FineVolume);

        Assert_True(CoarseCells > 0,
            "a slab under the whole volume must produce walkable cells, not an empty field");

        Assert_Equals_Int(FineCells, CoarseCells,
            f"the two tilings must rasterize the same walkable set, got {CoarseCells} coarse and {FineCells} fine");

        // Equality above would hold just as well if seam derivation had produced nothing on either
        // side, which is the failure this pair of assertions exists to separate out.
        auto CoarseSeams = utils_ground_nav_volume::Get_SeamPortalCount(_CoarseVolume);
        auto FineSeams = utils_ground_nav_volume::Get_SeamPortalCount(_FineVolume);

        Assert_True(CoarseSeams > 0,
            "a multi-tile field over continuous ground must derive seam portals");
        Assert_True(FineSeams > CoarseSeams,
            f"a finer tiling has strictly more seams to cross, got {CoarseSeams} coarse and {FineSeams} fine");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_FloorBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_FloorBody) && utils_jolt_body::Get_IsBodyAdded(_FloorBody));
    }

    UFUNCTION()
    private void Check_BothCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CoarseCompletions >= 1 && _FineCompletions >= 1);
    }

    //------------------------------------------------------------------------
    // Delegates
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnCoarseCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _CoarseCompletions += 1;
        _CoarseResult = InResult;
    }

    UFUNCTION()
    private void OnFineCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _FineCompletions += 1;
        _FineResult = InResult;
    }
}
