// Language=angelscript

//============================================================================
// CK SCENE NODE — AUTOMATION TEST: CREATE SEEDS THE COMPOSED WORLD
//============================================================================
//
// Asserts SYNCHRONOUSLY, with no wait. Every other SceneNode and SceneNodeTween
// test settles >= 0.25s or waits for tween completion first, so none of them can
// distinguish a correct seed from a wrong seed that the layer-update processor
// repairs a frame later. Adding a settle here silently guts the test.
//
// Parent scale stays uniform: a non-uniform parent scale under a rotated child
// is shear, which FTransform composition does not model.
//============================================================================

class UCk_AutoTest_SceneNode_CreateSeedsComposedWorld : UCk_AutoTest_Base
{
    private const FVector ParentLocation = FVector(400.0f, -250.0f, 75.0f);
    private const FRotator ParentRotation = FRotator(0.0f, 45.0f, 0.0f);
    private const FVector ParentScale = FVector(2.0f, 2.0f, 2.0f);

    private const FVector ChildLocalLocation = FVector(-0.722501f, -47.204372f, 11.581022f);
    private const FRotator ChildLocalRotation = FRotator(0.0f, 180.0f, 0.0f);
    private const FVector ChildLocalScale = FVector(0.011f, 0.914685f, 0.011f);

    private const float32 PositionToleranceCm = 0.1f;
    private const float32 RotationToleranceDeg = 0.1f;
    private const float32 ScaleTolerance = 0.0001f;

    private const int32 SettleFrames = 10;

    private FCk_Handle_Transform ChildTransform;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto ParentWorld = FTransform(ParentRotation, ParentLocation, ParentScale);
        auto ParentTransform = utils_transform::Add(ParentEntity, ParentWorld, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(ParentTransform))
        {
            FinishFailure("Failed to add Transform feature to the bare parent entity");
            return;
        }

        auto ChildLocal = FTransform(ChildLocalRotation, ChildLocalLocation, ChildLocalScale);
        auto ChildSceneNode = utils_scene_node::Create(ParentTransform, ChildLocal);
        if (ck::Is_NOT_Valid(ChildSceneNode))
        {
            FinishFailure("Failed to create the child SceneNode on the bare parent");
            return;
        }

        ChildTransform = ChildSceneNode.As_Transform();
        if (ck::Is_NOT_Valid(ChildTransform))
        {
            FinishFailure("Child SceneNode has no Transform handle");
            return;
        }

        AssertChildIsComposed("Immediately after Create (no wait)");
        if (IsFinished())
        { return; }

        WaitFrames(SettleFrames, n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished())
        { return; }

        // Propagation must agree with the seed, not move it.
        AssertChildIsComposed("After settle (propagation must not move it)");
        if (IsFinished())
        { return; }

        FinishSuccess();
    }

    private void AssertChildIsComposed(const FString& InContext)
    {
        auto ParentWorld = FTransform(ParentRotation, ParentLocation, ParentScale);
        auto ChildLocal = FTransform(ChildLocalRotation, ChildLocalLocation, ChildLocalScale);
        auto ExpectedWorld = ChildLocal * ParentWorld;

        auto ExpectedLoc = ExpectedWorld.GetLocation();
        auto ExpectedRot = ExpectedWorld.GetRotation().Rotator();
        auto ExpectedScale = ExpectedWorld.GetScale3D();

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(ChildTransform);
        auto ActualRot = utils_transform::Get_EntityCurrentRotation(ChildTransform);
        auto ActualScale = utils_transform::Get_EntityCurrentScale(ChildTransform);

        Assert_True(ActualScale.Equals(ExpectedScale, ScaleTolerance),
            f"[{InContext}] child SCALE | expected {ExpectedScale}, got {ActualScale}");
        Assert_True(ActualRot.Equals(ExpectedRot, RotationToleranceDeg),
            f"[{InContext}] child ROTATION | expected {ExpectedRot}, got {ActualRot}");
        Assert_True(ActualLoc.Equals(ExpectedLoc, PositionToleranceCm),
            f"[{InContext}] child LOCATION | expected {ExpectedLoc}, got {ActualLoc}");
    }
}
