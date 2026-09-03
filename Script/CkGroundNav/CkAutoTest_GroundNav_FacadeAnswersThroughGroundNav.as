// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: THE FACADE ANSWERS THROUGH GROUND NAV
//============================================================================
//
// The provider-neutral surface and the GroundNav bake had only ever been
// exercised apart: the volume tests drive the bake and read the volume's own
// getters, and the NavSurface tests ask the facade while Recast answers. The
// wiring in between - a world selecting GroundNav, the adapter finding the
// field that world published, and a neutral query coming back with the right
// numbers - had never been walked in a live world.
//
// The fixture is the volume test's, deliberately: one Static JoltBody slab
// whose TOP sits at the volume's mid height, auto-build disabled so the bake
// waited on is the one asked for. That makes the expected surface Z a known
// number rather than something read back from the thing under test.
//
// Two probes, because a facade that answered Success everywhere and one that
// answered nothing would each satisfy half of this on its own:
//   - above the slab: Success, and the Z it hands back is the slab's top.
//   - far outside every field: NoSurface. The adapter falls back to the
//     world's first field when no field's bounds contain the point, so this
//     still reaches a built field - it just finds no cell there, which is
//     what separates NoSurface from Unbuilt and NoProvider.
//
// The query carries its own search box so the expectation does not move with
// the project's nav settings.
//
// The provider is per world and every other NavSurface test in this map reads
// it, so this puts back whatever was selected before as soon as the answers
// are in hand, and asserts on the captured copies afterwards.
//
// Isolated Y band: 118000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_FacadeAnswersThroughGroundNav : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;

    private FVector _Centre = FVector(0.0, 118000.0, 0.0);
    private FVector _FloorHalfExtents = FVector(700.0, 700.0, 50.0);
    private FVector _VolumeHalfExtents = FVector(500.0, 500.0, 200.0);

    // The slab is placed so its top face lands on the volume's mid height, which is the Z a
    // projection onto it must answer with.
    private float _ExpectedSurfaceZ = 0.0;

    // The bake's vertical quantum is 10uu (BakeConfig cell height), so the rasterized surface can
    // sit one quantum off the true face. Anything tighter would be asserting the voxel grid's
    // phase rather than the projection.
    private const float SurfaceZToleranceUu = 15.0;

    // Horizontal reach of 100uu is four cells at the 25uu cell size - enough to find the slab under
    // the probe, far too little to reach anything else. 300uu of vertical reach covers the drop
    // from the probe to the slab with room to spare.
    private FVector _SearchHalfExtents = FVector(100.0, 100.0, 300.0);

    // Well above the slab, well inside the volume: a projection that ignored its own search volume
    // and one that read the wrong field would both miss this.
    private FVector _FloorProbe = FVector(0.0, 118000.0, 150.0);

    // Outside every volume any autotest in this map bakes, on every axis.
    private FVector _VoidProbe = FVector(250000.0, 250000.0, 250000.0);

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastResult = ECk_Request_OperationResult::Failed;

    private ECk_NavSurface_Provider _ProviderWhileQuerying = ECk_NavSurface_Provider::Recast;
    private FCk_NavSurface_ProjectionResult _FloorResult;
    private FCk_NavSurface_ProjectionResult _VoidResult;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

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

        auto VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(25.0f, 10.0f);
        Config.Set_TileSizeUu(500.0f);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(FCk_ShapeCapsule_Dimensions(70.0f, 20.0f)));
        Profile.Set_LedgeSensitivity(0.0f);

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(
            FBox(_Centre - _VolumeHalfExtents, _Centre + _VolumeHalfExtents), Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _Volume = utils_ground_nav_volume::Add(VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid volume handle");

        Add_Step_WaitUntil("the floor's static body joins the Jolt world", n"Check_FloorBodyAdded");
        Add_Step(          "request the bake",                             n"Step_RequestBuild");
        Add_Step_WaitUntil("the bake reports back to its caller",          n"Check_BakeCompleted");
        Add_Step(          "ask the facade with GroundNav selected",       n"Step_QueryThroughFacade");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RequestBuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
    }

    UFUNCTION()
    private void Step_QueryThroughFacade(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_BuildCompletions, 1, "the completion delegate must fire exactly once");
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            f"a bake that finished must complete with Succeeded (got {_LastResult})");

        // The field reaches the adapter's registry as part of publishing, so a volume that is not
        // built is a world the facade has nothing to answer from.
        Assert_True(utils_ground_nav_volume::Get_IsBuilt(_Volume),
            "the volume must publish its field before the facade can be asked about it");

        const auto ProviderBefore = utils_nav_surface::Get_Provider();

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);

        _ProviderWhileQuerying = utils_nav_surface::Get_Provider();

        auto FloorQuery = FCk_NavSurface_ProjectionQuery(_FloorProbe);
        FloorQuery.Set_SearchHalfExtents(_SearchHalfExtents);
        FloorQuery.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

        _FloorResult = utils_nav_surface::Try_ProjectPoint(FloorQuery);

        auto VoidQuery = FCk_NavSurface_ProjectionQuery(_VoidProbe);
        VoidQuery.Set_SearchHalfExtents(_SearchHalfExtents);
        VoidQuery.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

        _VoidResult = utils_nav_surface::Try_ProjectPoint(VoidQuery);

        // Handed back before anything below can report, so the tests that follow in this map see the
        // provider they expect no matter how this one ends.
        utils_nav_surface::Request_SetProvider(ProviderBefore);

        DoAssert_Answers();
    }

    //------------------------------------------------------------------------
    // Assertions
    //------------------------------------------------------------------------

    private void DoAssert_Answers()
    {
        // First, because every answer below is meaningless if the world quietly stayed on its
        // default provider - Recast would then be agreeing with GroundNav about nothing at all.
        Assert_True(_ProviderWhileQuerying == ECk_NavSurface_Provider::GroundNav,
            f"the world must report the provider it was told to use (got {_ProviderWhileQuerying})");

        Assert_True(_FloorResult.Get_Status() == ECk_NavSurface_QueryStatus::Success,
            f"a point above the baked slab must project onto it - got {_FloorResult.Get_Status()}");

        const auto ProjectedZ = _FloorResult.Get_Location().Z;

        Assert_True(Math::Abs(ProjectedZ - _ExpectedSurfaceZ) <= SurfaceZToleranceUu,
            f"the projection must land on the slab's top face at {_ExpectedSurfaceZ} - got {ProjectedZ}, further than {SurfaceZToleranceUu}uu away");

        // Success everywhere is the failure this half exists to catch. NoSurface exactly, not merely
        // "not Success": the field is built, so Unbuilt is ruled out; no filter is supplied, so
        // Blocked is; and the provider answered the probe above, so NoProvider is.
        Assert_True(_VoidResult.Get_Status() == ECk_NavSurface_QueryStatus::NoSurface,
            f"nothing walkable exists anywhere near {_VoidProbe}, so the facade must answer NoSurface - got {_VoidResult.Get_Status()}");

        Assert_True(_VoidResult.Get_Location() == FVector::ZeroVector,
            f"a failed projection must not hand back a location - got {_VoidResult.Get_Location()}");
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
    private void Check_BakeCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BuildCompletions >= 1);
    }

    //------------------------------------------------------------------------
    // Delegates
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _BuildCompletions += 1;
        _LastResult = InResult;
    }
}
