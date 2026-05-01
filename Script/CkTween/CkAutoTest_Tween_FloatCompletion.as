// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: FLOAT COMPLETION
//============================================================================
//
// Smoke test for the float-tween API:
//   1. Create a Linear float tween 0 → 100 over 0.25s.
//   2. Bind OnComplete.
//   3. The callback fires with FinalValue == 100.
//   4. Get_CurrentValue == 100 and Get_Progress == 1.0 at completion.
//============================================================================

class UCk_AutoTest_Tween_FloatCompletion : UCk_AutoTest_Base
{
    private FCk_Handle_Tween _Tween;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Tween = utils_tween::Create_TweenFloat(
            LocalHandle,
            0.0f,
            100.0f,
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

        auto FinalValue = utils_tween::TweenValue_GetAsFloat(InPayload.Get_FinalValue());
        Assert_True(FinalValue == 100.0f,
            f"OnComplete payload FinalValue should be 100 (got {FinalValue})");

        auto LiveValue = utils_tween::TweenValue_GetAsFloat(utils_tween::Get_CurrentValue(_Tween));
        Assert_True(LiveValue == 100.0f,
            f"Get_CurrentValue at completion should be 100 (got {LiveValue})");

        auto Progress = utils_tween::Get_Progress(_Tween);
        Assert_True(Progress.Get_Value() >= 1.0f,
            f"Get_Progress at completion should be >= 1.0 (got {Progress.Get_Value()})");

        FinishSuccess();
    }
}
