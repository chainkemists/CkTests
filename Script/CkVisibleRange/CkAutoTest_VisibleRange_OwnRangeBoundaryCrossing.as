// Language=angelscript

//============================================================================
// CK VISIBLE RANGE — AUTOMATION TEST: own-range boundary crossing
//============================================================================
//
// Composes VisibleRange with UpdateInterval = 0 (every tick, no cadence
// complexity here — see CkAutoTest_VisibleRange_CadenceGatesUpdates for
// that). Moves the caller-supplied distance across the MaxRange boundary
// and asserts FTag_VisibleRange_Hidden tracks it both ways.
//============================================================================

class UCk_AutoTest_VisibleRange_OwnRangeBoundaryCrossing : UCk_AutoTest_Base
{
    private FCk_Handle_VisibleRange _VR;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_VisibleRange_ParamsData(500.0f);
        _VR = utils_visible_range::Add(LocalHandle, Params);

        Assert_True(!utils_visible_range::Get_IsHidden(_VR),
            "Should start visible: default distance (0) is inside MaxRange (500)");

        utils_visible_range::Update_Distance(_VR, 1000.0f);
        WaitOneFrame(n"OnOutOfRangeSettled");
    }

    UFUNCTION()
    private void OnOutOfRangeSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_visible_range::Get_IsHidden(_VR),
            "Should be hidden after moving to distance 1000 (beyond MaxRange 500)");

        utils_visible_range::Update_Distance(_VR, 100.0f);
        WaitOneFrame(n"OnBackInRangeSettled");
    }

    UFUNCTION()
    private void OnBackInRangeSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_visible_range::Get_IsHidden(_VR),
            "Should be visible again after returning to distance 100 (inside MaxRange 500)");
        FinishSuccess();
    }
}
