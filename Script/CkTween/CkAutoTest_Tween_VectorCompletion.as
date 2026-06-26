// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: VECTOR COMPLETION
//============================================================================
//
// Verifies the vector-tween API:
//   1. Create a Linear vector tween (0,0,0) → (10,20,30) over 0.25s.
//   2. Bind OnComplete.
//   3. Callback fires with FinalValue == (10,20,30).
//   4. TweenValue_IsVector reports true on the payload value.
//============================================================================

class UCk_AutoTest_Tween_VectorCompletion : UCk_AutoTest_Base
{
    private FCk_Handle_Tween _Tween;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Tween = utils_tween::Create_TweenVector(
            LocalHandle,
            FVector(0.0f, 0.0f, 0.0f),
            FVector(10.0f, 20.0f, 30.0f),
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

        Assert_True(utils_tween::TweenValue_IsVector(InPayload.Get_FinalValue()),
            "OnComplete payload should be a vector tween value");

        auto Final = utils_tween::TweenValue_GetAsVector(InPayload.Get_FinalValue());
        Assert_True(Final.X == 10.0f && Final.Y == 20.0f && Final.Z == 30.0f,
            f"FinalValue should be (10,20,30) (got ({Final.X},{Final.Y},{Final.Z}))");

        FinishSuccess();
    }
}
