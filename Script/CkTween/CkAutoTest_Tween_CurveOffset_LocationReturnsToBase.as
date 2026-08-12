// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: CURVE-OFFSET LOCATION RETURNS TO BASE
//============================================================================
//
// Location sibling of CkAutoTest_Tween_CurveOffset_ShakeReturnsToBase — pins
// the VectorOffset arm of the curve-drive (the rotation test only exercises
// RotatorOffset): the curve's output is WORLD-axis units added onto a base
// location captured at creation.
//
// Same shape as the rotation test, for the same reasons: a midpoint assertion
// (peak displacement must be large, because "starts at base, ends at base" is
// also what a broken never-moved tween looks like), then a Restart pass that
// must return to the SAME base — the anti-drift property, plus coverage of
// the base-recapture path's VectorOffset arm.
//============================================================================

namespace ck_test_curve_bounce
{
    mixin void AddLinearKeyBounce(UCurveFloat CurveFloat, float InTime, float InValue)
    {
        auto KeyHandle = CurveFloat.AddCurveKey(InTime, InValue);
        CurveFloat.SetKeyInterpMode(KeyHandle, ERichCurveInterpMode::RCIM_Linear, false);
    }

    // 0 -> +40 units -> 0 over 0.5s; ends at exactly 0 so completion lands on base.
    asset BounceZ_ReturnsToZero of UCurveFloat
    {
        AddLinearKeyBounce(0.0f, 0.0f);
        AddLinearKeyBounce(0.25f, 40.0f);
        AddLinearKeyBounce(0.5f, 0.0f);
    }
}

class UCk_AutoTest_Tween_CurveOffset_LocationReturnsToBase : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Transform _Target;
    private FCk_Handle_Tween _Tween;
    private FVector _BaseLocation;

    private float32 _PeakDisplacement = 0.0f;
    private int32 _CompletedCount = 0;

    // Curve peaks at 40 units; 20 is a wide margin a motionless tween cannot reach.
    private const float32 k_MinPeakDisplacement = 20.0f;
    private const float32 k_RestTolerance = 0.1f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // A non-origin base, so returning to it cannot be confused with a zeroed write.
        _BaseLocation = FVector(100.0, 200.0, 50.0);

        _Target = utils_transform::Create(
            LocalHandle,
            FTransform(FRotator::ZeroRotator, _BaseLocation, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        Assert_True(ck::IsValid(_Target), "Target transform entity is valid after Create");

        // Z channel only; X and Y are unset and must contribute 0. Duration derives
        // from the curve's own last key (0.5s).
        _Tween = utils_tween::Create_TweenEntityLocation_CurveOffset(
            _Target,
            FCk_TweenCurveChannels(nullptr, nullptr, ck_test_curve_bounce::BounceZ_ReturnsToZero),
            0.0f,
            ECk_TweenCurveTimeInput::ElapsedSeconds,
            ECk_TweenLoopType::None, 0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        Assert_True(ck::IsValid(_Tween), "Curve-offset location tween handle is valid");

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

        const auto Current = utils_tween::TweenValue_GetAsVector(InPayload.Get_CurrentValue());
        _PeakDisplacement = Math::Max(_PeakDisplacement, float32((Current - _BaseLocation).Size()));
    }

    UFUNCTION()
    private void OnTweenComplete(
        FCk_Handle_Tween InTween,
        FCk_Tween_Payload_OnComplete InPayload)
    {
        if (IsFinished()) { return; }

        _CompletedCount += 1;

        const auto Final = utils_tween::TweenValue_GetAsVector(InPayload.Get_FinalValue());
        const auto FinalDisplacement = float32((Final - _BaseLocation).Size());

        Assert_True(_PeakDisplacement > k_MinPeakDisplacement,
            f"Pass {_CompletedCount}: the location must actually MOVE mid-flight — peak displacement was {_PeakDisplacement}, needed > {k_MinPeakDisplacement}");

        Assert_True(FinalDisplacement < k_RestTolerance,
            f"Pass {_CompletedCount}: the location must return to base on completion — final displacement was {FinalDisplacement}, needed < {k_RestTolerance}");

        if (_CompletedCount >= 2)
        {
            FinishSuccess();
            return;
        }

        _PeakDisplacement = 0.0f;
        utils_tween::Restart(_Tween, FCk_Delegate_Request_OnCompleted());
    }
}
