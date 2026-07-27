// Language=angelscript

//============================================================================
// CK SCENE NODE + TWEEN — AUTOMATION TEST: DEPTH-0 LEAF MATCHES EXPECTED
//============================================================================
//
// Headless equivalent of the SceneNodeTween gym's SIMPLE station: a tweened
// root with a single SceneNode child underneath. Verifies that on every
// sampled tick during a tween-driven root motion, the child's ECS-reported
// world location matches the AS-composed expected location (child local
// composed onto root world) within a sub-cm tolerance.
//
// A propagation-stall regression — where the tween moves the root but the
// child stays anchored at its initial world position — surfaces as a growing
// drift that peaks at the tween amplitude. We accumulate the maximum drift
// observed across the tween's lifetime and assert it remains small after
// OnComplete + one settle frame.
//============================================================================

class UCk_AutoTest_SceneNodeTween_Depth0_LeafMatchesExpected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector ChildLocalLocation = FVector(0.0f, 100.0f, 0.0f);
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
        // Skip the first sample — transform features are added this same tick and
        // SceneNode composition needs one processor pass to populate the child's
        // initial world transform. Subsequent samples must match.
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
        Assert_True(_SampleCount >= 3,
            f"Tick poller must sample multiple frames during the tween (got {_SampleCount})");
        Assert_True(_MaxDrift < DriftToleranceCm,
            f"Leaf world location must track AS-composed expected within {DriftToleranceCm}cm across every sampled frame (max drift observed: {_MaxDrift}cm)");

        FinishSuccess();
    }
}
