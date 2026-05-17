// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: COMPLETION BEHAVIOR — KEEP ENTITY
//============================================================================
//
// Pins ECk_TweenCompletionBehavior::DoNothing — the tween entity remains
// valid after OnComplete fires (no auto-destruction).
//
// Pairs with the existing CkAutoTest_Tween_SelfDestructOnComplete test
// which pins the opposite behavior (SelfDestruct destroys the entity).
//
// We bind OnComplete, then after the tween reports complete we WaitOneFrame
// to allow any deferred destruction to settle, then assert the tween
// handle is still valid.
//============================================================================

class UCk_AutoTest_Tween_CompletionBehavior_KeepEntity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Tween _Tween;
    private bool _CompleteObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Tween = utils_tween::Create_TweenFloat(
            LocalHandle, 0.0f, 100.0f, 0.25f,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None, 0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        utils_tween::BindTo_OnComplete(_Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnComplete"));
    }

    UFUNCTION()
    private void OnComplete(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnComplete InPayload)
    {
        if (_CompleteObserved) { return; }
        _CompleteObserved = true;

        // Tween entity should still be valid in this callback.
        Assert_True(ck::IsValid(_Tween),
            "Tween handle must remain valid inside the OnComplete callback under DoNothing behavior");

        WaitOneFrame(n"OnSettled_AfterComplete");
    }

    UFUNCTION()
    private void OnSettled_AfterComplete(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(ck::IsValid(_Tween),
            "Tween handle must STILL be valid one frame after OnComplete under DoNothing behavior (only SelfDestruct should destroy the entity)");

        FinishSuccess();
    }
}
