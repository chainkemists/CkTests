// Language=angelscript

//============================================================================
// CK SCENE NODE — AUTOMATION TEST: MESH SOCKET ANCHOR
//============================================================================
//
// Regression guard for the anchor-authoritative path. After we taught
// utils_scene_node::Add to mark its child FTag_Transform_ExternallyDriven so
// scene-node parents drive the child (Unreal AttachToComponent semantics),
// the Create*-flavored overloads must keep doing the OPPOSITE: their resulting
// SceneNode entity is supposed to track a foreign Unreal anchor (a
// USceneComponent or mesh socket), so the ExternallyDriven tag must NOT be
// stamped on those.
//
// This test exercises CreateAndAttachToUnrealMesh:
//   1. Spawn a helper actor with a UStaticMeshComponent.
//   2. Create a SceneNode via CreateAndAttachToUnrealMesh against that mesh
//      with a sentinel socket name "FakeSocket_TestOnly". GetSocketTransform
//      falls back to the component's world transform for unknown names, so
//      this test pins down the mesh-component world tracking path.
//   3. Move the actor.
//   4. After a settle, assert the SceneNode entity transform matches the
//      mesh component's world transform.
//
// If this test fails after the ExternallyDriven patch lands, the
// CreateAndAttachToUnrealMesh path accidentally got the tag stamped, or the
// SyncFromMeshSocket / UpdateLocal_FromMeshSocket exclude is too broad.
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

    private const float32 PositionToleranceCm = 1.0f;
    private const float32 RotationToleranceDeg = 1.0f;
    private const float32 PropagationWaitSeconds = 0.25f;

    private FCk_Handle TestEntity;
    private FCk_Handle_Transform StructuralParent;
    private ACk_AutoTest_SceneNode_MeshSocketAnchor_Helper Helper;
    private FCk_Handle_SceneNode MeshNode;
    private FCk_Handle_Transform MeshNodeTransform;

    private int32 _Step = 0;
    private float32 _WaitElapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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

        MeshNode = utils_scene_node::CreateAndAttachToUnrealMesh(
            StructuralParent, Helper.Mesh, n"FakeSocket_TestOnly");
        if (ck::Is_NOT_Valid(MeshNode))
        {
            FinishFailure("CreateAndAttachToUnrealMesh returned an invalid handle");
            return;
        }

        MeshNodeTransform = MeshNode.As_Transform();
        if (ck::Is_NOT_Valid(MeshNodeTransform))
        {
            FinishFailure("Mesh-anchored SceneNode has no Transform handle");
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
            // GetSocketTransform falls back to the component's world for unknown
            // socket names — same as the test's name "FakeSocket_TestOnly".
            AssertNodeTracksMeshWorld("Initial");
            if (IsFinished()) { return; }

            // Move the actor — the mesh component world moves with it,
            // SyncFromMeshSocket should pull that into the SceneNode entity.
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

        auto MeshWorld = Helper.Mesh.GetSocketTransform(n"FakeSocket_TestOnly");
        auto ExpectedLoc = MeshWorld.GetLocation();
        auto ExpectedRot = MeshWorld.GetRotation().Rotator();

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(MeshNodeTransform);
        auto ActualRot = utils_transform::Get_EntityCurrentRotation(MeshNodeTransform);

        Assert_True(ActualLoc.Equals(ExpectedLoc, PositionToleranceCm),
            f"[{InContext}] mesh-anchored node location | expected {ExpectedLoc}, got {ActualLoc}");
        Assert_True(ActualRot.Equals(ExpectedRot, RotationToleranceDeg),
            f"[{InContext}] mesh-anchored node rotation | expected {ExpectedRot}, got {ActualRot}");
    }
}

class ACk_AutoTest_SceneNode_MeshSocketAnchor_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_SceneNode_MeshSocketAnchor;
    default _TimeoutSeconds = 5.0f;
}
