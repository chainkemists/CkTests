// Language=angelscript

//============================================================================
// CK SCENE NODE - AUTOMATION TEST: MULTIPLE CHILDREN
//============================================================================
//
// Headless equivalent of the MultipleChildren gym behavior. Four child
// SceneNodes share the same bare ECS parent at cardinal local offsets.
// Rotates the parent and asserts every child's world transform composes
// correctly (ChildLocal * ParentWorld) - i.e. parent motion fans out to all
// siblings in a single tick.
//
// If a child reports its spawn-pose location instead of the rotated one, the
// layer-update gate is dropping the child after the first tick (parent's
// FTag_Transform_Updated isn't propagating to all siblings).
//============================================================================

class UCk_AutoTest_SceneNode_MultipleChildren : UCk_AutoTest_Base
{
    private const FRotator ParentRotationDelta = FRotator(0.0f, 90.0f, 0.0f);

    private const float32 PositionToleranceCm = 1.0f;
    private const float32 RotationToleranceDeg = 1.0f;
    private const float32 PropagationWaitSeconds = 0.25f;

    private FCk_Handle TestEntity;
    private FCk_Handle_Transform ParentTransform;
    private TArray<FCk_Handle_Transform> ChildTransforms;
    private TArray<FVector> ChildLocalOffsets;

    private int32 _Step = 0;
    private float32 _WaitElapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        TestEntity = InHandle;

        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        ParentTransform = utils_transform::Add(ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(ParentTransform))
        {
            FinishFailure("Failed to add Transform feature to bare parent entity");
            return;
        }

        ChildLocalOffsets.Add(FVector(120.0f, 0.0f, 0.0f));
        ChildLocalOffsets.Add(FVector(0.0f, 120.0f, 0.0f));
        ChildLocalOffsets.Add(FVector(-120.0f, 0.0f, 0.0f));
        ChildLocalOffsets.Add(FVector(0.0f, -120.0f, 0.0f));

        for (int32 Index = 0; Index < ChildLocalOffsets.Num(); ++Index)
        {
            auto ChildLocal = FTransform(FRotator::ZeroRotator, ChildLocalOffsets[Index], FVector::OneVector);
            auto ChildNode = utils_scene_node::Create(ParentTransform, ChildLocal);
            if (ck::Is_NOT_Valid(ChildNode))
            {
                FinishFailure(f"Failed to create child SceneNode {Index}");
                return;
            }

            auto ChildTransform = ChildNode.As_Transform();
            if (ck::Is_NOT_Valid(ChildTransform))
            {
                FinishFailure(f"Child SceneNode {Index} has no Transform handle");
                return;
            }

            ChildTransforms.Add(ChildTransform);
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
            AssertAllChildrenMatch(FRotator::ZeroRotator, "Initial (parent at Identity)");
            if (IsFinished()) { return; }

            utils_transform::Request_AddRotationOffset(ParentTransform, ParentRotationDelta, ECk_LocalWorld::World);
            _Step = 2;
            return;
        }

        if (_Step == 2)
        {
            AssertAllChildrenMatch(ParentRotationDelta, "After parent yaw 90deg");
            FinishSuccess();
            return;
        }
    }

    private void AssertAllChildrenMatch(const FRotator& InParentRotation, const FString& InContext)
    {
        auto ParentWorld = FTransform(InParentRotation, FVector::ZeroVector, FVector::OneVector);

        for (int32 Index = 0; Index < ChildTransforms.Num(); ++Index)
        {
            auto ChildLocal = FTransform(FRotator::ZeroRotator, ChildLocalOffsets[Index], FVector::OneVector);
            auto Expected = ChildLocal * ParentWorld;
            auto ExpectedLoc = Expected.GetLocation();

            auto ActualLoc = utils_transform::Get_EntityCurrentLocation(ChildTransforms[Index]);

            Assert_True(ActualLoc.Equals(ExpectedLoc, PositionToleranceCm),
                f"[{InContext}] child {Index} location | expected {ExpectedLoc}, got {ActualLoc}");
        }
    }
}
