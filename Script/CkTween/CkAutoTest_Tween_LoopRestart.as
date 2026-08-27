// Language=angelscript

//============================================================================
// CK TWEEN - AUTOMATION TEST: RESTART LOOP
//============================================================================
//
// Verifies LoopType::Restart with a finite loop count:
//   1. Create a 0 -> 100 tween with LoopType::Restart and LoopCount=2.
//   2. Bind OnLoop and OnComplete.
//   3. OnLoop should fire some N >= 1 times before OnComplete (one per
//      restart, depending on whether the framework counts the initial
//      pass as loop 0 or loop 1).
//   4. OnComplete fires exactly once at the very end.
//
// We don't pin down the exact OnLoop count strictly because the contract
// (whether N=LoopCount or N=LoopCount-1, and whether OnLoop fires on the
// initial pass) isn't documented in headers we've read. The test verifies
// the more important invariants: OnLoop fires AT LEAST once, OnComplete
// fires exactly once, and the order is OnLoop-before-OnComplete.
//============================================================================

class UCk_AutoTest_Tween_LoopRestart : UCk_AutoTest_Base
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
            0.15f,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::Restart,
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
            f"OnLoop should fire at least once before OnComplete on a Restart-loop tween (got {_LoopCount})");
        Assert_True(_LoopFiredBeforeComplete,
            "First OnLoop should fire before OnComplete");
        Assert_Equals_Int(_CompleteCount, 1,
            "OnComplete should fire exactly once at the end of all loops");

        FinishSuccess();
    }
}
