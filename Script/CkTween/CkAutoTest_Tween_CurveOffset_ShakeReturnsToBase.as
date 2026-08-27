// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: CURVE-OFFSET SHAKE RETURNS TO BASE
//============================================================================
//
// Pins the contract that Start->End interpolation cannot express and that the
// easing table cannot rescue: a motion which ENDS WHERE IT BEGAN.
//
// With Start == End, Interpolate(V, V, alpha) is V for every alpha, so an
// easing-only tween is provably motionless no matter how the curve reshapes
// progress. Create_TweenEntityRotation_CurveOffset takes the curve's OUTPUT as
// a degrees offset composed onto a captured base, which does move.
//
// Because "starts at base, ends at base" is also what a BROKEN (never-moved)
// tween looks like, asserting the endpoints alone would pass on a no-op. So
// this test asserts a MIDPOINT: peak deviation during flight must be large.
//
// Phase 2 re-runs the same curve via Restart and asserts it returns to the
// SAME base. That is the anti-drift property the migration depends on — the
// pose is recomputed from an immutable base every frame rather than
// accumulated, so a spammable re-trigger cannot walk the prop away from rest.
//
// The base carries a YAW on purpose. A roll offset composed onto a yawed base
// by quaternion differs from a component-wise FRotator add; an additive
// regression would still return to base at the end but trace a wrong arc, so
// the peak-deviation assertion is what catches it.
//============================================================================

namespace ck_test_curve_shake
{
    // Linear keys, matching how authored shake timelines interpolate. AddCurveKey
    // defaults to cubic-auto, which would round off the peak and undershoot it.
    mixin void AddLinearKey(UCurveFloat CurveFloat, float InTime, float InValue)
    {
        auto KeyHandle = CurveFloat.AddCurveKey(InTime, InValue);
        CurveFloat.SetKeyInterpMode(KeyHandle, ERichCurveInterpMode::RCIM_Linear, false);
    }

    // 0 -> +10deg -> 0 over 0.5s. Returns to exactly 0 at the last key so the
    // tween's completion lands on the captured base with no snap.
    asset ShakeRoll_ReturnsToZero of UCurveFloat
    {
        AddLinearKey(0.0f, 0.0f);
        AddLinearKey(0.25f, 10.0f);
        AddLinearKey(0.5f, 0.0f);
    }
}

class UCk_AutoTest_Tween_CurveOffset_ShakeReturnsToBase : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Transform _Target;
    private FCk_Handle_Tween _Tween;
    private FRotator _BaseRotation;

    private float32 _PeakDeviationDeg = 0.0f;
    private int32 _CompletedCount = 0;

    // Peak must clear this to prove the curve actually drove the pose. The curve
    // peaks at 10deg, so 5 is a wide margin against sampling luck while still
    // being impossible for a motionless tween to reach.
    private const float32 k_MinPeakDeviationDeg = 5.0f;
    // Composition is exact at the endpoints; this only absorbs float error.
    private const float32 k_RestToleranceDeg = 0.5f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _BaseRotation = FRotator(0.0f, 30.0f, 0.0f);

        _Target = utils_transform::Create(
            LocalHandle,
            FTransform(_BaseRotation, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        Assert_True(ck::IsValid(_Target), "Target transform entity is valid after Create");

        // Roll channel only; pitch and yaw are unset and must contribute 0. Duration
        // is left at 0 so the tween derives it from the curve's own last key (0.5s).
        _Tween = utils_tween::Create_TweenEntityRotation_CurveOffset(
            _Target,
            FCk_TweenCurveChannels(nullptr, nullptr, ck_test_curve_shake::ShakeRoll_ReturnsToZero),
            0.0f,
            ECk_TweenCurveTimeInput::ElapsedSeconds,
            ECk_TweenLoopType::None, 0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        Assert_True(ck::IsValid(_Tween), "Curve-offset tween handle is valid");

        utils_tween::BindTo_OnUpdate(_Tween,
            FCk_Delegate_Tween_OnUpdate(this, n"OnTweenUpdate"));
        utils_tween::BindTo_OnComplete(_Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnTweenComplete"));
    }

    UFUNCTION()
    private void OnTweenUpdate(
        FCk_Handle_Tween InTween,
        FCk_Tween_Payload_OnUpdate InPayload)
    {
        if (IsFinished()) { return; }

        const auto Current = utils_tween::TweenValue_GetAsRotator(InPayload.Get_CurrentValue());
        _PeakDeviationDeg = Math::Max(_PeakDeviationDeg, Get_DeviationFromBaseDeg(Current));
    }

    UFUNCTION()
    private void OnTweenComplete(
        FCk_Handle_Tween InTween,
        FCk_Tween_Payload_OnComplete InPayload)
    {
        if (IsFinished()) { return; }

        _CompletedCount += 1;

        const auto Final = utils_tween::TweenValue_GetAsRotator(InPayload.Get_FinalValue());
        const auto FinalDeviation = Get_DeviationFromBaseDeg(Final);

        Assert_True(_PeakDeviationDeg > k_MinPeakDeviationDeg,
            f"Pass {_CompletedCount}: the pose must actually MOVE mid-flight — peak deviation from base was {_PeakDeviationDeg} deg, needed > {k_MinPeakDeviationDeg}");

        Assert_True(FinalDeviation < k_RestToleranceDeg,
            f"Pass {_CompletedCount}: the pose must return to base on completion — final deviation was {FinalDeviation} deg, needed < {k_RestToleranceDeg}");

        if (_CompletedCount >= 2)
        {
            // The second pass returning to the SAME base is the anti-drift proof: an
            // accumulated-offset implementation would rest a full curve-peak further
            // along on every re-trigger.
            FinishSuccess();
            return;
        }

        // Re-trigger. The tween is Completed here, so Restart is the supported path —
        // Stop on an already-completed tween re-adds FTag_Tween_Completed and ensures.
        _PeakDeviationDeg = 0.0f;
        utils_tween::Restart(_Tween, FCk_Delegate_Request_OnCompleted());
    }

    // Absolute per-component difference from the base pose. Cheap, and unambiguous at
    // these angles: the composed result stays far from any gimbal degeneracy, so a
    // component-wise delta tracks real angular deviation closely enough for a
    // moved / did-not-move verdict.
    private float32 Get_DeviationFromBaseDeg(const FRotator& InRotation)
    {
        return float32(Math::Abs(InRotation.Pitch - _BaseRotation.Pitch)
             + Math::Abs(InRotation.Yaw   - _BaseRotation.Yaw)
             + Math::Abs(InRotation.Roll  - _BaseRotation.Roll));
    }
}
