// Language=angelscript

//============================================================================
// CK SCENE NODE - AUTOMATION TEST: PARENT DESTROY CASCADES TO CHILDREN
//============================================================================
//
// Verifies that destroying a SceneNode parent entity propagates to the
// children - the children must observe OnBeginDestroy. The lifetime
// ownership chain (parent owns child entities under it via SceneNode)
// guarantees this cascade - destroying the owner cascades to dependents.
//
// Setup:
//   Test entity owns ParentEntity (Transform fixture).
//   ParentEntity owns ChildA SceneNode and ChildB SceneNode (each with
//   their own Transform handle).
//
// Procedure:
//   1. Create the structure.
//   2. Bind OnBeginDestroy on each child's underlying entity.
//   3. Request_DestroyEntity(ParentEntity).
//   4. Wait for both children's OnBeginDestroy to fire.
//
// PASS: both children observe OnBeginDestroy within the timeout.
// FAIL: a child remains alive after parent destruction (orphan / dangling
//   reference signal).
//============================================================================

class UCk_AutoTest_SceneNode_ParentDestroyCascade : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle _ParentEntity;
    private FCk_Handle _ChildAEntity;
    private FCk_Handle _ChildBEntity;
    private bool _ChildADestroyed = false;
    private bool _ChildBDestroyed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _ParentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ParentTransform = utils_transform::Add(_ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto ChildANode = utils_scene_node::Create(ParentTransform, FTransform::Identity);
        auto ChildBNode = utils_scene_node::Create(ParentTransform, FTransform::Identity);

        // The child SceneNode entity itself receives OnBeginDestroy when the
        // parent owner is destroyed, since it lives in the parent's lifetime
        // ownership tree.
        _ChildAEntity = FCk_Handle(ChildANode);
        _ChildBEntity = FCk_Handle(ChildBNode);

        utils_entity_lifetime::BindTo_OnBeginDestroy(
            _ChildAEntity,
            FCk_Delegate_OnBeginDestroy(this, n"OnChildADestroyed"));
        utils_entity_lifetime::BindTo_OnBeginDestroy(
            _ChildBEntity,
            FCk_Delegate_OnBeginDestroy(this, n"OnChildBDestroyed"));

        utils_entity_lifetime::Request_DestroyEntity(_ParentEntity);
    }

    UFUNCTION()
    private void OnChildADestroyed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }
        _ChildADestroyed = true;
        TryFinish();
    }

    UFUNCTION()
    private void OnChildBDestroyed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }
        _ChildBDestroyed = true;
        TryFinish();
    }

    private void TryFinish()
    {
        if (_ChildADestroyed == false || _ChildBDestroyed == false) { return; }
        Assert_True(_ChildADestroyed,
            "ChildA SceneNode should observe OnBeginDestroy when parent entity is destroyed");
        Assert_True(_ChildBDestroyed,
            "ChildB SceneNode should observe OnBeginDestroy when parent entity is destroyed");
        FinishSuccess();
    }
}
