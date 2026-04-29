// Language=angelscript

//============================================================================
// CK SCENE NODE — AUTOMATION TEST: ACTOR ATTACHED TO ACTOR
//============================================================================
//
// Reproduces the bug observed when trying to make a WithActor-backed entity
// (Actor B) follow another WithActor-backed entity (Actor A) by scene-node-
// parenting B to a child SceneNode of A.
//
// This mirrors the production held-item presentation flow:
//   - Actor A == "the character"
//   - A child SceneNode on A's entity transform == an attach point with a
//     local offset.
//   - Actor B == "the held item"
//   - utils_scene_node::Add(B_entity_transform, A_sceneNode.As_Transform(),
//     FTransform::Identity) attaches B under A's attach point.
//
// EXPECTED OUTCOME (current framework): this test FAILS, and the cause is in
// CkFoundation's scene-node propagation. The layer-update processor
// (FProcessor_SceneNode_Update<Layer>, CkSceneNode_Processor.cpp) early-outs
// for any entity holding FFragment_Transform_RootComponent or
// FFragment_Transform_MeshSocket:
//
//     if (InHandle.Has_Any<FFragment_Transform_MeshSocket,
//                          FFragment_Transform_RootComponent>())
//     { return; }
//
// UCk_EntityScript_WithActor_UE adds FFragment_Transform_RootComponent (the
// actor's RootComponent drives the entity's Transform fragment), so any
// WithActor-bound entity (like ABb_ItemActor) is treated as "actor-
// authoritative" and the scene-node parent's transform is never propagated
// into it. A sibling processor (FProcessor_SceneNode_UpdateLocal_FromRootComponent)
// runs the OPPOSITE direction: it reads the actor's world transform and
// rewrites the relative offset on the scene-node fragment.
//
// In short: WithActor + scene-node parent are mutually exclusive in the
// current framework. To make a held actor follow an attach point you need
// one of:
//   (a) a non-WithActor actor + manual per-tick SetActorLocationAndRotation
//       from the scene-node's computed world transform (gym pattern);
//   (b) native UE AttachToComponent against the resolved primitives behind
//       the attach-point handle (mesh+socket / capsule+offset);
//   (c) a CkFoundation-side change: a new processor / opt-in flag that lets
//       a RootComponent-bound entity be driven BY the scene-node parent
//       (push the entity transform into the actor instead of pulling).
//
// This test is the regression repro for the bug. It will go green when the
// framework gains a fix (likely option (c)).
//
// Test flow:
//   1. Spawn Actor A at a known world transform.
//   2. When A's entity is ECS-ready, create a child SceneNode on A's entity
//      transform with a known local offset (location + rotation).
//   3. Spawn Actor B at the origin (the spawn pose is irrelevant if propagation
//      works — the scene-node parenting overrides it).
//   4. When B's entity is ECS-ready, scene-node-parent B's entity transform
//      to the SceneNode created in (2) with FTransform::Identity local offset.
//   5. Wait a few frames for the ECS scene-node + transform sync processors.
//   6. Assert layer 1 (B's entity transform) and layer 2 (B's actor world
//      transform) both match the expected composed transform
//      (sceneNode_local * A_world).
//   7. Apply a yaw rotation to A's entity transform.
//   8. Wait a few frames again.
//   9. Assert both layers reflect the new pose.
//============================================================================

// Non-replicated WithActor entity script — the test runs locally on the
// authority only, so we explicitly opt the actor↔entity bridge out of
// replication to keep the test self-contained.
class UCk_AutoTest_SceneNode_AttachedActor_EntityScript : UCk_EntityScript_WithActor_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;
}

class ACk_AutoTest_SceneNode_AttachedActor_Helper : AActor
{
    default bReplicates = false;

    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent RootComponent;

    default RootComponent.Mobility = EComponentMobility::Movable;

    FCk_Handle_PendingEntityScript PendingEntity;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SpawnParams._OwningActor = this;
        PendingEntity = utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(), UCk_AutoTest_SceneNode_AttachedActor_EntityScript, SpawnParams);
    }
}

class UCk_AutoTest_SceneNode_ActorAttachedToActor : UCk_AutoTest_Base
{
    private const FVector A_StartLocation = FVector(500.0f, 0.0f, 100.0f);
    private const FVector ChildNodeLocalLocation = FVector(100.0f, 0.0f, 50.0f);
    private const FRotator ChildNodeLocalRotation = FRotator(0.0f, 30.0f, 0.0f);
    private const FRotator A_RotationDelta = FRotator(0.0f, 90.0f, 0.0f);

    private const float32 PositionToleranceCm = 1.0f;
    private const float32 RotationToleranceDeg = 1.0f;
    private const float32 PropagationWaitSeconds = 0.25f;

    private FCk_Handle TestEntity;
    private ACk_AutoTest_SceneNode_AttachedActor_Helper ActorA;
    private ACk_AutoTest_SceneNode_AttachedActor_Helper ActorB;
    private FCk_Handle_Transform A_Transform;
    private FCk_Handle_Transform B_Transform;
    private FCk_Handle_SceneNode ChildNodeOnA;

    private int32 _Step = 0;
    private float32 _WaitElapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        TestEntity = InHandle;

