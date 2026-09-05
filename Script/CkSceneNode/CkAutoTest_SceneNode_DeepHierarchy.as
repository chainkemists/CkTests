// Language=angelscript

//============================================================================
// CK SCENE NODE - AUTOMATION TEST: DEEP HIERARCHY
//============================================================================
//
// Headless equivalent of the Hierarchy / PropagateOnly gym behaviors.
// Three-level chain: root (bare ECS transform) -> child (SceneNode) ->
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
// If any of these break, propagation has stalled at a layer boundary
// usually the layer-update gate not picking up parent's Transform_Updated.
//============================================================================

// The timer-driven assertions below establish eventual propagation. This probe
// separately observes the leaf after Transform_Finalize in the producer's exact
// frame, before the scheduler's global pump can repair a missed local settle.
struct FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameResult
{
    bool Completed = false;
    bool Succeeded = false;
    int64 StimulusFrame = -1;
    int64 ProbeFrame = -1;

    FCk_Handle_Transform Root;
    FCk_Handle_Transform Grandchild;
    FTransform TargetRootTransform;
    FTransform ExpectedGrandchildTransform;
    FTransform ActualGrandchildTransform;
}

struct FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameProducerMarker {}
struct FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameProbeMarker {}

class UCk_TESTONLY_Processor_SceneNodeDeepHierarchy_ExactFrameProducer : UCk_Processor_Script_Base_UE
{
    default _Group = n"FGroup_Gameplay_TimeDelta";

    UFUNCTION(BlueprintOverride)
    void Configure(FCk_ScriptProcessorQuery& Query)
    {
        Query.Require(FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameProducerMarker);
        Query.Require(FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameResult);
    }

    UFUNCTION(BlueprintOverride)
    void ForEachBatch(FCk_ScriptQueryBatch Batch, FCk_Time InDeltaT)
    {
        for (int32 Index = 0; Index < Batch.Num(); ++Index)
        {
            auto Entity = Batch.GetHandle(Index);
            auto& Result = Entity.Get_Fragment(FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameResult);
            if (Result.StimulusFrame >= 0)
            { continue; }

            Result.StimulusFrame = utils_time::Get_FrameCounter();
            utils_transform::Request_SetTransform(Result.Root, Result.TargetRootTransform);
            Entity.Request_TryRemove(FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameProducerMarker);
        }
    }
}

class UCk_TESTONLY_Processor_SceneNodeDeepHierarchy_ExactFrameProbe : UCk_Processor_Script_Base_UE
{
    default _Group = n"FGroup_Gameplay_Camera";
    default _MarkedDirtyBy = FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameProbeMarker;

    UFUNCTION(BlueprintOverride)
    void Configure(FCk_ScriptProcessorQuery& Query)
    {
        Query.Require(FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameProbeMarker);
        Query.Require(FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameResult);
    }

    UFUNCTION(BlueprintOverride)
    void ForEachBatch(FCk_ScriptQueryBatch Batch, FCk_Time InDeltaT)
    {
        for (int32 Index = 0; Index < Batch.Num(); ++Index)
        {
            auto Entity = Batch.GetHandle(Index);
            auto& Result = Entity.Get_Fragment(FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameResult);
            if (Result.Completed || Result.StimulusFrame < 0)
            { continue; }

            Result.Succeeded = ck::IsValid(Result.Root) && ck::IsValid(Result.Grandchild);
            if (Result.Succeeded)
            {
                Result.ActualGrandchildTransform = utils_transform::Get_EntityCurrentTransform(Result.Grandchild);
            }

            Result.ProbeFrame = utils_time::Get_FrameCounter();
            Result.Completed = true;
            Entity.Request_TryRemove(FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameProbeMarker);
        }
    }
}

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
        auto _CkPerfScope = ck::ScopedStat();
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
            if (IsFinished())
            { return; }

            Arm_ExactFrameProbe();
            _Step = 4;
            return;
        }
    }

    private void Arm_ExactFrameProbe()
    {
        auto& Result = TestEntity.AddOrGet_Fragment(
            FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameResult);
        Result.Completed = false;
        Result.Succeeded = false;
        Result.StimulusFrame = -1;
        Result.ProbeFrame = -1;
        Result.Root = RootTransform;
        Result.Grandchild = GrandchildTransform;
        Result.TargetRootTransform = FTransform(
            FRotator(0.0f, -45.0f, 0.0f),
            FVector(725.0f, -330.0f, 45.0f),
            FVector::OneVector);

        const auto ChildLocal = FTransform(
            ChildOffsetRotation, ChildLocalLocation, FVector::OneVector);
        const auto GrandchildLocal = FTransform(
            FRotator::ZeroRotator, GrandchildLocalLocation, FVector::OneVector);
        Result.ExpectedGrandchildTransform = GrandchildLocal * (ChildLocal * Result.TargetRootTransform);

        TestEntity.AddOrGet_Fragment(
            FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameProducerMarker);
        TestEntity.AddOrGet_Fragment(
            FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameProbeMarker);
        WaitUntil(n"Check_ExactFrameProbe", n"OnExactFrameProbe");
    }

    UFUNCTION()
    private void Check_ExactFrameProbe(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        if (TestEntity.Has_Fragment(FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameResult) == false)
        { Result.Set(false); return; }

        Result.Set(TestEntity.Get_Fragment(
            FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameResult).Completed);
    }

    UFUNCTION()
    private void OnExactFrameProbe(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished())
        { return; }

        const auto& Result = TestEntity.Get_Fragment(
            FCk_Fragment_TESTONLY_SceneNodeDeepHierarchy_ExactFrameResult);
        Assert_True(Result.Succeeded,
            "Exact-frame SceneNode probe must resolve the root and grandchild handles");
        Assert_True(Result.ProbeFrame == Result.StimulusFrame,
            f"Grandchild must settle before the global pump in the stimulus frame; stimulus [{Result.StimulusFrame}], probe [{Result.ProbeFrame}]");
        Assert_True(Result.ActualGrandchildTransform.Equals(
            Result.ExpectedGrandchildTransform, PositionToleranceCm),
            f"Grandchild must equal the composed target root in the stimulus frame; expected [{Result.ExpectedGrandchildTransform}], actual [{Result.ActualGrandchildTransform}]");
        FinishSuccess();
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
