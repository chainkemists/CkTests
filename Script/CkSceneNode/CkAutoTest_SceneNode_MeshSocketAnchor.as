// Language=angelscript

//============================================================================
// CK SCENE NODE — AUTOMATION TEST: MESH SOCKET ANCHOR
//============================================================================
//
// Regression guard for the anchor-follow path. A SceneNode created via
// CreateAndAttachToUnrealComponent is a READ-ONLY follower of a foreign Unreal
// component: FProcessor_SceneNode_FollowUnrealAnchor sets the node's world to
// InLocalTransform * componentWorld every tick and never writes back onto the
// component. These nodes carry the SceneNode-owned FFragment_SceneNode_UnrealAnchor
// (NOT the Transform module's FFragment_Transform_RootComponent), so they are
// excluded from TProcessor_SceneNode_Update and never engage SyncFromActor/SyncToActor.
//
// This test exercises BOTH offsets against a moving mesh component:
//   1. Spawn a helper actor with a UStaticMeshComponent.
//   2. Create an identity-offset node (tracks component world exactly) and a
//      non-identity-offset node (tracks InLocalTransform * componentWorld).
//   3. Move the actor.
//   4. After a settle, assert each node's entity transform matches its expected
//      composed world both before and after the move.
//
// **Why no socket name here:** CreateAndAttachToUnrealMesh fails loud
// (CK_ENSURE_IF_NOT) on an unknown socket name — the original version of this
// test passed "FakeSocket_TestOnly" intending to exercise UE's silent fallback
// to component-world transform, which we explicitly rejected: a typo in a
// socket name silently anchoring to component world is a QA-difficult class of
// bug. If you need genuine socket coverage, write a sibling test against a
// SkeletalMesh asset with real sockets.
//
// If this test fails, FollowUnrealAnchor isn't composing offset * anchorWorld,
// or the TProcessor_SceneNode_Update TExclude<FFragment_SceneNode_UnrealAnchor>
// is missing (a bare SceneNode_Update pass would clobber the followed pose).
//============================================================================

class ACk_AutoTest_SceneNode_MeshSocketAnchor_Helper : AActor
{
    default bReplicates = false;

    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent SceneRoot;

    UPROPERTY(DefaultComponent, Attach = SceneRoot)
    UStaticMeshComponent Mesh;

    // Movable so SetActorLocation actually moves the actor at runtime.
    default SceneRoot.Mobility = EComponentMobility::Movable;
    default Mesh.Mobility = EComponentMobility::Movable;
}

class UCk_AutoTest_SceneNode_MeshSocketAnchor : UCk_AutoTest_Base
{
    private const FVector HelperStartLocation = FVector(200.0f, 0.0f, 50.0f);
    private const FVector HelperMoveLocation = FVector(750.0f, -300.0f, 175.0f);

    // Non-identity offset for the second node: 120cm up, yawed 45deg.
    private const FTransform AnchorOffset = FTransform(FRotator(0.0f, 45.0f, 0.0f), FVector(0.0f, 0.0f, 120.0f), FVector::OneVector);

    private const float32 PositionToleranceCm = 1.0f;
    private const float32 RotationToleranceDeg = 1.0f;
    private const float32 PropagationWaitSeconds = 0.25f;

    private FCk_Handle TestEntity;
    private FCk_Handle_Transform StructuralParent;
    private ACk_AutoTest_SceneNode_MeshSocketAnchor_Helper Helper;
    private FCk_Handle_SceneNode MeshNode;
    private FCk_Handle_Transform MeshNodeTransform;
    private FCk_Handle_SceneNode OffsetNode;
    private FCk_Handle_Transform OffsetNodeTransform;

    private int32 _Step = 0;
    private float32 _WaitElapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        TestEntity = InHandle;

        // Bare ECS structural parent — the SceneNode hierarchy needs a Transform-
        // bearing parent for InAttachTo, but the actual transform of the new
        // SceneNode comes from the mesh component, not from this parent.
        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        StructuralParent = utils_transform::Add(ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(StructuralParent))
        {
            FinishFailure("Failed to add Transform feature to structural parent entity");
            return;
        }

