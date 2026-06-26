// Language=angelscript
//
// CK TARGETING — AUTOMATION TEST: ECk_Lifetime::AfterOneFrame destroys entity
// Create with AfterOneFrame queues immediate destruction; after one frame the
// returned handle is no longer valid.

class UCk_AutoTest_Targeting_LifetimeAfterOneFrameDestroysEntity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_Transform _Ephemeral;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Ephemeral = utils_target_point::Create_FromLocation(
            LocalHandle, FVector(0.0f, 0.0f, 0.0f), ECk_Lifetime::AfterOneFrame);

        Assert_True(utils_handle::Get_IsValid(_Ephemeral),
            "Pre-tick: ephemeral TargetPoint should still be valid in the same frame as Create");

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_handle::Get_IsValid(_Ephemeral),
            "Post-tick: ephemeral TargetPoint should be invalid after AfterOneFrame destroy");

        FinishSuccess();
    }
}
