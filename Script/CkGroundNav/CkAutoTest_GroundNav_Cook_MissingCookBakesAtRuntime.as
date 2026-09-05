// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A MISSING COOK BAKES AT RUNTIME
//============================================================================
//
// The cooked/runtime fallback is STATE-SELECTED, and this pin drives the two
// states a PIE world can actually reach: a volume that authored a cook key
// nothing was ever cooked for, and a volume that authored none at all.
//
//   MissingCook - a key is set and no index asset exists at the convention
//                 path for {this level package, that key}. Absence is LEGAL,
//                 so the volume bakes at runtime and answers queries.
//   RuntimeOnly - no key, so nothing was ever looked up and nothing is ever
//                 written. This is what every gym and test volume is.
//
// WHAT MAKES IT EVIDENCE. A status on its own would be satisfied by a function
// returning a constant, so the keyed volume is also asserted BUILT and a
// projection is taken on its ground: the claim is that naming a cook nobody
// baked costs the volume nothing, not merely that the status reads a word. The
// keyless volume beside it is what stops MissingCook being read as "the status
// this world reports" rather than as this volume's own answer - same world,
// same slab, same tick, different key.
//
// A word on what this pin cannot reach: Cooked and StaleCook both need an index
// ASSET, and writing one is the cook's job in an UncookedOnly module. Those two
// are pinned headless in Test_GroundNav_CookedAssets.cpp against assets built in
// a transient package, which is exactly why the load path was split out of the
// world.
//
// FIXTURE. One Static JoltBody slab whose top sits at Z 0, overhanging BOTH
// volumes by 200uu on every horizontal side so no cliff edge exists inside
// either field. A box shape is convex and therefore closed - an open mesh would
// trip the bake's OPEN COLLISION warning, and the harness escalates a Warning
// into a failure. Auto-build is left ON: arming the first build is precisely
// what MissingCook is supposed to leave untouched.
//
// The provider is per world and every other fixture in this map reads it, so
// the previous selection is captured before the swap and handed back both when
// this test concludes AND in DoEndPlay - every exit path, including the engine
// TimeLimit one, must put the world back.
//
// Isolated Y band: 148000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Cook_MissingCookBakesAtRuntime : UCk_AutoTest_Base
{
    // Two 2x2 volumes at the default probe budget, plus the surface settling.
    // Deliberately slack: a contract that expires on the harness's anonymous
    // TimesUp names nothing, and every wait below carries its own budget so it
    // fails on its own condition.
    default _TimeoutSeconds = 120.0f;

    //------------------------------------------------------------------------
    // Fixture geometry - two 2x2 lattices at 400uu tiles, side by side in X
    //------------------------------------------------------------------------

    private const float BandY = 148000.0;

    private const float VolumeHalfX = 400.0;
    private const float VolumeHalfY = 400.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float KeyedCentreX = -1000.0;
    private const float KeylessCentreX = 1000.0;

    // Overhangs BOTH volumes by 200uu on every horizontal side, so neither
    // volume's interior contains a slab edge for the ledge filter to find.
    private const float SlabHalfX = 1600.0;
    private const float SlabHalfY = 600.0;
    private const float SlabHalfZ = 50.0;

    private const float SurfaceZ = 0.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 400.0;

    private const float AgentRadius = 42.0;
    private const float ProfileHalfHeightUu = 96.0;

    private const FVector ProbeHalfExtents = FVector(10.0, 10.0, 20.0);

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 3600;
    private const int32 SurfaceFrameBudget = 1800;

    //------------------------------------------------------------------------
    // Fixture handles
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _KeyedVolumeEntity;
    private FCk_Handle _KeylessVolumeEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _KeyedVolume;
    private FCk_Handle_GroundNavVolume _KeylessVolume;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    //------------------------------------------------------------------------
    // Episode bookkeeping - reported, so the log says what each volume answered
    //------------------------------------------------------------------------

    private ECk_GroundNav_CookStatus _KeyedStatus = ECk_GroundNav_CookStatus::Cooked;
    private ECk_GroundNav_CookStatus _KeylessStatus = ECk_GroundNav_CookStatus::Cooked;
    private float _ProbeZ = 0.0f;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage the floor and the two volumes",            n"Step_BuildFixture");
        Add_Step_WaitUntil("the floor reaches the Jolt static world",        n"Check_FloorBodyAdded",  BodyFrameBudget);
        Add_Step_WaitUntil("both fields report themselves built",            n"Check_FieldsBuilt",     BuildFrameBudget);
        Add_Step(          "put the world on the GroundNav provider",        n"Step_SelectProvider");
        Add_Step_WaitUntil("the nav surface settles at Ready",               n"Check_SurfaceSettled",  SurfaceFrameBudget);
        Add_Step(          "the keyed volume names a cook nobody baked",     n"Step_AssertMissingCook");
        Add_Step(          "the keyless volume names no cook at all",        n"Step_AssertRuntimeOnly");
        Add_Step(          "report what each volume answered",               n"Step_Report");
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

        // The key names a level/volume pair nothing has ever cooked, which is the whole point: the
        // convention path resolves to no asset, and the volume must bake anyway.
        _KeyedVolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _KeyedVolumeEntity.Request_OverrideToSelf();

        auto KeyedParams = Make_VolumeParams(KeyedCentreX, n"CkTests_GroundNav_Cook_NeverBaked");
        _KeyedVolume = utils_ground_nav_volume::Add(_KeyedVolumeEntity, KeyedParams);

        _KeylessVolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _KeylessVolumeEntity.Request_OverrideToSelf();

        auto KeylessParams = Make_VolumeParams(KeylessCentreX, FName());
        _KeylessVolume = utils_ground_nav_volume::Add(_KeylessVolumeEntity, KeylessParams);

        Assert_True(ck::IsValid(_KeyedVolume) && ck::IsValid(_KeylessVolume),
            "Add() must return a valid GroundNav volume handle for both volumes");
    }

    UFUNCTION()
    private void Check_FloorBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_jolt_body::Get_IsBodyAdded(_FloorBody));
    }

    UFUNCTION()
    private void Check_FieldsBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_ground_nav_volume::Get_IsBuilt(_KeyedVolume) &&
                utils_ground_nav_volume::Get_IsBuilt(_KeylessVolume));
    }

    UFUNCTION()
    private void Step_SelectProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
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
    // The claims
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertMissingCook(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _KeyedStatus = utils_ground_nav_volume::Get_CookStatus(_KeyedVolume);

        Assert_True(_KeyedStatus == ECk_GroundNav_CookStatus::MissingCook,
            f"a volume carrying a cook key that resolves to no index asset reports MissingCook - the key was read, the lookup ran, and nothing was there (got {_KeyedStatus})");

        // The half that makes the status worth having: a missing cook costs the volume nothing.
        Assert_True(utils_ground_nav_volume::Get_IsBuilt(_KeyedVolume),
            "MissingCook must leave the runtime bake armed exactly as it was, so the volume publishes ground of its own");

        const auto Probe = Project(FVector(KeyedCentreX, BandY, SurfaceZ));
        const auto ProbeStatus = Probe.Get_Status();

        Assert_True(ProbeStatus == ECk_NavSurface_QueryStatus::Success,
            f"the runtime bake published real ground, so a projection inside the keyed volume answers (got {ProbeStatus})");

        _ProbeZ = float32(Probe.Get_Location().Z);

        Assert_True(Math::Abs(_ProbeZ - float32(SurfaceZ)) < 1.0f,
            f"and it answers on the slab's own top face rather than somewhere the search wandered to (got Z={_ProbeZ})");
    }

    UFUNCTION()
    private void Step_AssertRuntimeOnly(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _KeylessStatus = utils_ground_nav_volume::Get_CookStatus(_KeylessVolume);

        // The POSITIVE the status rests on. A volume that never got set up would also report
        // RuntimeOnly, and a fixture reading that as "it authored no key" would pin nothing.
        Assert_True(utils_ground_nav_volume::Get_IsBuilt(_KeylessVolume),
            "the keyless volume must have published its own field, or its status is being read off a volume that never reached Setup");

        Assert_True(_KeylessStatus == ECk_GroundNav_CookStatus::RuntimeOnly,
            f"a volume that authored no cook key is runtime-only by definition: nothing is looked up for it and nothing is ever written (got {_KeylessStatus})");

        Assert_True(_KeylessStatus != _KeyedStatus,
            f"two volumes in one world, one tick apart, differing only in the key they authored must not report the same provenance (both read {_KeylessStatus})");
    }

    //------------------------------------------------------------------------
    // Report
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Keyed = _KeyedStatus;
        const auto Keyless = _KeylessStatus;
        const auto ProbeZ = _ProbeZ;

        ck::nav::Display(f"[GROUNDNAV-COOK] keyed={Keyed} keyless={Keyless} | runtime bake answered at Z={ProbeZ}");
    }

    //------------------------------------------------------------------------
    // Fixture helpers
    //------------------------------------------------------------------------

    private FCk_Fragment_GroundNavVolume_ParamsData Make_VolumeParams(float InCentreX, FName InCookKey)
    {
        auto Config = FCk_GroundNav_BakeConfig(float32(CellSizeUu), float32(CellHeightUu));
        Config.Set_TileSizeUu(float32(TileSizeUu));

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(float32(ProfileHalfHeightUu), float32(AgentRadius))));
        // The slab's own edges lie OUTSIDE both volumes, but each field is clipped to its volume, so
        // the ledge filter would otherwise demote the whole perimeter.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(InCentreX - VolumeHalfX, BandY - VolumeHalfY, VolumeFloorZ),
            FVector(InCentreX + VolumeHalfX, BandY + VolumeHalfY, VolumeCeilingZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_CookKey(InCookKey);

        return VolumeParams;
    }

    private FCk_NavSurface_ProjectionResult Project(FVector InPoint)
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(ProbeHalfExtents);

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
    // every later fixture in this map reads, and the slab would otherwise stay in the Jolt static world
    // for the rest of the lane, handing every later bake ground it did not stage.
    private void Teardown()
    {
        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_KeyedVolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_KeyedVolumeEntity);
            _KeyedVolumeEntity = FCk_Handle();
        }

        if (ck::IsValid(_KeylessVolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_KeylessVolumeEntity);
            _KeylessVolumeEntity = FCk_Handle();
        }

        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}
