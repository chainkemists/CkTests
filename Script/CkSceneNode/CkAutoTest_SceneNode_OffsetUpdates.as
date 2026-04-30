// Language=angelscript

//============================================================================
// CK SCENE NODE — AUTOMATION TEST: OFFSET UPDATES
//============================================================================
//
// Headless equivalent of the OffsetUpdates / ParentChild gym behaviors.
// Exercises Request_UpdateOffset_Location / _Rotation / _Scale on a child
// SceneNode and asserts that each request mutates the relative transform
// AND the resulting child world transform.
//
// Bare ECS hierarchy (parent + child, no actors) so the test isolates the
// SceneNode_HandleRequests + layer-update propagation path.
//============================================================================

class UCk_AutoTest_SceneNode_OffsetUpdates : UCk_AutoTest_Base
{
    private const FVector InitialChildLocal = FVector(150.0f, 0.0f, 50.0f);
    private const FVector NewLocationOffset = FVector(75.0f, 200.0f, -100.0f);
    private const FRotator NewRotationOffset = FRotator(0.0f, 45.0f, 0.0f);
    private const FVector NewScaleOffset = FVector(2.0f, 2.0f, 2.0f);

    private const float32 PositionToleranceCm = 1.0f;
    private const float32 RotationToleranceDeg = 1.0f;
    private const float32 ScaleTolerance = 0.01f;
    private const float32 PropagationWaitSeconds = 0.25f;

    private FCk_Handle TestEntity;
    private FCk_Handle_Transform ParentTransform;
    private FCk_Handle_SceneNode ChildNode;
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

        ChildNode = utils_scene_node::Create(ParentTransform, FTransform(FRotator::ZeroRotator, InitialChildLocal, FVector::OneVector));
        if (ck::Is_NOT_Valid(ChildNode))
        {
            FinishFailure("Failed to create child SceneNode");
            return;
        }

        ChildTransform = ChildNode.As_Transform();
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
            // Initial offset should be reflected in child world.
            AssertChildWorldMatches(InitialChildLocal, FRotator::ZeroRotator, FVector::OneVector, "Initial offset");
            if (IsFinished()) { return; }

            utils_scene_node::Request_UpdateOffset_Location(ChildNode, NewLocationOffset, ECk_RelativeAbsolute::Absolute);
            _Step = 2;
            return;
        }

        if (_Step == 2)
        {
            AssertChildWorldMatches(NewLocationOffset, FRotator::ZeroRotator, FVector::OneVector, "After Request_UpdateOffset_Location");
            if (IsFinished()) { return; }

            utils_scene_node::Request_UpdateOffset_Rotation(ChildNode, NewRotationOffset, ECk_RelativeAbsolute::Absolute);
            _Step = 3;
            return;
        }

        if (_Step == 3)
        {
            AssertChildWorldMatches(NewLocationOffset, NewRotationOffset, FVector::OneVector, "After Request_UpdateOffset_Rotation");
            if (IsFinished()) { return; }

            utils_scene_node::Request_UpdateOffset_Scale(ChildNode, NewScaleOffset, ECk_RelativeAbsolute::Absolute);
            _Step = 4;
            return;
        }

        if (_Step == 4)
        {
            AssertChildWorldMatches(NewLocationOffset, NewRotationOffset, NewScaleOffset, "After Request_UpdateOffset_Scale");
            FinishSuccess();
            return;
        }
    }

    private void AssertChildWorldMatches(
        const FVector& InExpectedLocation,
        const FRotator& InExpectedRotation,
        const FVector& InExpectedScale,
        const FString& InContext)
    {
        // Parent is at Identity, so child world == child relative offset.
        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(ChildTransform);
        auto ActualRot = utils_transform::Get_EntityCurrentRotation(ChildTransform);
        auto ActualScale = utils_transform::Get_EntityCurrentTransform(ChildTransform).GetScale3D();

        Assert_True(ActualLoc.Equals(InExpectedLocation, PositionToleranceCm),
            f"[{InContext}] child location | expected {InExpectedLocation}, got {ActualLoc}");
        Assert_True(ActualRot.Equals(InExpectedRotation, RotationToleranceDeg),
            f"[{InContext}] child rotation | expected {InExpectedRotation}, got {ActualRot}");
        Assert_True(ActualScale.Equals(InExpectedScale, ScaleTolerance),
            f"[{InContext}] child scale | expected {InExpectedScale}, got {ActualScale}");

        // Also verify the offset getters reflect the requested values directly.
        auto OffsetLoc = utils_scene_node::Get_Offset_Location(ChildNode);
        auto OffsetRot = utils_scene_node::Get_Offset_Rotation(ChildNode);
        auto OffsetScale = utils_scene_node::Get_Offset_Scale(ChildNode);

        Assert_True(OffsetLoc.Equals(InExpectedLocation, PositionToleranceCm),
            f"[{InContext}] Get_Offset_Location | expected {InExpectedLocation}, got {OffsetLoc}");
        Assert_True(OffsetRot.Equals(InExpectedRotation, RotationToleranceDeg),
            f"[{InContext}] Get_Offset_Rotation | expected {InExpectedRotation}, got {OffsetRot}");
        Assert_True(OffsetScale.Equals(InExpectedScale, ScaleTolerance),
            f"[{InContext}] Get_Offset_Scale | expected {InExpectedScale}, got {OffsetScale}");
    }
}
