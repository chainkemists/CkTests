// Language=angelscript

//============================================================================
// CK SCENE NODE + TWEEN - AUTOMATION TEST: DEPTH-1 LEAF MATCHES EXPECTED
//============================================================================
//
// Headless equivalent of the SceneNodeTween gym's CHAIN station: a tweened
// root with one intermediate child node and a leaf node underneath it (root
// -> A -> B). Each non-root link carries a non-identity local rotation so
// the leaf's world transform depends on the full composition chain, not
// just a flat offset.
//
// Same drift-tracking contract as Depth0: every sampled tick during the
// tween must show ECS-reported leaf world location within DriftToleranceCm
// of the AS-composed expected. A regression that stalls layer-2 propagation
// (B doesn't observe A's update when only the root moved) surfaces as a
// growing drift that peaks at the tween amplitude.
//============================================================================

class UCk_AutoTest_SceneNodeTween_Depth1_LeafMatchesExpected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector OffsetA = FVector(100.0f, 0.0f, 0.0f);
    private const FRotator RotA = FRotator(0.0f, 45.0f, 0.0f);
    private const FVector OffsetB = FVector(0.0f, 80.0f, 0.0f);
    private const FRotator RotB = FRotator(0.0f, 0.0f, 30.0f);

    private const FVector TweenEndLocation = FVector(200.0f, 0.0f, 0.0f);
    private const float32 TweenDurationSec = 0.4f;
    private const float32 DriftToleranceCm = 1.0f;

    private FCk_Handle_Transform _RootTH;
    private FCk_Handle_SceneNode _NodeA;
    private FCk_Handle_SceneNode _NodeB;
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
        auto ParentTransform = utils_transform::Add(ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
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

        auto LocalA = FTransform(RotA, OffsetA, FVector::OneVector);
        _NodeA = utils_scene_node::Create(_RootTH, LocalA);
        if (ck::Is_NOT_Valid(_NodeA))
        {
            FinishFailure("Failed to create intermediate SceneNode A");
            return;
        }

        auto LocalB = FTransform(RotB, OffsetB, FVector::OneVector);
        auto NodeAT = _NodeA.As_Transform();
        _NodeB = utils_scene_node::Create(NodeAT, LocalB);
        if (ck::Is_NOT_Valid(_NodeB))
        {
            FinishFailure("Failed to create leaf SceneNode B");
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
        auto LocalA = FTransform(RotA, OffsetA, FVector::OneVector);
        auto LocalB = FTransform(RotB, OffsetB, FVector::OneVector);

        auto WorldA = LocalA * RootXform;
        auto Expected = (LocalB * WorldA).GetLocation();
        auto Actual = utils_transform::Get_EntityCurrentLocation(_NodeB.As_Transform());

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
        Assert_True(_SampleCount >= 3,
            f"Tick poller must sample multiple frames during the tween (got {_SampleCount})");
        Assert_True(_MaxDrift < DriftToleranceCm,
            f"Leaf B world location must track AS-composed expected within {DriftToleranceCm}cm across every sampled frame (max drift observed: {_MaxDrift}cm)");

        FinishSuccess();
    }
}
