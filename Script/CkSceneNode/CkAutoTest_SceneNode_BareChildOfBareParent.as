// Language=angelscript

//============================================================================
// CK SCENE NODE — AUTOMATION TEST: BARE CHILD OF BARE PARENT
//============================================================================
//
// Bedrock test for the layer-update math. Both parent and child are bare ECS
// entities (no actor, no mesh socket) that only carry FFragment_Transform +
// the SceneNode hierarchy. Exercises FProcessor_SceneNode_HandleRequests +
// TProcessor_SceneNode_Update<Layer> in isolation.
//
// If THIS test fails, every other scene-node test breaks too — it pins down
// the basic "Current * ParentWorld" composition and the MarkedDirtyBy / layer
// propagation chain. It must stay green regardless of whatever changes are
// made to anchor-bound (RootComponent / MeshSocket) entity behavior.
//
// Test flow:
//   1. Create a bare parent transform on a fresh entity (Identity).
//   2. utils_scene_node::Create(parent, ChildLocal) — child is a SceneNode
//      whose Transform fragment was seeded from the parent's world. The
//      FTag_SceneNode_RelativeTransformUpdated tag added by AssignLayerByIndex
//      forces TProcessor_SceneNode_Update to compute the initial world.
//   3. Wait a few frames; assert child world == ChildLocal.
//   4. Move + rotate the bare parent. Wait again.
//   5. Assert child world == ChildLocal * ParentWorld.
//============================================================================

class UCk_AutoTest_SceneNode_BareChildOfBareParent : UCk_AutoTest_Base
{
    private const FVector ChildLocalLocation = FVector(150.0f, 0.0f, 50.0f);
    private const FRotator ChildLocalRotation = FRotator(0.0f, 30.0f, 0.0f);
    private const FVector ParentTargetLocation = FVector(800.0f, -200.0f, 100.0f);
    private const FRotator ParentRotationDelta = FRotator(0.0f, 60.0f, 0.0f);

    private const float32 PositionToleranceCm = 1.0f;
    private const float32 RotationToleranceDeg = 1.0f;
    private const float32 PropagationWaitSeconds = 0.25f;

    private FCk_Handle TestEntity;
    private FCk_Handle_Transform ParentTransform;
    private FCk_Handle_Transform ChildTransform;

    private int32 _Step = 0;
    private float32 _WaitElapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        TestEntity = InHandle;

        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        ParentTransform = utils_transform::Add(ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(ParentTransform))
        {
            FinishFailure("Failed to add Transform feature to bare parent entity");
            return;
        }

        auto ChildLocal = FTransform(ChildLocalRotation, ChildLocalLocation, FVector::OneVector);
        auto ChildSceneNode = utils_scene_node::Create(ParentTransform, ChildLocal);
        if (ck::Is_NOT_Valid(ChildSceneNode))
        {
            FinishFailure("Failed to create child SceneNode on bare parent");
            return;
        }

        ChildTransform = ChildSceneNode.As_Transform();
        if (ck::Is_NOT_Valid(ChildTransform))
        {
            FinishFailure("Child SceneNode has no Transform handle");
            return;
        }

        _Step = 1;
        _WaitElapsed = 0.0f;
        utils_timer::Create_Tick(TestEntity, FCk_Delegate_Timer(this, n"OnFrameTick"));
    }

    UFUNCTION()
    private void OnFrameTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _WaitElapsed += float32(InDeltaT.Get_Seconds());
        if (_WaitElapsed < PropagationWaitSeconds) { return; }
        _WaitElapsed = 0.0f;

        if (_Step == 1)
        {
            // After settle: child world should equal ChildLocal (parent at Identity).
            AssertChildMatches(FVector::ZeroVector, FRotator::ZeroRotator, "Initial (parent at Identity)");
            if (IsFinished()) { return; }

            // Now move the parent: rotation + translation. The layer-update
            // processor should propagate to the child within a tick or two.
            utils_transform::Request_SetLocation(
                ParentTransform, ParentTargetLocation, ECk_LocalWorld::World);
            utils_transform::Request_AddRotationOffset(
                ParentTransform, ParentRotationDelta, ECk_LocalWorld::World);

            _Step = 2;
            return;
        }

        if (_Step == 2)
        {
            AssertChildMatches(ParentTargetLocation, ParentRotationDelta, "After parent move + rotate");
            FinishSuccess();
            return;
        }
    }

    private void AssertChildMatches(
        const FVector& InParentLocation, const FRotator& InParentRotation, const FString& InContext)
    {
        auto ParentWorld = FTransform(InParentRotation, InParentLocation, FVector::OneVector);
        auto ChildLocal = FTransform(ChildLocalRotation, ChildLocalLocation, FVector::OneVector);
        auto ExpectedWorld = ChildLocal * ParentWorld;

        auto ExpectedLoc = ExpectedWorld.GetLocation();
        auto ExpectedRot = ExpectedWorld.GetRotation().Rotator();

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(ChildTransform);
        auto ActualRot = utils_transform::Get_EntityCurrentRotation(ChildTransform);

        Assert_True(ActualLoc.Equals(ExpectedLoc, PositionToleranceCm),
            f"[{InContext}] child location | expected {ExpectedLoc}, got {ActualLoc}");
        Assert_True(ActualRot.Equals(ExpectedRot, RotationToleranceDeg),
            f"[{InContext}] child rotation | expected {ExpectedRot}, got {ActualRot}");
    }
}
