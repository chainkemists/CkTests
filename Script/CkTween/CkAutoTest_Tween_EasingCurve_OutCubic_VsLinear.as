// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: EASING CURVE — OUT-CUBIC VS LINEAR
//============================================================================
//
// Pins the easing-table contract: at the same alpha (mid-flight, ~50% time
// elapsed), an OutCubic-eased tween's value differs from a Linear tween's
// value in the expected direction. OutCubic at α=0.5 maps to ~0.875 (well
// above the linear 0.5).
//
// Setup: two parallel float tweens 0->100 over 0.5s. Bind OnUpdate on both
// to capture each tween's mid-flight value at the same world time. Verify
// the captured values differ by at least a sane epsilon (OutCubic value
// should be significantly higher than Linear at the same elapsed time).
//============================================================================

class UCk_AutoTest_Tween_EasingCurve_OutCubic_VsLinear : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Tween _LinearTween;
    private FCk_Handle_Tween _CubicTween;
    private float _LinearMidValue = -1.0f;
    private float _CubicMidValue = -1.0f;
    private bool _LinearMidCaptured = false;
    private bool _CubicMidCaptured = false;
    private int _LinearCompleted = 0;
    private int _CubicCompleted = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _LinearTween = utils_tween::Create_TweenFloat(
            LocalHandle, 0.0f, 100.0f, 0.5f,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None, 0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);
        utils_tween::BindTo_OnUpdate(_LinearTween,
            FCk_Delegate_Tween_OnUpdate(this, n"OnLinearUpdate"));
        utils_tween::BindTo_OnComplete(_LinearTween,
            FCk_Delegate_Tween_OnComplete(this, n"OnLinearComplete"));

        _CubicTween = utils_tween::Create_TweenFloat(
            LocalHandle, 0.0f, 100.0f, 0.5f,
            ECk_TweenEasing::OutCubic,
            ECk_TweenLoopType::None, 0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);
        utils_tween::BindTo_OnUpdate(_CubicTween,
            FCk_Delegate_Tween_OnUpdate(this, n"OnCubicUpdate"));
        utils_tween::BindTo_OnComplete(_CubicTween,
            FCk_Delegate_Tween_OnComplete(this, n"OnCubicComplete"));
    }

    UFUNCTION()
    private void OnLinearUpdate(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnUpdate InPayload)
    {
        if (_LinearMidCaptured) { return; }
        auto Progress = InPayload.Get_Progress().Get_Value();
        if (Progress >= 0.45f && Progress <= 0.55f)
        {
            _LinearMidValue = utils_tween::TweenValue_GetAsFloat(InPayload.Get_CurrentValue());
            _LinearMidCaptured = true;
        }
    }

    UFUNCTION()
    private void OnCubicUpdate(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnUpdate InPayload)
    {
        if (_CubicMidCaptured) { return; }
        auto Progress = InPayload.Get_Progress().Get_Value();
        if (Progress >= 0.45f && Progress <= 0.55f)
        {
            _CubicMidValue = utils_tween::TweenValue_GetAsFloat(InPayload.Get_CurrentValue());
            _CubicMidCaptured = true;
        }
    }

    UFUNCTION()
    private void OnLinearComplete(FCk_Handle_Tween H, FCk_Tween_Payload_OnComplete P)
    {
        _LinearCompleted += 1;
        TryFinish();
    }

    UFUNCTION()
    private void OnCubicComplete(FCk_Handle_Tween H, FCk_Tween_Payload_OnComplete P)
    {
        _CubicCompleted += 1;
        TryFinish();
    }

    private void TryFinish()
    {
        if (IsFinished()) { return; }
        if (_LinearCompleted == 0 || _CubicCompleted == 0) { return; }

        Assert_True(_LinearMidCaptured,
            "Linear tween should have produced an OnUpdate at ~50% progress");
        Assert_True(_CubicMidCaptured,
            "OutCubic tween should have produced an OnUpdate at ~50% progress");

        // OutCubic at α=0.5 maps to 0.875; Linear at α=0.5 maps to 0.5.
        // On a 0->100 range that's ~87.5 vs ~50. Require Cubic to be
        // at least 20 units above Linear (very loose to absorb the
        // exact-progress capture window).
        Assert_True(_CubicMidValue > _LinearMidValue + 20.0f,
            f"OutCubic mid-flight value ({_CubicMidValue}) must be substantially higher than Linear ({_LinearMidValue})");

        FinishSuccess();
    }
}
