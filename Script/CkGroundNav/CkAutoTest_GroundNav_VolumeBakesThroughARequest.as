// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A VOLUME BAKES THROUGH ITS REQUEST
//============================================================================
//
// The volume path end to end, driven the way a consumer drives it, because
// until this ran the ECS shell had only ever been compiled: the processors
// registered and scheduled correctly and no bake had ever gone through them.
//
//   1. A Static JoltBody slab is the only geometry, so the bake has real
//      world to read rather than a hand-authored box list.
//   2. Auto-build is disabled, so the bake this test waits on is the one it
//      asked for and not one that happened at composition.
//   3. Request_Build, then wait for the completion delegate - which fires
//      when the BUILD ends, not when the request was accepted. That gap is
//      the whole reason the request carries the delegate across ticks.
//   4. A second build must advance the epoch, because a reader compares
//      epochs to learn its field is stale and a counter that stood still
//      would tell every one of them it was current.
//
// The tile size is deliberately smaller than the volume, so the field is
// several tiles and the seam derivation runs too.
//
// Isolated Y band: 64000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_GroundNav_VolumeBakesThroughARequest : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;

    private FVector _Centre = FVector(0.0, 64000.0, 0.0);
    private FVector _FloorHalfExtents = FVector(700.0, 700.0, 50.0);
    private FVector _VolumeHalfExtents = FVector(500.0, 500.0, 200.0);

    private int32 _BuildCompletions = 0;
    private int64 _EpochAfterFirstBuild = 0;
    private ECk_Request_OperationResult _LastResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // The slab's TOP sits at the volume's mid height, so there is ground to find rather than a
        // volume of empty air that would bake successfully and prove nothing.
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
        Assert_True(utils_ground_nav_volume::Has(FCk_Handle(_Volume)),
            "the volume entity must carry the feature Add() composed");
        Assert_False(utils_ground_nav_volume::Get_IsBuilt(_Volume),
            "nothing is built before a build is asked for");

        Add_Step_WaitUntil("the floor's static body joins the Jolt world", n"Check_FloorBodyAdded");
        Add_Step(          "request the bake",                             n"Step_RequestBuild");
        Add_Step_WaitUntil("the bake reports back to its caller",          n"Check_BakeCompleted");
        Add_Step(          "assert the bake, then request another",        n"Step_AssertBake_RequestAgain");
        Add_Step_WaitUntil("the rebuild reports back",                     n"Check_RebuildCompleted");
        Add_Step(          "assert the rebuild advanced the epoch",        n"Step_AssertRebuild");

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
    private void Step_AssertBake_RequestAgain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_BuildCompletions, 1, "the completion delegate must fire exactly once");
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            f"a bake that finished must complete with Succeeded (got {_LastResult})");

        Assert_True(utils_ground_nav_volume::Get_IsBuilt(_Volume),
            "the volume must publish its field once the build completes");
        Assert_False(utils_ground_nav_volume::Get_IsBuilding(_Volume),
            "a finished build must stop reporting itself as building");

        _EpochAfterFirstBuild = utils_ground_nav_volume::Get_BuildEpoch(_Volume);

        Assert_True(_EpochAfterFirstBuild >= 1,
            f"the build epoch must advance past zero, got {_EpochAfterFirstBuild}");

        utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
    }

    UFUNCTION()
    private void Step_AssertRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_BuildCompletions, 2, "the second build must report back too");
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            f"the rebuild must also complete with Succeeded (got {_LastResult})");

        Assert_True(utils_ground_nav_volume::Get_IsBuilt(_Volume),
            "a rebuild leaves the volume built");

        // The number a reader compares against to learn its field is behind. An epoch that stood
        // still would tell every one of them it was current.
        auto EpochNow = utils_ground_nav_volume::Get_BuildEpoch(_Volume);

        Assert_True(EpochNow > _EpochAfterFirstBuild,
            f"the rebuild must advance the epoch past {_EpochAfterFirstBuild}, got {EpochNow}");
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

    UFUNCTION()
    private void Check_RebuildCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BuildCompletions >= 2);
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
