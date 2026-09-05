// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A DUPLICATE COOK KEY IS REFUSED
//============================================================================
//
// A cooked field is keyed on {the level package the cook ran over, the volume's
// authored cook key}, so two volumes in one world carrying the SAME key name
// one cooked field between them: each would write over the other's tiles and
// read back whichever landed last, and nothing downstream could tell which
// volume the ground came from. That is refused where the params are judged, and
// again where a build is asked for.
//
// This pin drives the second volume, and it drives BOTH guards:
//
//   The admission guard - the duplicate is never admitted, so it never enters
//   the world-field registry and never arms a build. Get_IsBuilt stays false.
//   The build guard - a Request_Build raised on it completes Failed, rather
//   than sitting forever or quietly baking a field nothing may read.
//
// THE ORDER IS DELIBERATE. The first volume is staged, built and left alone
// BEFORE the second is created, so which of the two is the duplicate is decided
// by the fixture rather than by whatever order the setup processor happened to
// visit them in. The first volume being asserted still built afterwards is the
// other half of the claim: refusing the second must cost the first nothing.
//
// The build request is raised in the same step the duplicate is created. The
// request drain excludes a volume that still carries NeedsSetup, so the request
// parks until Setup has run and refused it, and the completion is what says the
// refusal reached the caller.
//
// A THIRD volume drives the other cook-key admission guard, at both of the same
// sites: a cooked field index names ONE field for a volume, so a volume that
// authors a cook key AND a profile variant would have no field under the
// variant's tag - and a query naming that tag is answered from nothing rather
// than from the default's ground, which would walk an agent up a step its own
// profile cannot climb. It carries its own key, so the duplicate guard above
// (which is judged first) cannot be what refuses it.
//
// ALL THREE GUARDS ENSURE, which is what makes them loud, so the actor wrapper
// below registers their message substrings - the automation framework would
// otherwise auto-fail the run on exactly the diagnostics this test exists to
// produce.
//
// FIXTURE. One Static JoltBody slab whose top sits at Z 0, overhanging both
// volumes by 200uu on every horizontal side so no cliff edge exists inside
// either field. A box shape is convex and therefore closed - an open mesh would
// trip the bake's OPEN COLLISION warning, and the harness escalates a Warning
// into a failure. No provider swap: nothing here is projected, so this fixture
// changes no world state that a later one in the map would read.
//
// Isolated Y band: 150000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_Cook_DuplicateCookKeyIsRefused : UCk_AutoTest_Base
{
    // One 2x2 volume at the default probe budget, plus the parked request
    // draining. Deliberately slack: a contract that expires on the harness's
    // anonymous TimesUp names nothing, and every wait below carries its own
    // budget so it fails on its own condition.
    default _TimeoutSeconds = 120.0f;

    //------------------------------------------------------------------------
    // Fixture geometry - two 2x2 lattices at 400uu tiles, side by side in X
    //------------------------------------------------------------------------

    private const float BandY = 150000.0;

    private const float VolumeHalfX = 400.0;
    private const float VolumeHalfY = 400.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float FirstCentreX = -1000.0;
    private const float SecondCentreX = 1000.0;
    private const float ThirdCentreX = 0.0;

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

    // The one name both volumes claim. Nothing is ever cooked for it - what is
    // under test is the clash, which is decided before any lookup runs.
    private const FName SharedCookKey = n"CkTests_GroundNav_Cook_Contested";

    // The third volume's own key, so nothing it does is answered by the duplicate
    // guard. What refuses it is the profile variant it authors beside the key.
    private const FName VariantCookKey = n"CkTests_GroundNav_Cook_Variants";

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 600;
    private const int32 BuildFrameBudget = 3600;
    private const int32 RefusalFrameBudget = 1800;

    //------------------------------------------------------------------------
    // Fixture handles
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _FirstVolumeEntity;
    private FCk_Handle _SecondVolumeEntity;
    private FCk_Handle _ThirdVolumeEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _FirstVolume;
    private FCk_Handle_GroundNavVolume _SecondVolume;
    private FCk_Handle_GroundNavVolume _ThirdVolume;

    //------------------------------------------------------------------------
    // Episode bookkeeping
    //------------------------------------------------------------------------

    private int32 _RefusedBuildCompletions = 0;
    private ECk_Request_OperationResult _LastRefusedBuildResult = ECk_Request_OperationResult::Succeeded;

    private int32 _VariantBuildCompletions = 0;
    private ECk_Request_OperationResult _LastVariantBuildResult = ECk_Request_OperationResult::Succeeded;

    private ECk_GroundNav_CookStatus _FirstStatus = ECk_GroundNav_CookStatus::Cooked;
    private ECk_GroundNav_CookStatus _SecondStatus = ECk_GroundNav_CookStatus::Cooked;
    private ECk_GroundNav_CookStatus _ThirdStatus = ECk_GroundNav_CookStatus::Cooked;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        Add_Step(          "stage the floor and the first volume",           n"Step_BuildFixture");
        Add_Step_WaitUntil("the floor reaches the Jolt static world",        n"Check_FloorBodyAdded",  BodyFrameBudget);
        Add_Step_WaitUntil("the first field reports itself built",           n"Check_FirstBuilt",      BuildFrameBudget);
        Add_Step(          "stage a second volume claiming the same key",    n"Step_StageDuplicate");
        Add_Step_WaitUntil("the duplicate's build request is answered",      n"Check_BuildRefused",    RefusalFrameBudget);
        Add_Step(          "the duplicate never became ground",              n"Step_AssertRefused");
        Add_Step(          "and the first volume is untouched",              n"Step_AssertFirstIntact");
        Add_Step(          "stage a volume with a key AND a variant",        n"Step_StageVariantVolume");
        Add_Step_WaitUntil("that volume's build request is answered",        n"Check_VariantBuildRefused", RefusalFrameBudget);
        Add_Step(          "a cooked field carries one profile",             n"Step_AssertVariantRefused");
        Add_Step(          "report what each volume answered",               n"Step_Report");
        Add_Step(          "tear the fixture down",                          n"Step_Cleanup");

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

        _FirstVolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _FirstVolumeEntity.Request_OverrideToSelf();

        auto FirstParams = Make_VolumeParams(FirstCentreX);
        _FirstVolume = utils_ground_nav_volume::Add(_FirstVolumeEntity, FirstParams);

        Assert_True(ck::IsValid(_FirstVolume), "Add() must return a valid GroundNav volume handle");
    }

    UFUNCTION()
    private void Check_FloorBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_jolt_body::Get_IsBodyAdded(_FloorBody));
    }

    UFUNCTION()
    private void Check_FirstBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_ground_nav_volume::Get_IsBuilt(_FirstVolume));
    }

    //------------------------------------------------------------------------
    // The duplicate
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_StageDuplicate(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _SecondVolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _SecondVolumeEntity.Request_OverrideToSelf();

        auto SecondParams = Make_VolumeParams(SecondCentreX);
        _SecondVolume = utils_ground_nav_volume::Add(_SecondVolumeEntity, SecondParams);

        Assert_True(ck::IsValid(_SecondVolume),
            "the duplicate must be a valid volume handle - it is refused at ADMISSION, which is not the same as never being composed");

        // Raised now rather than after Setup has run: the request drain excludes a volume still
        // carrying NeedsSetup, so this parks until the refusal has happened and then drains against
        // the build guard. The completion is what says the refusal reached the caller.
        utils_ground_nav_volume::Request_Build(_SecondVolume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnRefusedBuildCompleted"));
    }

    UFUNCTION()
    private void OnRefusedBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RefusedBuildCompletions += 1;
        _LastRefusedBuildResult = InResult;
    }

    UFUNCTION()
    private void Check_BuildRefused(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RefusedBuildCompletions >= 1);
    }

    //------------------------------------------------------------------------
    // The claims
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertRefused(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastRefusedBuildResult == ECk_Request_OperationResult::Failed,
            f"a build asked of a volume whose cook key another volume already answers to must complete Failed - the caller's intent cannot hold, and retrying will not change that (got {_LastRefusedBuildResult})");

        Assert_True(!utils_ground_nav_volume::Get_IsBuilt(_SecondVolume),
            "the duplicate must never have published a field: it was refused at admission, so no build was ever armed and the refused request armed none either");

        _SecondStatus = utils_ground_nav_volume::Get_CookStatus(_SecondVolume);

        // A volume that never reached the cook resolution reports the default, which is the honest
        // answer for one whose key was never read: nothing was looked up, and nothing was written.
        Assert_True(_SecondStatus == ECk_GroundNav_CookStatus::RuntimeOnly,
            f"a volume refused before its cook key was ever resolved reports RuntimeOnly, because no cooked field was looked for on its behalf (got {_SecondStatus})");
    }

    UFUNCTION()
    private void Step_AssertFirstIntact(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // The other half of the claim. Refusing the duplicate must cost the volume that legitimately
        // holds the key nothing, or the guard has traded one corruption for another.
        Assert_True(utils_ground_nav_volume::Get_IsBuilt(_FirstVolume),
            "the volume that claimed the key first keeps its published field - the refusal is the duplicate's alone");

        _FirstStatus = utils_ground_nav_volume::Get_CookStatus(_FirstVolume);

        Assert_True(_FirstStatus == ECk_GroundNav_CookStatus::MissingCook,
            f"the first volume's key resolved to no index asset, so it baked at runtime and says so (got {_FirstStatus})");
    }

    //------------------------------------------------------------------------
    // The volume that authors a key AND a profile variant
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_StageVariantVolume(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ThirdVolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _ThirdVolumeEntity.Request_OverrideToSelf();

        auto ThirdParams = Make_VolumeParams(ThirdCentreX);
        ThirdParams.Set_CookKey(VariantCookKey);

        // Registered natively by Test_GroundNav_ProfileVariants.cpp, which pins the variant feature
        // over the same tag. WHICH tag it is does not matter here - what is refused is that there is
        // one at all beside a cook key.
        TArray<FCk_GroundNav_ProfileVariant> Variants;
        Variants.Add(FCk_GroundNav_ProfileVariant(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.GroundNav.Profile.Crawler"),
            ThirdParams.Get_Profile()));

        ThirdParams.Set_ProfileVariants(Variants);

        _ThirdVolume = utils_ground_nav_volume::Add(_ThirdVolumeEntity, ThirdParams);

        Assert_True(ck::IsValid(_ThirdVolume),
            "the variant-carrying volume must be a valid volume handle - it is refused at ADMISSION, which is not the same as never being composed");

        utils_ground_nav_volume::Request_Build(_ThirdVolume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnVariantBuildCompleted"));
    }

    UFUNCTION()
    private void OnVariantBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _VariantBuildCompletions += 1;
        _LastVariantBuildResult = InResult;
    }

    UFUNCTION()
    private void Check_VariantBuildRefused(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_VariantBuildCompletions >= 1);
    }

    UFUNCTION()
    private void Step_AssertVariantRefused(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastVariantBuildResult == ECk_Request_OperationResult::Failed,
            f"a build asked of a volume carrying both a cook key and a profile variant must complete Failed - the index names one field per volume, so the variant's tag would be answered from nothing (got {_LastVariantBuildResult})");

        Assert_True(!utils_ground_nav_volume::Get_IsBuilt(_ThirdVolume),
            "the variant-carrying volume must never have published a field: it was refused at admission, so no build was ever armed and the refused request armed none either");

        _ThirdStatus = utils_ground_nav_volume::Get_CookStatus(_ThirdVolume);

        Assert_True(_ThirdStatus == ECk_GroundNav_CookStatus::RuntimeOnly,
            f"a volume refused before its cook key was ever resolved reports RuntimeOnly, because no cooked field was looked for on its behalf (got {_ThirdStatus})");
    }

    //------------------------------------------------------------------------
    // Report
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto First = _FirstStatus;
        const auto Second = _SecondStatus;
        const auto Third = _ThirdStatus;
        const auto Completions = _RefusedBuildCompletions;
        const auto Result = _LastRefusedBuildResult;
        const auto VariantCompletions = _VariantBuildCompletions;
        const auto VariantResult = _LastVariantBuildResult;

        ck::nav::Display(f"[GROUNDNAV-COOK] first={First} duplicate={Second} variant={Third} | refused build completions={Completions} result={Result} | variant build completions={VariantCompletions} result={VariantResult}");
    }

    //------------------------------------------------------------------------
    // Fixture helpers
    //------------------------------------------------------------------------

    private FCk_Fragment_GroundNavVolume_ParamsData Make_VolumeParams(float InCentreX)
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
        VolumeParams.Set_CookKey(SharedCookKey);

        return VolumeParams;
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. The slab would otherwise stay in
    // the Jolt static world for the rest of the lane, handing every later bake ground it did not stage.
    private void Teardown()
    {
        if (ck::IsValid(_ThirdVolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_ThirdVolumeEntity);
            _ThirdVolumeEntity = FCk_Handle();
        }

        if (ck::IsValid(_SecondVolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_SecondVolumeEntity);
            _SecondVolumeEntity = FCk_Handle();
        }

        if (ck::IsValid(_FirstVolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FirstVolumeEntity);
            _FirstVolumeEntity = FCk_Handle();
        }

        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}

//============================================================================
// Hand-authored wrapper: every cook-key admission guard this test drives is a
// CK_ENSURE_IF_NOT, so their messages reach the automation framework as errors.
// Registering the substrings stops the run auto-failing on the very diagnostics
// this test is here to produce. The wrapper generator skips a test that
// hand-authors one.
//============================================================================

class ACk_AutoTest_GroundNav_Cook_DuplicateCookKeyIsRefused_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_GroundNav_Cook_DuplicateCookKeyIsRefused;
    default _TimeoutSeconds = 120.0f;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("already carries the cook key");
        Out.Add("already carries its cook key");
        Out.Add("a cooked field carries one profile");
        return Out;
    }
}
