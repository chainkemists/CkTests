// Language=angelscript

//============================================================================
// CK SCENE NODE + TWEEN - AUTOMATION TEST: NON-UNIFORM SCALE PROPAGATES
//============================================================================
//
// Tween-driven counterpart to CkAutoTest_SceneNode_NonUniformScalePropagation:
// a non-uniform parent scale must compose correctly into the child's world
// location while the root location is being tweened. The static
// (non-tween) test already pins this for fixed transforms; this test pins
// that the compose-with-scale step still runs every frame under a moving
// root.
//
// Setup:
//   Parent transform: Loc=(0,0,0), Rot=Identity, Scale=(0.5, 2.0, 1.0)
//   Child SceneNode local offset: Loc=(0, 50, 0), Scale=1
//
// At any moment during the tween:
//   ChildWorld.X = Root.X + 0.5 * 0    = Root.X
//   ChildWorld.Y = Root.Y + 2.0 * 50   = Root.Y + 100
//   ChildWorld.Z = Root.Z + 1.0 * 0    = Root.Z
//============================================================================

class UCk_AutoTest_SceneNodeTween_NonUniformScalePropagatesToLeaf : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector ParentScale = FVector(0.5f, 2.0f, 1.0f);
    private const FVector ChildLocalLocation = FVector(0.0f, 50.0f, 0.0f);
    private const FVector TweenEndLocation = FVector(200.0f, 0.0f, 0.0f);
    private const float32 TweenDurationSec = 0.4f;
    private const float32 DriftToleranceCm = 1.0f;

    private FCk_Handle_Transform _RootTH;
    private FCk_Handle_SceneNode _Child;
    private FCk_Handle_Tween _Tween;

    private float32 _MaxDrift = 0.0f;
    private int32 _SampleCount = 0;
    private bool _TweenComplete = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ParentXf = FTransform(FRotator::ZeroRotator, FVector::ZeroVector, ParentScale);
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
            _RootTH, TweenEndLocation, TweenDurationSec,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None,
            0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        utils_tween::BindTo_OnComplete(_Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnTweenComplete"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto RootXform = utils_transform::Get_EntityCurrentTransform(_RootTH);
        auto ChildLocal = FTransform(FRotator::ZeroRotator, ChildLocalLocation, FVector::OneVector);
        auto Expected = (ChildLocal * RootXform).GetLocation();
        auto Actual = utils_transform::Get_EntityCurrentLocation(_Child.As_Transform());

        _SampleCount += 1;
        if (_SampleCount < 2) { return; }

        auto DX = Math::Abs(Expected.X - Actual.X);
        auto DY = Math::Abs(Expected.Y - Actual.Y);
        auto DZ = Math::Abs(Expected.Z - Actual.Z);
        auto Drift = Math::Max(Math::Max(DX, DY), DZ);
        if (Drift > _MaxDrift) { _MaxDrift = float32(Drift); }
    }

    UFUNCTION()
    private void OnTweenComplete(FCk_Handle_Tween InHandle, FCk_Tween_Payload_OnComplete InPayload)
    {
        if (IsFinished()) { return; }
        _TweenComplete = true;
        WaitOneFrame(n"OnFinalSettle");
    }

    UFUNCTION()
    private void OnFinalSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_TweenComplete, "Tween OnComplete must fire before final assert");

        auto FinalLeaf = utils_transform::Get_EntityCurrentLocation(_Child.As_Transform());
        // Expected at completion: Root at tween end (200,0,0), with parent's
        // non-uniform scale composed into ChildLocal: child world Y =
        // RootEnd.Y + ParentScale.Y * ChildLocal.Y = 0 + 2.0 * 50 = 100.
        auto ExpectedY = ParentScale.Y * ChildLocalLocation.Y;
        auto DLeafY = Math::Abs(FinalLeaf.Y - ExpectedY);
        Assert_True(DLeafY < DriftToleranceCm,
            f"At tween completion, leaf Y must reflect parent non-uniform scale {ParentScale.Y}x on local offset {ChildLocalLocation.Y} (expected {ExpectedY}, got {FinalLeaf.Y})");

        Assert_True(_MaxDrift < DriftToleranceCm,
            f"Leaf must track tween+scale composition within {DriftToleranceCm}cm across every sampled frame (max drift observed: {_MaxDrift}cm)");

        FinishSuccess();
    }
}
