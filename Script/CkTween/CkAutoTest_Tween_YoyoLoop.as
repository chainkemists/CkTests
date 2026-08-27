// Language=angelscript

//============================================================================
// CK TWEEN - AUTOMATION TEST: YOYO LOOP TYPE
//============================================================================
//
// Verifies LoopType::Yoyo with a finite loop count fires OnLoop on each
// direction change and OnComplete after the final loop:
//   1. Create a Linear float tween 0->100 over 0.10s with LoopType::Yoyo
//      and LoopCount=2 (one forward + one backward, then complete).
//   2. Bind OnLoop and OnComplete.
//   3. OnLoop fires at least once before OnComplete; OnComplete fires
//      exactly once.
//
// Companion to Tween_LoopRestart - that one tests Restart-loop direction
// preservation; this one tests Yoyo direction reversal.
//============================================================================

class UCk_AutoTest_Tween_YoyoLoop : UCk_AutoTest_Base
{
    private FCk_Handle_Tween _Tween;
    private int32 _LoopCount = 0;
    private int32 _CompleteCount = 0;
    private bool _LoopFiredBeforeComplete = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Tween = utils_tween::Create_TweenFloat(
            LocalHandle,
            0.0f,
            100.0f,
            0.10f,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::Yoyo,
            2,
            0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        utils_tween::BindTo_OnLoop(
            _Tween,
            FCk_Delegate_Tween_OnLoop(this, n"OnLoop"));
        utils_tween::BindTo_OnComplete(
            _Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnComplete"));
    }

    UFUNCTION()
    private void OnLoop(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnLoop InPayload)
    {
        _LoopCount++;
        if (_CompleteCount == 0)
        {
            _LoopFiredBeforeComplete = true;
        }
    }

    UFUNCTION()
    private void OnComplete(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnComplete InPayload)
    {
        if (IsFinished()) { return; }
        _CompleteCount++;

        Assert_True(_LoopCount >= 1,
            f"OnLoop should fire at least once on a Yoyo tween before OnComplete (got {_LoopCount})");
        Assert_True(_LoopFiredBeforeComplete,
            "First OnLoop should fire before OnComplete");
        Assert_Equals_Int(_CompleteCount, 1,
            "OnComplete should fire exactly once at the end of a finite-loop Yoyo");

        FinishSuccess();
    }
}
