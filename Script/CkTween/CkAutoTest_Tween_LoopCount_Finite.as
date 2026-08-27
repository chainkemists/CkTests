// Language=angelscript

//============================================================================
// CK TWEEN - AUTOMATION TEST: LOOP COUNT FINITE
//============================================================================
//
// Pins the finite-loop contract: a tween with LoopType::Restart and a
// finite _LoopCount fires OnComplete exactly once AFTER all loops finish,
// and further ticks do not produce additional OnComplete fires.
//
// We intentionally do NOT pin the OnLoop fire count (the existing
// CkAutoTest_Tween_LoopRestart test notes this contract isn't documented).
// This test pins the post-completion finality contract: OnComplete fires
// once, and the tween's progress stays at >= 1.0 indefinitely.
//============================================================================

class UCk_AutoTest_Tween_LoopCount_Finite : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Tween _Tween;
    private int32 _CompleteCount = 0;
    private bool _PostCompleteCheckScheduled = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // 3 loops at 0.1s each = ~0.3s total, well within the 4s timeout.
        _Tween = utils_tween::Create_TweenFloat(
            LocalHandle, 0.0f, 100.0f, 0.1f,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::Restart,
            3,    // LoopCount
            0.0f, // YoyoDelay
            ECk_TweenCompletionBehavior::DoNothing);

        utils_tween::BindTo_OnComplete(_Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnComplete"));
    }

    UFUNCTION()
    private void OnComplete(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnComplete InPayload)
    {
        _CompleteCount += 1;

        if (_PostCompleteCheckScheduled) { return; }
        _PostCompleteCheckScheduled = true;

        // Wait 1s after the first OnComplete and verify no additional fires.
        System::SetTimer(this, n"OnPostCompleteDeadline", 1.0f, false);
    }

    UFUNCTION()
    private void OnPostCompleteDeadline()
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_CompleteCount, 1,
            "OnComplete must fire exactly once after the finite loop count is exhausted (further ticks must NOT trigger additional completions)");

        auto Progress = utils_tween::Get_Progress(_Tween);
        Assert_True(Progress.Get_Value() >= 1.0f,
            f"Tween progress must stay at >= 1.0 after the finite loop count is exhausted (got {Progress.Get_Value()})");

        FinishSuccess();
    }
}
