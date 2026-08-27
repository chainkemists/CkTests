// Language=angelscript

//============================================================================
// CK CHRONO - AUTOMATION TEST: TICK PAST COMPLETION CLAMPS AT DURATION
//============================================================================
//
// Pins the clamp-on-overshoot contract: a single Tick that pushes elapsed
// well past the goal results in elapsed == goal (clamped), not goal + delta.
// Get_IsDone is true.
//
// The existing TickAndComplete test asserts IsDone after a multi-Tick that
// crosses the goal but doesn't pin the elapsed clamp value. This test does.
//============================================================================

class UCk_AutoTest_Chrono_TickPastCompletion_ClampsAtDuration : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Tol = 0.001f;

        auto Chrono = FCk_Chrono();
        Chrono._GoalValue = FCk_Time(1.0f);

        // Single Tick of 5x the goal - should clamp at goal, not overshoot to 5.
        utils_chrono::Tick(Chrono, FCk_Time(5.0f));

        Assert_True(utils_chrono::Get_IsDone(Chrono),
            "After Tick(5.0) against a 1.0 goal, IsDone must be true");

        auto Elapsed = utils_chrono::Get_TimeElapsed(Chrono).Get_Seconds();
        Assert_True(Math::Abs(Elapsed - 1.0f) < Tol,
            f"After overshooting Tick, elapsed must clamp to goal (1.0, got {Elapsed})");

        auto Remaining = utils_chrono::Get_TimeRemaining(Chrono).Get_Seconds();
        Assert_True(Math::Abs(Remaining) < Tol,
            f"After overshooting Tick, remaining must clamp to 0 (got {Remaining})");

        FinishSuccess();
    }
}
