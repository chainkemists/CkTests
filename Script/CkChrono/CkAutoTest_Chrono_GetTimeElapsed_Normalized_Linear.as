// Language=angelscript

//============================================================================
// CK CHRONO - AUTOMATION TEST: GET_TIMEELAPSED NORMALIZED LINEAR
//============================================================================
//
// Pins the [0, 1] normalization contract: Get_TimeElapsed with
// ECk_NormalizationPolicy::ZeroToOne returns 0 at start, 0.5 at half,
// 1.0 at completion (within float epsilon).
//
// This is the "alpha" accessor - what consumers use to drive interpolation
// against a chrono-driven timer/tween. Pinning it linear at the three
// boundary points catches any future change that breaks the contract.
//============================================================================

class UCk_AutoTest_Chrono_GetTimeElapsed_Normalized_Linear : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Tol = 0.001f;

        auto Chrono = FCk_Chrono();
        Chrono._GoalValue = FCk_Time(2.0f);

        // alpha at start
        auto Alpha0 = utils_chrono::Get_TimeElapsed(Chrono, ECk_NormalizationPolicy::ZeroToOne).Get_Seconds();
        Assert_True(Math::Abs(Alpha0) < Tol,
            f"Get_TimeElapsed(ZeroToOne) at start must be 0 (got {Alpha0})");

        // alpha at half
        utils_chrono::Tick(Chrono, FCk_Time(1.0f));
        auto AlphaHalf = utils_chrono::Get_TimeElapsed(Chrono, ECk_NormalizationPolicy::ZeroToOne).Get_Seconds();
        Assert_True(Math::Abs(AlphaHalf - 0.5f) < Tol,
            f"Get_TimeElapsed(ZeroToOne) at half (1.0/2.0) must be 0.5 (got {AlphaHalf})");

        // alpha at full
        utils_chrono::Tick(Chrono, FCk_Time(1.0f));
        auto Alpha1 = utils_chrono::Get_TimeElapsed(Chrono, ECk_NormalizationPolicy::ZeroToOne).Get_Seconds();
        Assert_True(Math::Abs(Alpha1 - 1.0f) < Tol,
            f"Get_TimeElapsed(ZeroToOne) at completion must be 1.0 (got {Alpha1})");

        FinishSuccess();
    }
}
