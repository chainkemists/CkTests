// Language=angelscript

//============================================================================
// CK SCENE NODE + TWEEN — AUTOMATION TEST: YOYO LOOP, LEAF TRACKS BOTH WAYS
//============================================================================
//
// Yoyo-loop variant of the propagation test: a root tween yoyos once
// (forward + reverse), and the leaf must track within tolerance every
// sampled frame across BOTH legs. We also observe the root's swept range
// to prove the yoyo actually reversed (max-X near tween end, min-X back
// near tween start).
//
// A propagation-stall regression where the leaf tracks the forward leg
// but stops observing the reverse leg's updates surfaces as drift that
// accumulates only after the yoyo turnaround.
//============================================================================

class UCk_AutoTest_SceneNodeTween_TweenLoopYoyo_LeafTracksBoth : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private const FVector RootStart = FVector(0.0f, 0.0f, 0.0f);
    private const FVector RootEnd = FVector(150.0f, 0.0f, 0.0f);
    private const FVector ChildLocalLocation = FVector(0.0f, 80.0f, 0.0f);
    private const float32 TweenDurationSec = 0.25f;
    private const float32 DriftToleranceCm = 1.0f;
    private const float32 SweepProofCm = 50.0f;

    private FCk_Handle_Transform _RootTH;
    private FCk_Handle_SceneNode _Child;
    private FCk_Handle_Tween _Tween;

    private float32 _MaxDrift = 0.0f;
    private float32 _MaxRootX = -1.0e9f;
    private float32 _MinRootX = 1.0e9f;
    private int32 _SampleCount = 0;
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

        // Yoyo with LoopCount=1 = one round trip (forward + reverse).
        _Tween = utils_tween::Create_TweenEntityLocation(
            _RootTH, RootEnd, TweenDurationSec,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::Yoyo,
            1, 0.0f,
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

        auto RX = float32(RootXform.GetLocation().X);
        if (RX > _MaxRootX) { _MaxRootX = RX; }
        if (RX < _MinRootX) { _MinRootX = RX; }

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
        Assert_True(_MaxRootX > SweepProofCm,
            f"Yoyo forward leg should sweep root X past {SweepProofCm}cm (max observed: {_MaxRootX}cm) — without this, the test can't prove the yoyo went forward");
        Assert_True(_MinRootX < SweepProofCm,
            f"Yoyo reverse leg should sweep root X back below {SweepProofCm}cm (min observed: {_MinRootX}cm) — without this, the test can't prove the yoyo reversed");
        Assert_True(_MaxDrift < DriftToleranceCm,
            f"Leaf must track yoyo-tweened root within {DriftToleranceCm}cm on BOTH legs (max drift observed: {_MaxDrift}cm)");

        FinishSuccess();
    }
}