        ActorA = Cast<ACk_AutoTest_SceneNode_AttachedActor_Helper>(SpawnActor(
            ACk_AutoTest_SceneNode_AttachedActor_Helper, A_StartLocation, FRotator()));

        if (ck::Is_NOT_Valid(ActorA))
        {
            FinishFailure("Failed to spawn ActorA");
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(
            ActorA.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnActorAEntityReady"));
    }

    UFUNCTION()
    private void OnActorAEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto EntityA = FCk_Handle(InEntityScriptHandle);
        A_Transform = EntityA.As_Transform();

        if (ck::Is_NOT_Valid(A_Transform))
        {
            FinishFailure("ActorA entity has no Transform after construction");
            return;
        }

        auto ChildLocal = FTransform(ChildNodeLocalRotation, ChildNodeLocalLocation, FVector::OneVector);
        ChildNodeOnA = utils_scene_node::Create(A_Transform, ChildLocal);

        if (ck::Is_NOT_Valid(ChildNodeOnA))
        {
            FinishFailure("Failed to create child SceneNode on ActorA");
            return;
        }

        ActorB = Cast<ACk_AutoTest_SceneNode_AttachedActor_Helper>(SpawnActor(
            ACk_AutoTest_SceneNode_AttachedActor_Helper, FVector(0.0f, 0.0f, 0.0f), FRotator()));

        if (ck::Is_NOT_Valid(ActorB))
        {
            FinishFailure("Failed to spawn ActorB");
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(
            ActorB.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnActorBEntityReady"));
    }

    UFUNCTION()
    private void OnActorBEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto EntityB = FCk_Handle(InEntityScriptHandle);
        B_Transform = EntityB.As_Transform();

        if (ck::Is_NOT_Valid(B_Transform))
        {
            FinishFailure("ActorB entity has no Transform after construction");
            return;
        }

        auto ChildAsTransform = ChildNodeOnA.As_Transform();
        utils_scene_node::Add(B_Transform, ChildAsTransform, FTransform::Identity);

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
            AssertActorBMatchesComposedExpected(A_StartLocation, FRotator(), "Initial (A unrotated)");
            if (IsFinished()) { return; }

            utils_transform::Request_AddRotationOffset(
                A_Transform, A_RotationDelta, ECk_LocalWorld::World);

            _Step = 2;
            return;
        }

        if (_Step == 2)
        {
            AssertActorBMatchesComposedExpected(A_StartLocation, A_RotationDelta, "After A yaw 90deg");
            FinishSuccess();
            return;
        }
    }

    // Compose expected: B_World = ChildNodeLocal * A_World (B's own scene-node
    // local offset under the child node = Identity, set in OnActorBEntityReady).
    //
    // Asserts on TWO layers so the failure tells us which one is broken:
    //   1. ECS Transform fragment on B — driven by scene-node propagation.
    //   2. ActorB world transform — driven by the Transform→Actor sync processor.
    private void AssertActorBMatchesComposedExpected(
        const FVector& InA_Location, const FRotator& InA_Rotation, const FString& InContext)
    {
        if (ck::Is_NOT_Valid(ActorB))
        {
            FinishFailure(f"[{InContext}] ActorB became invalid");
            return;
        }

        auto A_World = FTransform(InA_Rotation, InA_Location, FVector::OneVector);
        auto ChildLocal = FTransform(ChildNodeLocalRotation, ChildNodeLocalLocation, FVector::OneVector);
        auto B_ExpectedWorld = ChildLocal * A_World;

        auto ExpectedLoc = B_ExpectedWorld.GetLocation();
        auto ExpectedRot = B_ExpectedWorld.GetRotation().Rotator();

        auto A_EntityLoc = utils_transform::Get_EntityCurrentLocation(A_Transform);
        auto A_EntityRot = utils_transform::Get_EntityCurrentRotation(A_Transform);
        ck::Trace(f"[{InContext}] A.entity loc={A_EntityLoc} rot={A_EntityRot} (expected loc={InA_Location} rot={InA_Rotation})");

        auto B_EntityLoc = utils_transform::Get_EntityCurrentLocation(B_Transform);
        auto B_EntityRot = utils_transform::Get_EntityCurrentRotation(B_Transform);

        Assert_True(B_EntityLoc.Equals(ExpectedLoc, PositionToleranceCm),
            f"[{InContext}] B.entity location | expected {ExpectedLoc}, got {B_EntityLoc}");
        Assert_True(B_EntityRot.Equals(ExpectedRot, RotationToleranceDeg),
            f"[{InContext}] B.entity rotation | expected {ExpectedRot}, got {B_EntityRot}");

        auto ActualLoc = ActorB.GetActorLocation();
        auto ActualRot = ActorB.GetActorRotation();

        Assert_True(ActualLoc.Equals(ExpectedLoc, PositionToleranceCm),
            f"[{InContext}] ActorB world location | expected {ExpectedLoc}, got {ActualLoc}");
        Assert_True(ActualRot.Equals(ExpectedRot, RotationToleranceDeg),
            f"[{InContext}] ActorB world rotation | expected {ExpectedRot}, got {ActualRot}");
    }
}

class ACk_AutoTest_SceneNode_ActorAttachedToActor_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_SceneNode_ActorAttachedToActor;
    default _TimeoutSeconds = 5.0f;
}
