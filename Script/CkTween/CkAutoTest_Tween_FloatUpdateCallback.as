// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: FLOAT UPDATE CALLBACK
//============================================================================
//
// Verifies that OnUpdate fires repeatedly during a tween (not just at
// completion):
//   1. Create a Linear float tween 0 → 100 over 0.5s.
//   2. Bind OnUpdate.
//   3. Wait until OnComplete.
//   4. Verify OnUpdate was called at least 2 times before completion (a
//      single fire could be a degenerate "fires only at end" regression
//      mode — multiple fires confirm the per-tick update path).
//   5. Verify OnUpdate's payload Progress was monotonically increasing.
//============================================================================

class UCk_AutoTest_Tween_FloatUpdateCallback : UCk_AutoTest_Base
{
    private FCk_Handle_Tween _Tween;
    private int32 _UpdateCount = 0;
    private float _LastProgress = -1.0f;
    private bool _ProgressWasMonotonic = true;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Tween = utils_tween::Create_TweenFloat(
            LocalHandle,
            0.0f,
            100.0f,
            0.5f,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None,
            0,
            0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        utils_tween::BindTo_OnUpdate(
            _Tween,
            FCk_Delegate_Tween_OnUpdate(this, n"OnUpdate"));
        utils_tween::BindTo_OnComplete(
            _Tween,
            FCk_Delegate_Tween_OnComplete(this, n"OnComplete"));
    }

    UFUNCTION()
    private void OnUpdate(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnUpdate InPayload)
    {
        _UpdateCount++;
        auto Progress = InPayload.Get_Progress().Get_Value();
        if (Progress < _LastProgress)
        {
            _ProgressWasMonotonic = false;
        }
        _LastProgress = Progress;
    }

    UFUNCTION()
    private void OnComplete(
        FCk_Handle_Tween InHandle,
        FCk_Tween_Payload_OnComplete InPayload)
    {
        if (IsFinished()) { return; }

        Assert_True(_UpdateCount >= 2,
            f"OnUpdate should fire multiple times during a 0.5s tween (got {_UpdateCount} fires)");
        Assert_True(_ProgressWasMonotonic,
            "OnUpdate payload Progress should be monotonically non-decreasing");

        FinishSuccess();
    }
}
