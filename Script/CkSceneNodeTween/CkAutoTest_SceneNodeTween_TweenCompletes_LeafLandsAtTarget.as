// Language=angelscript

//============================================================================
// CK SCENE NODE + TWEEN — AUTOMATION TEST: TWEEN COMPLETES, LEAF AT TARGET
//============================================================================
//
// Endpoint contract: when a TweenEntityLocation on the root scene-node
// completes, the leaf (one child SceneNode below) lands at exactly:
//
//   LeafWorld = RootStart + TweenOffset + ChildLocalOffset
//
// Unlike the Depth0/1/4 per-frame drift tests, this asserts the discrete
// endpoint after OnComplete + one settle frame. Catches a regression where
// the tween writes the final root value but the child never picks up the
// final propagation pass (so the leaf trails behind by one frame's worth
// of motion forever).
//============================================================================

class UCk_AutoTest_SceneNodeTween_TweenCompletes_LeafLandsAtTarget : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector RootStart = FVector(50.0f, 0.0f, 0.0f);
    private const FVector RootEnd = FVector(250.0f, 0.0f, 0.0f);
    private const FVector ChildLocalLocation = FVector(0.0f, 100.0f, 0.0f);
    private const FVector ExpectedLeafEnd = FVector(250.0f, 100.0f, 0.0f);

    private const float32 PositionToleranceCm = 1.0f;
    private const float32 TweenDurationSec = 0.3f;

    private FCk_Handle_Transform _RootTH;
    private FCk_Handle_SceneNode _Child;
    private FCk_Handle_Tween _Tween;
    private bool _TweenComplete = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ParentXf = FTransform(FRotator::ZeroRotator, RootStart, FVector::OneVector);
        auto ParentTransform = utils_transform::Add(ParentEntity, ParentXf, ECk_Replication::DoesNotReplicate);
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
        _RootTH = RootNode.As_Transform();

        auto ChildLocal = FTransform(FRotator::ZeroRotator, ChildLocalLocation, FVector::OneVector);
        _Child = utils_scene_node::Create(_RootTH, ChildLocal);
        if (ck::Is_NOT_Valid(_Child))
        {
            FinishFailure("Failed to create child SceneNode");
            return;
        }

        _Tween = utils_tween::Create_TweenEntityLocation(
            _RootTH, RootEnd, TweenDurationSec,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None,
            0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        utils_tween::BindTo_OnComplete(_Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnTweenComplete"));
    }

    UFUNCTION()
    private void OnTweenComplete(FCk_Handle_Tween InHandle, FCk_Tween_Payload_OnComplete InPayload)
    {
        if (IsFinished()) { return; }
        _TweenComplete = true;
        WaitUntil(n"Check_LeafPropagated", n"OnFinalSettle");
    }

    // Propagation consistency, not the tween's target: this only asks whether the
    // SceneNode pass has pushed the root's new world transform down to the leaf.
    // The assertions below still judge whether it landed where it should.
    UFUNCTION()
    private void Check_LeafPropagated(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Root = utils_transform::Get_EntityCurrentLocation(_RootTH);
        auto Leaf = utils_transform::Get_EntityCurrentLocation(_Child.As_Transform());
        auto Expected = Root + ChildLocalLocation;

        auto Res = OutResult;
        Res.Set(Math::Abs(Leaf.X - Expected.X) < 1.0f
             && Math::Abs(Leaf.Y - Expected.Y) < 1.0f
             && Math::Abs(Leaf.Z - Expected.Z) < 1.0f);
    }

    UFUNCTION()
    private void OnFinalSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(_TweenComplete, "Tween OnComplete must fire before final assert");

        auto RootWorld = utils_transform::Get_EntityCurrentLocation(_RootTH);
        auto DRootX = Math::Abs(RootWorld.X - RootEnd.X);
        Assert_True(DRootX < PositionToleranceCm,
            f"Root world X should equal tween end after completion (expected {RootEnd.X}, got {RootWorld.X})");

        auto LeafWorld = utils_transform::Get_EntityCurrentLocation(_Child.As_Transform());
        auto DX = Math::Abs(LeafWorld.X - ExpectedLeafEnd.X);
        auto DY = Math::Abs(LeafWorld.Y - ExpectedLeafEnd.Y);
        auto DZ = Math::Abs(LeafWorld.Z - ExpectedLeafEnd.Z);

        Assert_True(DX < PositionToleranceCm,
            f"Leaf world X must equal Root.End + ChildLocal.X after completion (expected {ExpectedLeafEnd.X}, got {LeafWorld.X})");
        Assert_True(DY < PositionToleranceCm,
            f"Leaf world Y must equal Root.End + ChildLocal.Y after completion (expected {ExpectedLeafEnd.Y}, got {LeafWorld.Y})");
        Assert_True(DZ < PositionToleranceCm,
            f"Leaf world Z must equal Root.End + ChildLocal.Z after completion (expected {ExpectedLeafEnd.Z}, got {LeafWorld.Z})");

        FinishSuccess();
    }
}
