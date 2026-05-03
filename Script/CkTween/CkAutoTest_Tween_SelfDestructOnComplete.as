// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: SELF-DESTRUCT ON COMPLETE
//============================================================================
//
// Verifies ECk_TweenCompletionBehavior::SelfDestruct destroys the tween
// entity once it completes:
//   1. Create a Linear float tween 0->100 over 0.20s with
//      CompletionBehavior::SelfDestruct.
//   2. Bind OnComplete.
//   3. After OnComplete fires, poll on tick until ck::IsValid(tween) is
//      false — that confirms the tween entity was destroyed.
//
// Catches the regression where SelfDestruct doesn't actually clean up,
// leaving leaked tween entities accumulating across plays.
//============================================================================

class UCk_AutoTest_Tween_SelfDestructOnComplete : UCk_AutoTest_Base
{
    private FCk_Handle_Tween _Tween;
    private bool _CompleteFired = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Tween = utils_tween::Create_TweenFloat(
            LocalHandle,
            0.0f,
            100.0f,
            0.20f,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None,
            0,
            0.0f,
            ECk_TweenCompletionBehavior::SelfDestruct);

        utils_tween::BindTo_OnComplete(
            _Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnComplete"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnComplete(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnComplete InPayload)
    {
        _CompleteFired = true;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (!_CompleteFired) { return; }

        if (!ck::IsValid(_Tween))
        {
            Assert_True(true,
                "Tween with CompletionBehavior::SelfDestruct should be invalid after OnComplete fires");
            FinishSuccess();
        }
    }
}
