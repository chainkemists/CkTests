// Language=angelscript

//============================================================================
// CK SCENE NODE + TWEEN — AUTOMATION TEST: DEPTH-4 LEAF MATCHES EXPECTED
//============================================================================
//
// Headless equivalent of the SceneNodeTween gym's DEEP station: a tweened
// root with a 5-link chain of intermediate SceneNodes underneath. Each link
// carries a distinct local offset + yaw so the leaf's world depends on the
// full propagation chain.
//
// Stress-tests propagation depth: every layer must observe the previous
// layer's update each frame. A regression where a deep layer stops observing
// its parent's Transform_Updated tag mid-chain surfaces as a leaf that
// gradually decouples from the tweened root.
//============================================================================

class UCk_AutoTest_SceneNodeTween_Depth4_LeafMatchesExpected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector TweenEndLocation = FVector(200.0f, 0.0f, 0.0f);
    private const float32 TweenDurationSec = 0.4f;
    private const float32 DriftToleranceCm = 1.0f;

    private FCk_Handle_Transform _RootTH;
    private TArray<FCk_Handle_SceneNode> _Chain;
    private TArray<FTransform> _LocalOffsets;
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

        // Mirror the gym's DEEP station: 5 links with mixed offsets and yaws.
        _LocalOffsets.Add(FTransform(FRotator(0.0f,  30.0f, 0.0f), FVector(100.0f,  0.0f, 0.0f), FVector::OneVector));
        _LocalOffsets.Add(FTransform(FRotator(0.0f, -20.0f, 0.0f), FVector( 80.0f, 20.0f, 0.0f), FVector::OneVector));
        _LocalOffsets.Add(FTransform(FRotator(0.0f,  15.0f, 0.0f), FVector( 60.0f,  0.0f, 0.0f), FVector::OneVector));
        _LocalOffsets.Add(FTransform(FRotator(0.0f, -10.0f, 0.0f), FVector( 40.0f, 20.0f, 0.0f), FVector::OneVector));
        _LocalOffsets.Add(FTransform(FRotator(0.0f,   5.0f, 0.0f), FVector( 30.0f,  0.0f, 0.0f), FVector::OneVector));

        auto ParentT = _RootTH;
        for (int32 i = 0; i < _LocalOffsets.Num(); ++i)
        {
            auto Link = utils_scene_node::Create(ParentT, _LocalOffsets[i]);
            if (ck::Is_NOT_Valid(Link))
            {
                FinishFailure(f"Failed to create chain link {i}");
                return;
            }
            _Chain.Add(Link);
            ParentT = Link.As_Transform();
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
        auto Acc = RootXform;
        for (int32 i = 0; i < _LocalOffsets.Num(); ++i)
        {
            Acc = _LocalOffsets[i] * Acc;
        }
        auto Expected = Acc.GetLocation();
        auto LeafNode = _Chain[_Chain.Num() - 1];
        auto Actual = utils_transform::Get_EntityCurrentLocation(LeafNode.As_Transform());

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
            f"5-link leaf world location must track AS-composed expected within {DriftToleranceCm}cm across every sampled frame (max drift observed: {_MaxDrift}cm)");

        FinishSuccess();
    }
}
