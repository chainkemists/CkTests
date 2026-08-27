// Language=angelscript

//============================================================================
// CK TRANSFORM - AUTOMATION TEST: ForceRefresh REBROADCASTS CURRENT VALUE
//============================================================================
//
// Pins the Request_ForceRefresh contract: it fires OnUpdate with the
// CURRENT transform value, regardless of whether the value changed. The
// mechanism gameplay code uses to force-resync downstream listeners that
// missed an earlier broadcast (e.g. late-bound observers).
//
// The refactor's processor simplification could regress this by treating
// ForceRefresh as a no-op when the transform didn't change.
//
// Setup:
//   - Add a Transform at a known location.
//   - WaitOneFrame so the initial setup-side OnUpdate flushes.
//   - Bind OnUpdate AFTER the flush with a counter.
//   - Issue Request_ForceRefresh on the unchanged transform.
//   - WaitOneFrame.
//
// Pass: OnUpdate fires exactly once after the ForceRefresh, with the
//   transform's existing (unchanged) value.
//============================================================================

class UCk_AutoTest_Transform_ForceRefreshRebroadcasts : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private const FVector ExpectedLocation = FVector(50.0f, 100.0f, 25.0f);
    private const float32 PositionToleranceCm = 1.0f;

    private FCk_Handle_Transform _Transform;
    private int32 _UpdateCount = 0;
    private bool _Bound = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto InitialXf = FTransform::Identity;
        InitialXf.SetLocation(ExpectedLocation);
        _Transform = utils_transform::Add(LocalHandle, InitialXf, ECk_Replication::DoesNotReplicate);

        // Let setup-side broadcasts flush before we start counting. Stays on the
        // legacy WaitOneFrame DELIBERATELY. Two reasons it resists both migrations:
        //   - a CONDITION is wrong: the counter is 0 and nothing becomes true, so
        //     any predicate returns on its first poll and lets a setup-side
        //     OnUpdate land inside the counted window;
        //   - WaitFrames is wrong at any count I can justify: this window is
        //     calibrated to 0.05s of WALL-CLOCK (~3 frames at 60fps). Shortening
        //     it to WaitFrames(2) made the bind + Request_ForceRefresh land while
        //     setup was still running, the refresh got absorbed into that pass,
        //     and no distinct OnUpdate ever broadcast - the test timed out waiting
        //     for a rebroadcast that legitimately never happened.
        WaitOneFrame(n"OnSetupSettled");
    }

    UFUNCTION()
    private void OnSetupSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        utils_transform::BindTo_OnUpdate(_Transform,
            FCk_Delegate_Transform_OnUpdate(this, n"OnTransformUpdate"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);
        _Bound = true;

        utils_transform::Request_ForceRefresh(_Transform);

        WaitUntil(n"Check_RefreshBroadcast", n"OnForceRefreshSettled");
    }

    // The rebroadcast arriving IS the settling event. That it arrives EXACTLY
    // once - the contract, since the value is unchanged - stays an assertion, so
    // a double-broadcast regression is reported rather than hanging.
    UFUNCTION()
    private void Check_RefreshBroadcast(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_UpdateCount >= 1);
    }

    UFUNCTION()
    private void OnTransformUpdate(FCk_Handle_Transform InHandle, FTransform InTransform)
    {
        if (_Bound) { _UpdateCount++; }
    }

    UFUNCTION()
    private void OnForceRefreshSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_UpdateCount, 1,
            "Request_ForceRefresh should fire exactly one OnUpdate broadcast even when value is unchanged");

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(_Transform);
        Assert_True(ActualLoc.Equals(ExpectedLocation, PositionToleranceCm),
            f"ForceRefresh must not alter the stored value; expected {ExpectedLocation}, got {ActualLoc}");

        FinishSuccess();
    }
}
