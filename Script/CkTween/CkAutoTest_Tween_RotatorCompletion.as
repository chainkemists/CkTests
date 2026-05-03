// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: ROTATOR COMPLETION
//============================================================================
//
// Verifies the rotator-tween API:
//   1. Create a Linear rotator tween from zero to (45, 90, 135) over 0.25s.
//   2. Bind OnComplete.
//   3. Callback fires with FinalValue == (45, 90, 135) (within tolerance).
//   4. TweenValue_IsRotator reports true on the payload value.
//
// Completes the four-type tween matrix alongside FloatCompletion,
// VectorCompletion and LinearColorCompletion.
//============================================================================

class UCk_AutoTest_Tween_RotatorCompletion : UCk_AutoTest_Base
{
    private FCk_Handle_Tween _Tween;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Tween = utils_tween::Create_TweenRotator(
            LocalHandle,
            FRotator::ZeroRotator,
            FRotator(45.0f, 90.0f, 135.0f),
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

        Assert_True(utils_tween::TweenValue_IsRotator(InPayload.Get_FinalValue()),
            "OnComplete payload should be a Rotator tween value");

        // FRotator interpolation may go through a quaternion path internally;
        // use tolerance comparison.
        auto Tol = 0.01f;
        auto Final = utils_tween::TweenValue_GetAsRotator(InPayload.Get_FinalValue());
        Assert_True(Math::Abs(Final.Pitch - 45.0f)  < Tol &&
                    Math::Abs(Final.Yaw   - 90.0f)  < Tol &&
                    Math::Abs(Final.Roll  - 135.0f) < Tol,
            f"FinalValue should be (45,90,135) (got P={Final.Pitch},Y={Final.Yaw},R={Final.Roll})");

        FinishSuccess();
    }
}
