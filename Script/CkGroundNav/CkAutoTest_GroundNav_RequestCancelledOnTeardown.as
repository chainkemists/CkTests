// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: A BUILD CANCELS WHEN ITS VOLUME DIES
//============================================================================
//
// FProcessor_GroundNavVolume_CancelPendingRequests (FGroup_EndPlay) has two
// populations to answer for, and this pins the one nothing else reaches: the
// IN-FLIGHT build. Request_Build's delegate does not stay in the queue - the
// drain moves it onto FFragment_GroundNavVolume_BuildState::_PendingRequest,
// where it rides the multi-tick bake. From that moment the queue is empty, so
// ck::request::FireCancelledForPending has nothing to fire and the only thing
// standing between a destroyed volume and a caller waiting forever is
// _PendingRequest.TryFireCompletion(Failed_Cancelled).
//
//   1. A Static JoltBody slab is the only geometry, exactly as the sibling
//      bake test uses, so the build has real world to read.
//   2. Auto-build is disabled, so the build that gets cancelled is the one
//      this test asked for and not one that happened at composition.
//   3. ProbeBudgetPerTick = 1. The budget gates whether the NEXT TILE starts,
//      so a budget of one bakes exactly one tile per tick; over the 4x4 tile
//      lattice below that is sixteen ticks of building. At the default budget
//      the whole field bakes inside a single slice and there is no in-flight
//      build left to cancel by the time the next frame arrives.
//   4. Destroy the volume on the very next frame - the sequencer advances an
//      action step on the FOLLOWING tick, so this lands one frame after the
//      request and some fourteen tiles short of completion.
//   5. Exactly once, with Failed_Cancelled. Once matters as much as the
//      result: both arms of the cancel processor run in that same EndPlay
//      pass, and a delegate left in both would report twice.
//
// Isolated Y band: 90000 - free per a census of every numeric literal under
// CkTests/Script. Nearest neighbours are 87000 and 93000, both far clear of
// this fixture's 700uu floor.
//============================================================================

class UCk_AutoTest_GroundNav_RequestCancelledOnTeardown : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle _VolumeAsHandle;

    private FVector _Centre = FVector(0.0, 90000.0, 0.0);
    private FVector _FloorHalfExtents = FVector(700.0, 700.0, 50.0);
    private FVector _VolumeHalfExtents = FVector(500.0, 500.0, 200.0);

    private int32 _Completions = 0;
    private ECk_Request_OperationResult _LastResult = ECk_Request_OperationResult::Succeeded;
    private bool _OwnerWasTheVolume = false;

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

        // 250uu tiles over a 1000uu volume: 4x4 tiles, and at one tile a tick the build cannot
        // possibly have finished by the time the next step runs.
        auto Config = FCk_GroundNav_BakeConfig(25.0f, 10.0f);
        Config.Set_TileSizeUu(250.0f);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(FCk_ShapeCapsule_Dimensions(70.0f, 20.0f)));
        Profile.Set_LedgeSensitivity(0.0f);

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(
            FBox(_Centre - _VolumeHalfExtents, _Centre + _VolumeHalfExtents), Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        VolumeParams.Set_ProbeBudgetPerTick(1);

        _Volume = utils_ground_nav_volume::Add(VolumeEntity, VolumeParams);
        _VolumeAsHandle = FCk_Handle(_Volume);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid volume handle");

        Add_Step_WaitUntil( "the floor's static body joins the Jolt world", n"Check_FloorBodyAdded");
        Add_Step(           "request the bake",                            n"Step_RequestBuild");
        Add_Step(           "destroy the volume mid-build",                n"Step_AssertBuilding_Destroy");
        Add_Step_WaitFrames("settle past the whole destruction pipeline",  5);
        Add_Step(           "assert the build reported back as cancelled", n"Step_AssertCancelled");

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
    private void Step_AssertBuilding_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Both halves of the premise. A volume that is no longer building has nothing in flight to
        // cancel, and a delegate that already fired would make the final assertion pass for the
        // wrong reason.
        Assert_True(utils_ground_nav_volume::Get_IsBuilding(_Volume),
            "the build must still be underway one frame after the request");
        Assert_Equals_Int(_Completions, 0,
            "the completion delegate must not have fired while the build is still running");
        Assert_False(utils_ground_nav_volume::Get_IsBuilt(_Volume),
            "nothing is published while the first build is still running");

        utils_entity_lifetime::Request_DestroyEntity(_VolumeAsHandle);
    }

    UFUNCTION()
    private void Step_AssertCancelled(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1,
            "a cancelled build's completion delegate must fire exactly once");

        Assert_True(_LastResult == ECk_Request_OperationResult::Failed_Cancelled,
            f"a build whose volume is destroyed under it must complete with Failed_Cancelled (got {_LastResult})");

        Assert_True(_OwnerWasTheVolume,
            "cancellation must report the volume entity as the request's owner");
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

    //------------------------------------------------------------------------
    // Delegates
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Completions += 1;
        _LastResult = InResult;

        // Recorded rather than asserted here: the owner only means anything alongside the fire count,
        // and an assertion raised from a delegate names no step.
        _OwnerWasTheVolume = InRequestOwner == _VolumeAsHandle;
    }
}