        Helper = Cast<ACk_AutoTest_SceneNode_MeshSocketAnchor_Helper>(SpawnActor(
            ACk_AutoTest_SceneNode_MeshSocketAnchor_Helper, HelperStartLocation, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(Helper))
        {
            FinishFailure("Failed to spawn mesh-socket helper actor");
            return;
        }

        if (ck::Is_NOT_Valid(Helper.Mesh))
        {
            FinishFailure("Helper actor has no Mesh component");
            return;
        }

        MeshNode = utils_scene_node::CreateAndAttachToUnrealComponent(StructuralParent, Helper.Mesh, FTransform::Identity);
        if (ck::Is_NOT_Valid(MeshNode))
        {
            FinishFailure("CreateAndAttachToUnrealComponent returned an invalid handle");
            return;
        }

        MeshNodeTransform = MeshNode.As_Transform();
        if (ck::Is_NOT_Valid(MeshNodeTransform))
        {
            FinishFailure("Mesh-anchored SceneNode has no Transform handle");
            return;
        }

        OffsetNode = utils_scene_node::CreateAndAttachToUnrealComponent(StructuralParent, Helper.Mesh, AnchorOffset);
        if (ck::Is_NOT_Valid(OffsetNode))
        {
            FinishFailure("CreateAndAttachToUnrealComponent (offset) returned an invalid handle");
            return;
        }

        OffsetNodeTransform = OffsetNode.As_Transform();
        if (ck::Is_NOT_Valid(OffsetNodeTransform))
        {
            FinishFailure("Offset mesh-anchored SceneNode has no Transform handle");
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
            // After settle: SceneNode entity should track the mesh component world.
            AssertNodeTracksMeshWorld("Initial");
            if (IsFinished()) { return; }

            // Move the actor — the mesh component world moves with it,
            // SyncFromActor should pull that into the SceneNode entity.
            Helper.SetActorLocation(HelperMoveLocation);

            _Step = 2;
            return;
        }

        if (_Step == 2)
        {
            AssertNodeTracksMeshWorld("After actor move");
            FinishSuccess();
            return;
        }
    }

    private void AssertNodeTracksMeshWorld(const FString& InContext)
    {
        if (ck::Is_NOT_Valid(Helper) || ck::Is_NOT_Valid(Helper.Mesh))
        {
            FinishFailure(f"[{InContext}] Helper actor or mesh became invalid");
            return;
        }

        // Mesh component is rigidly attached to the actor root with no offset,
        // so its component-world transform equals the actor's world transform.
        // GetActorTransform is AS-bound; UMeshComponent::GetComponentTransform
        // is not.
        auto MeshWorld = Helper.GetActorTransform();
        auto ExpectedLoc = MeshWorld.GetLocation();
        auto ExpectedRot = MeshWorld.GetRotation().Rotator();

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(MeshNodeTransform);
        auto ActualRot = utils_transform::Get_EntityCurrentRotation(MeshNodeTransform);

        Assert_True(ActualLoc.Equals(ExpectedLoc, PositionToleranceCm),
            f"[{InContext}] mesh-anchored node location | expected {ExpectedLoc}, got {ActualLoc}");
        Assert_True(ActualRot.Equals(ExpectedRot, RotationToleranceDeg),
            f"[{InContext}] mesh-anchored node rotation | expected {ExpectedRot}, got {ActualRot}");

        // Offset node must sit at AnchorOffset composed onto the same mesh world.
        auto OffsetExpectedWorld = AnchorOffset * MeshWorld;
        auto OffsetExpectedLoc = OffsetExpectedWorld.GetLocation();
        auto OffsetExpectedRot = OffsetExpectedWorld.GetRotation().Rotator();

        auto OffsetActualLoc = utils_transform::Get_EntityCurrentLocation(OffsetNodeTransform);
        auto OffsetActualRot = utils_transform::Get_EntityCurrentRotation(OffsetNodeTransform);

        Assert_True(OffsetActualLoc.Equals(OffsetExpectedLoc, PositionToleranceCm),
            f"[{InContext}] offset node location | expected {OffsetExpectedLoc}, got {OffsetActualLoc}");
        Assert_True(OffsetActualRot.Equals(OffsetExpectedRot, RotationToleranceDeg),
            f"[{InContext}] offset node rotation | expected {OffsetExpectedRot}, got {OffsetActualRot}");
    }
}
