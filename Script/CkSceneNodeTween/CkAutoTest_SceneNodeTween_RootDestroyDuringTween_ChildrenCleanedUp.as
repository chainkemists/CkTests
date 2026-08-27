// Language=angelscript

//============================================================================
// CK SCENE NODE + TWEEN - AUTOMATION TEST: ROOT DESTROY MID-TWEEN
//============================================================================
//
// Tween-in-flight regression check for SceneNode parent destruction:
// destroying the parent transform entity while a Tween is actively writing
// the root's location must still cascade-destroy the child SceneNodes
// (no orphans, no dangling tween writes to freed handles).
//
// Setup:
//   ParentEntity has the parent Transform fixture.
//   Root SceneNode under ParentEntity carries an active Tween.
//   ChildA and ChildB SceneNodes hang off the Root.
//
// Procedure:
//   1. Create the chain.
//   2. Start the tween on the root.
//   3. Bind OnBeginDestroy on both children.
//   4. After a brief delay (mid-tween), destroy ParentEntity.
//   5. Wait for both children's OnBeginDestroy.
//============================================================================

class UCk_AutoTest_SceneNodeTween_RootDestroyDuringTween_ChildrenCleanedUp : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private const float32 TweenDurationSec = 1.0f;
    private const float32 MidFlightDelaySec = 0.15f;

    private FCk_Handle _ParentEntity;
    private FCk_Handle _ChildAEntity;
    private FCk_Handle _ChildBEntity;
    private FCk_Handle_Tween _Tween;
    private bool _ChildADestroyed = false;
    private bool _ChildBDestroyed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _ParentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ParentTransform = utils_transform::Add(_ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(ParentTransform))
        {
            FinishFailure("Failed to add Transform feature to parent entity");
            return;
        }

        auto RootNode = utils_scene_node::Create(ParentTransform, FTransform::Identity);
        if (ck::Is_NOT_Valid(RootNode))
        {
            FinishFailure("Failed to create root SceneNode");
            return;
        }
        auto RootTH = RootNode.As_Transform();

        auto ChildALocal = FTransform(FRotator::ZeroRotator, FVector(0.0f, 80.0f, 0.0f), FVector::OneVector);
        auto ChildBLocal = FTransform(FRotator::ZeroRotator, FVector(80.0f, 0.0f, 0.0f), FVector::OneVector);
        auto ChildANode = utils_scene_node::Create(RootTH, ChildALocal);
        auto ChildBNode = utils_scene_node::Create(RootTH, ChildBLocal);
        if (ck::Is_NOT_Valid(ChildANode) || ck::Is_NOT_Valid(ChildBNode))
        {
            FinishFailure("Failed to create child SceneNodes");
            return;
        }

        _ChildAEntity = FCk_Handle(ChildANode);
        _ChildBEntity = FCk_Handle(ChildBNode);

        utils_entity_lifetime::BindTo_OnBeginDestroy(
            _ChildAEntity,
            FCk_Delegate_OnBeginDestroy(this, n"OnChildADestroyed"));
        utils_entity_lifetime::BindTo_OnBeginDestroy(
            _ChildBEntity,
            FCk_Delegate_OnBeginDestroy(this, n"OnChildBDestroyed"));

        _Tween = utils_tween::Create_TweenEntityLocation(
            RootTH, FVector(300.0f, 0.0f, 0.0f), TweenDurationSec,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None,
            0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        System::SetTimer(this, n"OnMidFlightTrigger", MidFlightDelaySec, false);
    }

    UFUNCTION()
    private void OnMidFlightTrigger()
    {
        if (IsFinished()) { return; }
        Assert_True(ck::IsValid(_Tween),
            "Tween should still be valid mid-flight before parent destroy");
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
            "ChildA SceneNode must observe OnBeginDestroy when parent entity is destroyed mid-tween");
        Assert_True(_ChildBDestroyed,
            "ChildB SceneNode must observe OnBeginDestroy when parent entity is destroyed mid-tween");
        FinishSuccess();
    }
}
