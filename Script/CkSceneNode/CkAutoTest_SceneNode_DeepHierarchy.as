// Language=angelscript

//============================================================================
// CK SCENE NODE — AUTOMATION TEST: DEEP HIERARCHY
//============================================================================
//
// Headless equivalent of the Hierarchy / PropagateOnly gym behaviors.
// Three-level chain: root (bare ECS transform) → child (SceneNode) →
// grandchild (SceneNode). Verifies that:
//
//   1. Initial composition: each level's world transform = its local offset
//      composed onto the parent's world.
//   2. Rotating the root propagates to BOTH child and grandchild (Layer1 and
//      Layer2 must both fire when root.Transform_Updated is set).
//   3. Updating the child's offset (via Request_UpdateOffset_Rotation)
//      propagates to grandchild (Layer2 must re-fire when child.Transform_
//      Updated is set even if root didn't move).
//
// If any of these break, propagation has stalled at a layer boundary —
// usually the layer-update gate not picking up parent's Transform_Updated.
//============================================================================

class UCk_AutoTest_SceneNode_DeepHierarchy : UCk_AutoTest_Base
{
    private const FVector ChildLocalLocation = FVector(120.0f, 0.0f, 0.0f);
    private const FVector GrandchildLocalLocation = FVector(80.0f, 0.0f, 0.0f);
    private const FRotator RootRotationDelta = FRotator(0.0f, 90.0f, 0.0f);
    private const FRotator ChildOffsetRotation = FRotator(0.0f, 30.0f, 0.0f);

    private const float32 PositionToleranceCm = 1.0f;
    private const float32 PropagationWaitSeconds = 0.25f;

    private FCk_Handle TestEntity;
    private FCk_Handle_Transform RootTransform;
    private FCk_Handle_SceneNode ChildNode;
    private FCk_Handle_Transform ChildTransform;
    private FCk_Handle_SceneNode GrandchildNode;
    private FCk_Handle_Transform GrandchildTransform;

    private int32 _Step = 0;
    private float32 _WaitElapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        TestEntity = InHandle;

        auto RootEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        RootTransform = utils_transform::Add(RootEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(RootTransform))
        {
            FinishFailure("Failed to add Transform feature to root entity");
            return;
        }

        auto ChildLocal = FTransform(FRotator::ZeroRotator, ChildLocalLocation, FVector::OneVector);
        ChildNode = utils_scene_node::Create(RootTransform, ChildLocal);
        if (ck::Is_NOT_Valid(ChildNode))
        {
            FinishFailure("Failed to create child SceneNode");
            return;
        }
        ChildTransform = ChildNode.As_Transform();

        auto GrandchildLocal = FTransform(FRotator::ZeroRotator, GrandchildLocalLocation, FVector::OneVector);
        GrandchildNode = utils_scene_node::Create(ChildTransform, GrandchildLocal);
        if (ck::Is_NOT_Valid(GrandchildNode))
        {
            FinishFailure("Failed to create grandchild SceneNode");
            return;
        }
        GrandchildTransform = GrandchildNode.As_Transform();

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
            AssertChainComposesTo(FRotator::ZeroRotator, FRotator::ZeroRotator, "Initial (root at Identity)");
            if (IsFinished()) { return; }

            utils_transform::Request_AddRotationOffset(RootTransform, RootRotationDelta, ECk_LocalWorld::World);
            _Step = 2;
            return;
        }

        if (_Step == 2)
        {
            AssertChainComposesTo(RootRotationDelta, FRotator::ZeroRotator, "After root yaw 90deg");
            if (IsFinished()) { return; }

            utils_scene_node::Request_UpdateOffset_Rotation(ChildNode, ChildOffsetRotation, ECk_RelativeAbsolute::Absolute);
            _Step = 3;
            return;
        }

        if (_Step == 3)
        {
            // Child offset rotation must propagate to grandchild even though root hasn't moved this step.
            AssertChainComposesTo(RootRotationDelta, ChildOffsetRotation, "After child offset rotation");
            FinishSuccess();
            return;
        }
    }

    private void AssertChainComposesTo(
        const FRotator& InRootRotation, const FRotator& InChildOffsetRotation, const FString& InContext)
    {
        auto RootWorld = FTransform(InRootRotation, FVector::ZeroVector, FVector::OneVector);
        auto ChildLocal = FTransform(InChildOffsetRotation, ChildLocalLocation, FVector::OneVector);
        auto GrandchildLocal = FTransform(FRotator::ZeroRotator, GrandchildLocalLocation, FVector::OneVector);

        auto ChildExpected = ChildLocal * RootWorld;
        auto GrandchildExpected = GrandchildLocal * ChildExpected;

        auto ChildLoc = utils_transform::Get_EntityCurrentLocation(ChildTransform);
        Assert_True(ChildLoc.Equals(ChildExpected.GetLocation(), PositionToleranceCm),
            f"[{InContext}] child location | expected {ChildExpected.GetLocation()}, got {ChildLoc}");

        auto GrandchildLoc = utils_transform::Get_EntityCurrentLocation(GrandchildTransform);
        Assert_True(GrandchildLoc.Equals(GrandchildExpected.GetLocation(), PositionToleranceCm),
            f"[{InContext}] grandchild location | expected {GrandchildExpected.GetLocation()}, got {GrandchildLoc}");
    }
}

class ACk_AutoTest_SceneNode_DeepHierarchy_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_SceneNode_DeepHierarchy;
    default _TimeoutSeconds = 5.0f;
}
