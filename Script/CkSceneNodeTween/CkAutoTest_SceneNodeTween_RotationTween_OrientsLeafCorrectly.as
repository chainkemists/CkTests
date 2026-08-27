// Language=angelscript

//============================================================================
// CK SCENE NODE + TWEEN - AUTOMATION TEST: ROTATION TWEEN, LEAF ORIENTED
//============================================================================
//
// Rotation-tween variant: the root's rotation is tweened (not its location),
// and the leaf's world location must reflect the composed rotation pivoting
// the child's local offset around the root. Different code path from the
// location-tween cases: the tween writes the root's quaternion each tick,
// and SceneNode propagation must observe that rotation update - not just
// translation updates.
//
// Setup:
//   Root SceneNode under an identity-transform parent.
//   Child SceneNode at local offset (100, 0, 0).
//   Tween rotates root from yaw=0 to yaw=90 over the duration.
//
// At completion:
//   Root yaw 90 rotates child's local (100, 0, 0) around the root to
//   world (0, 100, 0). Each per-frame sample checks the AS-composed
//   prediction matches.
//============================================================================

class UCk_AutoTest_SceneNodeTween_RotationTween_OrientsLeafCorrectly : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector ChildLocalLocation = FVector(100.0f, 0.0f, 0.0f);
    private const FRotator RootEndRotation = FRotator(0.0f, 90.0f, 0.0f);
    private const FVector ExpectedLeafEnd = FVector(0.0f, 100.0f, 0.0f);
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

        _Tween = utils_tween::Create_TweenEntityRotation(
            _RootTH, RootEndRotation, TweenDurationSec,
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
        auto DX = Math::Abs(FinalLeaf.X - ExpectedLeafEnd.X);
        auto DY = Math::Abs(FinalLeaf.Y - ExpectedLeafEnd.Y);
        auto DZ = Math::Abs(FinalLeaf.Z - ExpectedLeafEnd.Z);

        Assert_True(DX < DriftToleranceCm,
            f"At yaw=90 rotation tween completion, leaf X should be {ExpectedLeafEnd.X} (got {FinalLeaf.X})");
        Assert_True(DY < DriftToleranceCm,
            f"At yaw=90 rotation tween completion, leaf Y should be {ExpectedLeafEnd.Y} (got {FinalLeaf.Y})");
        Assert_True(DZ < DriftToleranceCm,
            f"At yaw=90 rotation tween completion, leaf Z should be {ExpectedLeafEnd.Z} (got {FinalLeaf.Z})");

        Assert_True(_MaxDrift < DriftToleranceCm,
            f"Leaf must track rotation-tween across every sampled frame within {DriftToleranceCm}cm (max drift observed: {_MaxDrift}cm)");

        FinishSuccess();
    }
}
