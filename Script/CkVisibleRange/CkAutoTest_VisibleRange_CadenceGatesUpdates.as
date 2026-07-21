// Language=angelscript

//============================================================================
// CK VISIBLE RANGE — AUTOMATION TEST: cadence gates re-evaluation
//============================================================================
//
// UpdateInterval = 0.5s. Verifies two things in one pass:
//   1. The FIRST tick after Add evaluates immediately regardless of the
//      configured interval (Add seeds its Chrono via .Complete(), not
//      fresh/zero — without that seed the entity would show the default
//      visible state for up to a full interval before ever being evaluated).
//      Distance is set out-of-range BEFORE the first tick specifically so the
//      correct answer (hidden) differs from the default (visible) — otherwise
//      this property wouldn't actually be exercised, since an un-evaluated
//      entity and a correctly-evaluated in-range entity look identical.
//   2. Once armed, ck::cadence::ShouldRun genuinely SKIPS re-evaluation
//      before the interval elapses, and picks it up once it does.
//
// Timing is measured via real CkTimer instances (utils_timer, the same
// accumulated-DeltaT primitive the engine itself uses), never frame counts —
// a nullrhi/headless test run can tick far faster than real-time, so N
// frames is not a reliable proxy for N seconds.
//============================================================================

class UCk_AutoTest_VisibleRange_CadenceGatesUpdates : UCk_AutoTest_Base
{
    // Default (5.0s) comfortably covers this test's ~0.75s of real elapsed time; kept explicit
    // as documentation of that budget rather than because a tighter/looser bound is needed.
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;
    private FCk_Handle_VisibleRange _VR;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Entity = LocalHandle;

        auto Params = FCk_Fragment_VisibleRange_ParamsData(500.0f);
        Params.Set_UpdateInterval(FCk_Time(0.5));
        _VR = utils_visible_range::Add(LocalHandle, Params);

        // Set out-of-range BEFORE the first tick ever evaluates anything. This is what makes the
        // next assertion actually discriminate the .Complete()-seed fix: the default (un-evaluated)
        // state is visible/false, same as a correctly-evaluated in-range result — so if distance
        // were left at its in-range default (0), "visible" would pass whether or not the first
        // tick actually ran. Only by making the correct answer (hidden) differ from the default
        // (visible) does the assertion below prove the first tick evaluated at all.
        utils_visible_range::Update_Distance(_VR, 1000.0f);

        WaitOneFrame(n"OnFirstTickSettled");
    }

    UFUNCTION()
    private void OnFirstTickSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_visible_range::Get_IsHidden(_VR),
            "Should be hidden immediately after Add (distance 1000, beyond MaxRange 500) — the " +
            "first tick must not be deferred by the 0.5s cadence interval (the .Complete()-seed fix)");

        // Bring it back in range, then check the VERY NEXT tick — one frame's real elapsed time
        // cannot be anywhere close to the 0.5s interval, so this proves cadence gates re-evaluation
        // rather than merely never having evaluated in the first place (the distinction the
        // previous assertion already nailed down).
        utils_visible_range::Update_Distance(_VR, 100.0f);

        // Under the 0.5s interval — cadence should GATE this, no re-evaluation yet.
        auto ShortWaitParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.1));
        ShortWaitParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto ShortTimer = utils_timer::Add(_Entity, ShortWaitParams);
        ShortTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnShortWaitDone"));
    }

    UFUNCTION()
    private void OnShortWaitDone(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_visible_range::Get_IsHidden(_VR),
            "Cadence should have gated the re-evaluation: only 0.1s elapsed of the 0.5s interval, " +
            "but distance was moved back in range (still stale/hidden)");

        // Over the 0.5s interval — cadence should now have re-evaluated.
        auto LongWaitParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.6));
        LongWaitParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto LongTimer = utils_timer::Add(_Entity, LongWaitParams);
        LongTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnLongWaitDone"));
    }

    UFUNCTION()
    private void OnLongWaitDone(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_visible_range::Get_IsHidden(_VR),
            "Cadence interval has now elapsed (~0.7s since Update_Distance) — should be visible");
        FinishSuccess();
    }
}
