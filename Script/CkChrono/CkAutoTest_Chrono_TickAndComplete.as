// Language=angelscript

//============================================================================
// CK CHRONO — AUTOMATION TEST: TICK / RESET / COMPLETE
//============================================================================
//
// Smoke test for FCk_Chrono direct manipulation (no entity required).
// FCk_Chrono is the entity-free countdown/accumulator primitive that
// CkTimer is built on top of.
//
//   1. Construct FCk_Chrono with goal 1.0s.
//   2. Get_IsDone returns false at construction (elapsed=0).
//   3. Tick by 0.5s → still not done; Get_TimeElapsed reflects 0.5.
//   4. Tick by 0.6s → now done (elapsed clamped to goal).
//   5. Reset → Get_IsDone false again, Get_TimeElapsed back to 0.
//   6. Complete → Get_IsDone true, Get_TimeElapsed equals goal.
//
// All operations resolve synchronously in DoBeginPlay — chrono is a
// plain value, no processor/world involvement.
//============================================================================

class UCk_AutoTest_Chrono_TickAndComplete : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Tol = 0.001f;

        // FCk_Chrono's explicit FCk_Time constructor isn't exposed to AS —
        // only the default and copy constructors are. Default-construct
        // and set the goal via the BlueprintReadWrite _GoalValue field.
        auto Chrono = FCk_Chrono();
        Chrono._GoalValue = FCk_Time(1.0f);

        Assert_True(!utils_chrono::Get_IsDone(Chrono),
            "Fresh chrono should report IsDone=false");

        utils_chrono::Tick(Chrono, FCk_Time(0.5f));
        Assert_True(!utils_chrono::Get_IsDone(Chrono),
            "After Tick(0.5) on a 1.0 goal, IsDone should still be false");
        auto Elapsed1 = utils_chrono::Get_TimeElapsed(Chrono).Get_Seconds();
        Assert_True(Math::Abs(Elapsed1 - 0.5f) < Tol,
            f"After Tick(0.5), TimeElapsed should be 0.5 (got {Elapsed1})");

        utils_chrono::Tick(Chrono, FCk_Time(0.6f));
        Assert_True(utils_chrono::Get_IsDone(Chrono),
            "After Tick(0.6) totalling 1.1 against a 1.0 goal, IsDone should be true (clamped to goal)");

        utils_chrono::Reset(Chrono);
        Assert_True(!utils_chrono::Get_IsDone(Chrono),
            "After Reset, IsDone should return to false");
        auto ElapsedAfterReset = utils_chrono::Get_TimeElapsed(Chrono).Get_Seconds();
        Assert_True(Math::Abs(ElapsedAfterReset) < Tol,
            f"After Reset, TimeElapsed should be 0 (got {ElapsedAfterReset})");

        utils_chrono::Complete(Chrono);
        Assert_True(utils_chrono::Get_IsDone(Chrono),
            "After Complete, IsDone should be true");
        auto ElapsedAfterComplete = utils_chrono::Get_TimeElapsed(Chrono).Get_Seconds();
        Assert_True(Math::Abs(ElapsedAfterComplete - 1.0f) < Tol,
            f"After Complete, TimeElapsed should equal goal (1.0, got {ElapsedAfterComplete})");

        FinishSuccess();
    }
}
