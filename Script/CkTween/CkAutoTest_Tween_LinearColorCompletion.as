// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: LINEAR COLOR COMPLETION
//============================================================================
//
// Verifies the linear-color tween API:
//   1. Create a Linear color tween from black (0,0,0,1) to white (1,1,1,1)
//      over 0.25s.
//   2. Bind OnComplete.
//   3. Callback fires with FinalValue == white.
//   4. TweenValue_IsLinearColor reports true on the payload value.
//
// Pairs with the existing FloatCompletion / VectorCompletion tests to
// cover the four primary tween value types (Float, Vector, Rotator and
// LinearColor).
//============================================================================

class UCk_AutoTest_Tween_LinearColorCompletion : UCk_AutoTest_Base
{
    private FCk_Handle_Tween _Tween;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Tween = utils_tween::Create_TweenLinearColor(
            LocalHandle,
            FLinearColor(0.0f, 0.0f, 0.0f, 1.0f),
            FLinearColor(1.0f, 1.0f, 1.0f, 1.0f),
            0.25f,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None,
            0,
            0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        utils_tween::BindTo_OnComplete(
            _Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnComplete"));
    }

    UFUNCTION()
    private void OnComplete(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnComplete InPayload)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_tween::TweenValue_IsLinearColor(InPayload.Get_FinalValue()),
            "OnComplete payload should be a LinearColor tween value");

        // FLinearColor components are floats — use tolerance comparison
        // to be safe against any internal interpolation rounding.
        auto Tol = 0.001f;
        auto Final = utils_tween::TweenValue_GetAsLinearColor(InPayload.Get_FinalValue());
        Assert_True(Math::Abs(Final.R - 1.0f) < Tol &&
                    Math::Abs(Final.G - 1.0f) < Tol &&
                    Math::Abs(Final.B - 1.0f) < Tol &&
                    Math::Abs(Final.A - 1.0f) < Tol,
            f"FinalValue should be (1,1,1,1) (got R={Final.R},G={Final.G},B={Final.B},A={Final.A})");

        FinishSuccess();
    }
}
